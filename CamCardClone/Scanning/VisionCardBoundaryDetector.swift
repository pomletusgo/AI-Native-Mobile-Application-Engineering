import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Vision

/// 校正后的名片图像。
struct CorrectedCardImage: Equatable {
    /// PNG 编码的图像数据。
    let imageData: Data
    /// 校正后图像的像素尺寸。
    let pixelSize: CGSize
}

/// 名片区域校正能力。把检测到的四边形摆正成矩形，供 OCR 使用。
protocol CardBoundaryCorrecting: AnyObject {
    func correctCard(in imageData: Data, quad: CardQuad) throws -> CorrectedCardImage
}

/// 基于 Vision 的名片区域检测与校正实现。
///
/// 检测使用 `VNDetectRectanglesRequest`（矩形检测，对干净背景上的名片最稳），
/// 校正使用 `CIPerspectiveCorrection` 把任意四边形拉成矩形，再按几何长宽比做 90° 摆正。
/// 检测结果先经 `CardQuad.isReliable()` 判定：不可靠的候选不丢弃，而是以
/// `.unreliable` 返回，交给上层提示「重拍或手动调整」，对应规格里
/// 「不得直接把整张图片当作名片」。
final class VisionCardBoundaryDetector: CardBoundaryDetecting, CardBoundaryCorrecting {

    private let minimumAspectRatio: Float
    private let minimumSize: Float
    private let quadratureTolerance: Float
    private let maximumObservations: Int

    init(
        minimumAspectRatio: Float = 0.3,
        minimumSize: Float = 0.18,
        quadratureTolerance: Float = 30,
        maximumObservations: Int = 4
    ) {
        self.minimumAspectRatio = minimumAspectRatio
        self.minimumSize = minimumSize
        self.quadratureTolerance = quadratureTolerance
        self.maximumObservations = maximumObservations
    }

    /// 在后台队列执行检测，避免阻塞调用方。
    func detectCard(in imageData: Data) async throws -> CardDetectionOutcome {
        let configuration = (minimumAspectRatio, minimumSize, quadratureTolerance, maximumObservations)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let outcome = try VisionCardBoundaryDetector.detect(
                        imageData: imageData,
                        minimumAspectRatio: configuration.0,
                        minimumSize: configuration.1,
                        quadratureTolerance: configuration.2,
                        maximumObservations: configuration.3
                    )
                    continuation.resume(returning: outcome)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// 同步执行一次检测，抽成静态方法便于在测试中直接调用。
    static func detect(
        imageData: Data,
        minimumAspectRatio: Float,
        minimumSize: Float,
        quadratureTolerance: Float,
        maximumObservations: Int
    ) throws -> CardDetectionOutcome {
        guard
            let source = CGImageSourceCreateWithData(imageData as CFData, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw CardBoundaryError.invalidImageData
        }

        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = minimumAspectRatio
        request.minimumSize = minimumSize
        request.quadratureTolerance = quadratureTolerance
        request.maximumObservations = maximumObservations
        request.minimumConfidence = 0.5

        do {
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        } catch {
            throw CardBoundaryError.detectionFailed(reason: error.localizedDescription)
        }

        let quads = (request.results ?? []).map(CardQuad.init(observation:))
        // 多个候选时取面积最大的一个，通常是真正覆盖名片的那张。
        guard let best = quads.max(by: { $0.area < $1.area }) else {
            return .notFound
        }
        return outcome(for: best)
    }

    /// 依据可靠性把候选四边形分成「可用」与「需人工处理」；纯函数，便于单测。
    static func outcome(for quad: CardQuad) -> CardDetectionOutcome {
        quad.isReliable() ? .detected(quad) : .unreliable(quad)
    }

    /// 透视校正 + 90° 摆正，输出 PNG 数据。
    func correctCard(in imageData: Data, quad: CardQuad) throws -> CorrectedCardImage {
        try VisionCardBoundaryDetector.correct(
            imageData: imageData,
            quad: quad,
            rotation: quad.suggestedRotation()
        )
    }

    /// 同步执行一次校正，抽成静态方法便于在测试中直接调用。
    static func correct(
        imageData: Data,
        quad: CardQuad,
        rotation: CardRotation
    ) throws -> CorrectedCardImage {
        guard let sourceImage = CIImage(data: imageData) else {
            throw CardBoundaryError.invalidImageData
        }
        let imageSize = sourceImage.extent.size
        let corners = quad.pixelCorners(in: imageSize)

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else {
            throw CardBoundaryError.correctionFailed(reason: "透视校正滤镜不可用。")
        }
        filter.setValue(sourceImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: corners.topLeft), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: corners.topRight), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: corners.bottomRight), forKey: "inputBottomRight")
        filter.setValue(CIVector(cgPoint: corners.bottomLeft), forKey: "inputBottomLeft")

        guard let corrected = filter.outputImage else {
            throw CardBoundaryError.correctionFailed(reason: "透视校正未产出图像。")
        }

        let oriented: CIImage
        switch rotation {
        case .none:
            oriented = corrected
        case .quarterTurnClockwise:
            // Core Image 的坐标原点在左下角，正角度为逆时针，因此顺时针 90° 用 -π/2。
            // 旋转后 extent 原点会平移，需要归一化回 (0, 0)。
            let rotated = corrected.transformed(by: CGAffineTransform(rotationAngle: -.pi / 2))
            oriented = rotated.transformed(
                by: CGAffineTransform(
                    translationX: -rotated.extent.origin.x,
                    y: -rotated.extent.origin.y
                )
            )
        }

        // 用软件渲染器，避免在无 GPU 的环境（如 CI）上因 Metal 不可用而失败。
        let context = CIContext(options: [.useSoftwareRenderer: true])
        guard let outputCGImage = context.createCGImage(oriented, from: oriented.extent) else {
            throw CardBoundaryError.correctionFailed(reason: "无法渲染校正后的图像。")
        }

        let data = try encodePNG(outputCGImage)
        return CorrectedCardImage(imageData: data, pixelSize: outputCGImage.size)
    }

    private static func encodePNG(_ image: CGImage) throws -> Data {
        let buffer = NSMutableData()
        let pngType = "public.png" as CFString
        guard
            let destination = CGImageDestinationCreateWithData(buffer, pngType, 1, nil)
        else {
            throw CardBoundaryError.correctionFailed(reason: "无法创建图像编码器。")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CardBoundaryError.correctionFailed(reason: "图像编码失败。")
        }
        return buffer as Data
    }
}

private extension CardQuad {
    /// 由 Vision 的矩形观察结果构造；`VNRectangleObservation` 的角点已是
    /// 左下角原点的归一化坐标，与 `CardQuad` 约定一致。
    init(observation: VNRectangleObservation) {
        self.init(
            topLeft: observation.topLeft,
            topRight: observation.topRight,
            bottomRight: observation.bottomRight,
            bottomLeft: observation.bottomLeft
        )
    }
}
