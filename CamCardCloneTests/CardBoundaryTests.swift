import CoreGraphics
import ImageIO
import XCTest
@testable import CamCardClone

/// 名片区域检测与校正的单元测试。
///
/// 覆盖 card-scanner 的 Card boundary detection 需求（T06）：
/// 「给出覆盖名片主要区域且不含大块背景的检测框」「倾斜名片做摆正或透视校正」
/// 「检测不可靠时提示重拍或手动调整，不把整张图片当作名片」。
///
/// 几何判定（面积、长宽比、可靠性、旋转方向、像素映射）全部是纯函数，逐条断言；
/// 依赖 Vision / Core Image 的部分只覆盖可确定的两端——不可解码的图片数据会失败、
/// 无矩形候选的纯白图片返回 `.notFound`、校正对合成图像产出可解码结果。
/// 真实名片照片上的检测成功率属人工验收（见 `docs/验证报告.md 附录 A`）。
final class CardBoundaryTests: XCTestCase {

    // MARK: - Fixtures

    /// 单测里的四边形都构造在归一化坐标里、不涉及真实照片，取正方形图片尺寸即可让像素长宽比
    /// 等于几何长宽比，从而只考察几何本身；「横版照片把比例压扁」的场景见
    /// `testReliableForCardInLandscapePhoto` 与 `testDiagnoseCorpusDetection`。
    private let squareImageSize = CGSize(width: 1000, height: 1000)

    /// 构造轴对齐矩形的四边形，`x`/`y` 为左下角（Vision 坐标原点在左下角）。
    private func rectQuad(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> CardQuad {
        CardQuad(
            topLeft: CGPoint(x: x, y: y + height),
            topRight: CGPoint(x: x + width, y: y + height),
            bottomRight: CGPoint(x: x + width, y: y),
            bottomLeft: CGPoint(x: x, y: y)
        )
    }

    /// 生成一张 400×250 的白底深灰矩形合成图片，深灰矩形占 0.8×0.6，模拟「干净背景上的名片」。
    private func makeCardImageData() -> Data {
        let width = 400
        let height = 250
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return Data()
        }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.setFillColor(CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 40, y: 50, width: 320, height: 150))
        guard let image = context.makeImage() else { return Data() }

        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            buffer,
            "public.png" as CFString,
            1,
            nil
        ) else {
            return Data()
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return Data() }
        return buffer as Data
    }

    /// 生成一张纯白图片，用来验证「可读但无矩形候选」的检测路径。
    private func makeBlankImageData(width: Int = 160, height: Int = 120) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return Data()
        }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        guard let image = context.makeImage() else { return Data() }

        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            buffer,
            "public.png" as CFString,
            1,
            nil
        ) else {
            return Data()
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return Data() }
        return buffer as Data
    }

    private func decodedSize(of imageData: Data) -> CGSize? {
        guard
            let source = CGImageSourceCreateWithData(imageData as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }
        return CGSize(width: image.width, height: image.height)
    }

    // MARK: - 几何：面积

    func testAreaMatchesRectangleBounds() {
        let quad = rectQuad(x: 0.1, y: 0.2, width: 0.8, height: 0.5)

        XCTAssertEqual(quad.area, 0.4, accuracy: 1e-9)
        XCTAssertGreaterThan(quad.signedArea, 0)
    }

    func testSignedAreaIsNegativeWhenCornerOrderIsReversed() {
        // 角序反转：bottomLeft → bottomRight → topRight → topLeft。
        let reversed = CardQuad(
            topLeft: CGPoint(x: 0.1, y: 0.2),
            topRight: CGPoint(x: 0.9, y: 0.2),
            bottomRight: CGPoint(x: 0.9, y: 0.7),
            bottomLeft: CGPoint(x: 0.1, y: 0.7)
        )

        XCTAssertLessThan(reversed.signedArea, 0)
        XCTAssertEqual(reversed.area, 0.4, accuracy: 1e-9)
    }

    func testDegenerateQuadHasZeroAspectRatio() {
        let point = CGPoint(x: 0.5, y: 0.5)
        let degenerate = CardQuad(
            topLeft: point,
            topRight: point,
            bottomRight: point,
            bottomLeft: point
        )

        XCTAssertEqual(degenerate.aspectRatio(in: squareImageSize), 0)
        XCTAssertFalse(degenerate.isReliable(in: squareImageSize))
    }

    // MARK: - 几何：长宽比

    func testAspectRatioUsesLongestEdgeOverShortestEdge() {
        let landscape = rectQuad(x: 0.1, y: 0.2, width: 0.8, height: 0.5)

        XCTAssertEqual(landscape.aspectRatio(in: squareImageSize), 1.6, accuracy: 1e-9)
    }

    // MARK: - 可靠性判定

    func testReliableForCardSizedLandscapeQuad() {
        let quad = rectQuad(x: 0.1, y: 0.1, width: 0.8, height: 0.5)

        XCTAssertTrue(quad.isReliable(in: squareImageSize))
    }

    func testReliableForCardInLandscapePhoto() {
        // 回归：1400×900 的横版照片里，真实比例 1.66 的名片在归一化长宽比口径下只剩约 1.07，
        // 被 1.15 的下限整批判成「不像名片」，于是相册导入的正常名片全部退到手动调整提示页
        // （M18/M19 失败的根因，数字见 testDiagnoseCorpusDetection 的语料报告）。此处用 TC01 的
        // 实际检测角点，锁住「长宽比必须在像素空间量」这条约束。
        let quad = rectQuad(x: 0.089, y: 0.113, width: 0.823, height: 0.771)
        let imageSize = CGSize(width: 1400, height: 900)

        XCTAssertEqual(quad.aspectRatio(in: imageSize), 1.660, accuracy: 0.01)
        XCTAssertTrue(quad.isReliable(in: imageSize))
        XCTAssertEqual(VisionCardBoundaryDetector.outcome(for: quad, in: imageSize), .detected(quad))
    }

    func testUnreliableWhenRegionIsTooSmall() {
        // 面积 0.02，远低于 0.12，多半是误检的局部纹理。
        let quad = rectQuad(x: 0.1, y: 0.1, width: 0.2, height: 0.1)

        XCTAssertFalse(quad.isReliable(in: squareImageSize))
    }

    func testUnreliableWhenRegionCoversWholeImage() {
        // 几乎铺满整幅图，多半把背景边界当成了名片，规格要求不得整图当名片。
        let quad = rectQuad(x: 0, y: 0, width: 1, height: 1)

        XCTAssertFalse(quad.isReliable(in: squareImageSize))
    }

    func testUnreliableWhenAspectRatioIsNotCardLike() {
        // 正方形轮廓不在名片比例范围内，多半是屏幕或标签边框。
        let square = rectQuad(x: 0.1, y: 0.1, width: 0.5, height: 0.5)

        XCTAssertFalse(square.isReliable(in: squareImageSize))
    }

    // MARK: - 像素映射

    func testPixelCornersScaleNormalizedPoints() {
        let quad = rectQuad(x: 0.25, y: 0.5, width: 0.5, height: 0.25)
        let corners = quad.pixelCorners(in: CGSize(width: 400, height: 200))

        XCTAssertEqual(corners.topLeft, CGPoint(x: 100, y: 150))
        XCTAssertEqual(corners.topRight, CGPoint(x: 300, y: 150))
        XCTAssertEqual(corners.bottomRight, CGPoint(x: 300, y: 100))
        XCTAssertEqual(corners.bottomLeft, CGPoint(x: 100, y: 100))
    }

    // MARK: - 结果分类

    func testOutcomeIsDetectedForReliableQuad() {
        let quad = rectQuad(x: 0.1, y: 0.1, width: 0.8, height: 0.5)

        XCTAssertEqual(VisionCardBoundaryDetector.outcome(for: quad, in: squareImageSize), .detected(quad))
    }

    func testOutcomeIsUnreliableForImplausibleQuad() {
        let quad = rectQuad(x: 0, y: 0, width: 1, height: 1)

        XCTAssertEqual(VisionCardBoundaryDetector.outcome(for: quad, in: squareImageSize), .unreliable(quad))
    }

    func testOutcomesAreDistinct() {
        let quad = rectQuad(x: 0.1, y: 0.1, width: 0.8, height: 0.5)

        XCTAssertNotEqual(CardDetectionOutcome.detected(quad), .unreliable(quad))
        XCTAssertNotEqual(CardDetectionOutcome.notFound, .detected(quad))
    }

    // MARK: - 错误文案

    func testErrorsCarryReadableDescriptions() {
        XCTAssertNotNil(CardBoundaryError.invalidImageData.errorDescription)
        XCTAssertEqual(
            CardBoundaryError.detectionFailed(reason: "超时").errorDescription,
            "名片区域检测失败：超时"
        )
        XCTAssertEqual(
            CardBoundaryError.correctionFailed(reason: "滤镜缺失").errorDescription,
            "名片校正失败：滤镜缺失"
        )
    }

    // MARK: - Vision 检测：可确定的两端

    func testDetectRejectsUndecodableImageData() {
        XCTAssertThrowsError(
            try VisionCardBoundaryDetector.detect(
                imageData: Data([0x00, 0x01, 0x02, 0x03]),
                minimumAspectRatio: 0.3,
                minimumSize: 0.18,
                quadratureTolerance: 30,
                maximumObservations: 4
            )
        ) { error in
            XCTAssertEqual(error as? CardBoundaryError, .invalidImageData)
        }
    }

    func testDetectReportsNotFoundForRectanglelessImage() throws {
        // 只有纯白底色，没有任何矩形候选，无法确定名片区域。
        let blankData = makeBlankImageData(width: 160, height: 120)
        XCTAssertFalse(blankData.isEmpty, "测试图片应能成功编码为 PNG")

        let outcome = try VisionCardBoundaryDetector.detect(
            imageData: blankData,
            minimumAspectRatio: 0.3,
            minimumSize: 0.18,
            quadratureTolerance: 30,
            maximumObservations: 4
        )

        XCTAssertEqual(outcome, .notFound)
    }

    func testAsyncDetectPropagatesInvalidImageError() async {
        let detector = VisionCardBoundaryDetector()

        do {
            _ = try await detector.detectCard(in: Data([0xFF]))
            XCTFail("不可解码的图片数据应以 invalidImageData 失败")
        } catch let error as CardBoundaryError {
            XCTAssertEqual(error, .invalidImageData)
        } catch {
            XCTFail("出现了预期之外的错误类型：\(error)")
        }
    }

    // MARK: - Core Image 校正

    func testCorrectProducesDecodableImage() throws {
        let imageData = makeCardImageData()
        XCTAssertFalse(imageData.isEmpty)
        let quad = rectQuad(x: 0.1, y: 0.2, width: 0.8, height: 0.6)

        let result = try VisionCardBoundaryDetector.correct(imageData: imageData, quad: quad)

        XCTAssertFalse(result.imageData.isEmpty)
        let size = decodedSize(of: result.imageData)
        XCTAssertNotNil(size)
        XCTAssertEqual(result.pixelSize, size ?? .zero)
        // 四边形在 400×250 的图里占 0.8×0.6，校正后应接近 320×150。
        XCTAssertEqual(result.pixelSize.width, 320, accuracy: 2)
        XCTAssertEqual(result.pixelSize.height, 150, accuracy: 2)
    }

    func testCorrectStraightensRotatedQuadToAxisAlignedBounds() throws {
        // 旋转过的四边形（上边略窄于下边），校正后宽度应回落到与下边一致。
        let imageData = makeCardImageData()
        let tilted = CardQuad(
            topLeft: CGPoint(x: 0.15, y: 0.80),
            topRight: CGPoint(x: 0.85, y: 0.80),
            bottomRight: CGPoint(x: 0.90, y: 0.20),
            bottomLeft: CGPoint(x: 0.10, y: 0.20)
        )

        let result = try VisionCardBoundaryDetector.correct(imageData: imageData, quad: tilted)

        XCTAssertFalse(result.imageData.isEmpty)
        XCTAssertGreaterThan(result.pixelSize.width, result.pixelSize.height)
    }

    func testCorrectRejectsUndecodableImageData() {
        let quad = rectQuad(x: 0.1, y: 0.2, width: 0.8, height: 0.6)

        XCTAssertThrowsError(
            try VisionCardBoundaryDetector.correct(
                imageData: Data([0xFF, 0xFE]),
                quad: quad
            )
        ) { error in
            XCTAssertEqual(error as? CardBoundaryError, .invalidImageData)
        }
    }

    func testCorrectCardKeepsDetectedOrientation() throws {
        // 竖版四边形不做自动 90° 旋转，输出仍为竖版，避免误转破坏竖版名片。
        let imageData = makeCardImageData()
        let portrait = rectQuad(x: 0.2, y: 0.05, width: 0.4, height: 0.8)
        let detector = VisionCardBoundaryDetector()

        let result = try detector.correctCard(in: imageData, quad: portrait)

        XCTAssertGreaterThan(result.pixelSize.height, result.pixelSize.width)
        XCTAssertEqual(result.pixelSize.width, 160, accuracy: 2)
        XCTAssertEqual(result.pixelSize.height, 200, accuracy: 2)
    }

    // MARK: - 诊断：合成语料上的矩形检测表现

    /// 逐张打印 `testcards/images/TC01…TC30.png` 的矩形检测结果，作为「检测判据有没有把正常
    /// 名片挡在门外」的常设体检。
    ///
    /// 每行给出图片像素尺寸、三态结果、候选四边形的归一化面积、像素空间长宽比与四个角点。
    /// 2026-11-01 就是靠这份报告定位到问题的：30 张语料的像素长宽比是 1.59…1.69（正常名片比例），
    /// 而按归一化坐标算出来只有 1.03…1.08，被 `isReliable()` 的 1.15 下限整批判成不可靠，
    /// 相册导入的正常名片因此全部退到手动调整提示页。长宽比改在像素空间量之后，这份报告
    /// 应显示 30 张全部 `detected`。
    ///
    /// 只读语料、不写回数据集，故随常规单测一起跑；仓库里没有 `testcards/images` 时跳过。
    /// 单独跑：
    /// `xcodebuild test … -only-testing:CamCardCloneTests/CardBoundaryTests/testDiagnoseCorpusDetection`
    /// 报告同时打印到测试日志并写到仓库根的 `detect-corpus.txt`；CI 的单测作业会把带
    /// `DETECTCORPUS` 前缀的行提升为 notice 注解，便于在没有仓库授权令牌时读回。
    func testDiagnoseCorpusDetection() throws {
        let repositoryRoot = FieldExtractionEvaluator.repositoryRoot(sourceFilePath: #filePath)
        let imagesDirectory = repositoryRoot.appendingPathComponent("testcards/images")
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: imagesDirectory.path),
            "语料目录不存在，跳过：\(imagesDirectory.path)"
        )

        let names = try FileManager.default
            .contentsOfDirectory(atPath: imagesDirectory.path)
            .filter { $0.hasPrefix("TC") && $0.hasSuffix(".png") }
            .sorted()
        XCTAssertFalse(names.isEmpty, "语料目录里没有 TCxx.png：\(imagesDirectory.path)")

        var lines: [String] = []
        var detectedCount = 0
        var unreliableCount = 0
        var notFoundCount = 0

        for name in names {
            let data = try Data(contentsOf: imagesDirectory.appendingPathComponent(name))
            let size = decodedSize(of: data) ?? .zero
            let outcome = try VisionCardBoundaryDetector.detect(
                imageData: data,
                minimumAspectRatio: 0.3,
                minimumSize: 0.18,
                quadratureTolerance: 30,
                maximumObservations: 4
            )

            let geometry: String
            switch outcome {
            case .detected(let quad):
                detectedCount += 1
                geometry = describe(quad, in: size)
            case .unreliable(let quad):
                unreliableCount += 1
                geometry = describe(quad, in: size)
            case .notFound:
                notFoundCount += 1
                geometry = "无矩形候选"
            }
            lines.append(
                "DETECTCORPUS \(String(name.dropLast(4))) \(Int(size.width))x\(Int(size.height)) "
                    + "\(outcomeLabel(outcome)) \(geometry)"
            )
        }

        lines.append(
            "DETECTCORPUS 合计 共\(names.count)张 detected=\(detectedCount) "
                + "unreliable=\(unreliableCount) notFound=\(notFoundCount)"
        )

        let report = lines.joined(separator: "\n")
        print(report)
        try? report.write(
            to: repositoryRoot.appendingPathComponent("detect-corpus.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func outcomeLabel(_ outcome: CardDetectionOutcome) -> String {
        switch outcome {
        case .detected: return "detected"
        case .unreliable: return "unreliable"
        case .notFound: return "notFound"
        }
    }

    /// 面积、像素空间长宽比与四个角点，并标出两条判据各自的通过情况。
    private func describe(_ quad: CardQuad, in imageSize: CGSize) -> String {
        let areaOK = (0.12...0.98).contains(quad.area)
        let aspectRatio = quad.aspectRatio(in: imageSize)
        let aspectOK = (1.15...3.6).contains(aspectRatio)
        let corners = quad.corners
            .map { String(format: "(%.3f,%.3f)", Double($0.x), Double($0.y)) }
            .joined(separator: " ")
        return "面积=\(String(format: "%.3f", Double(quad.area)))[合格:\(areaOK)]"
            + " 长宽比=\(String(format: "%.3f", Double(aspectRatio)))[合格:\(aspectOK)]"
            + " 角点=\(corners)"
    }
}
