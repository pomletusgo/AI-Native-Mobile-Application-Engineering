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
/// 真实名片照片上的检测成功率属人工验收（见 `docs/UI验收清单.md`）。
final class CardBoundaryTests: XCTestCase {

    // MARK: - Fixtures

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

    /// 生成一张白底深灰矩形的合成图片，模拟「干净背景上的名片」。
    private func makeCardImageData(width: Int = 400, height: Int = 250) -> Data {
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
        let reversed = CardQuad(
            topLeft: CGPoint(x: 0.1, y: 0.7),
            topRight: CGPoint(x: 0.1, y: 0.2),
            bottomRight: CGPoint(x: 0.9, y: 0.2),
            bottomLeft: CGPoint(x: 0.9, y: 0.7)
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

        XCTAssertEqual(degenerate.aspectRatio, 0)
        XCTAssertFalse(degenerate.isReliable())
    }

    // MARK: - 几何：长宽比

    func testAspectRatioUsesLongestEdgeOverShortestEdge() {
        let landscape = rectQuad(x: 0.1, y: 0.2, width: 0.8, height: 0.5)

        XCTAssertEqual(landscape.aspectRatio, 1.6, accuracy: 1e-9)
    }

    // MARK: - 可靠性判定

    func testReliableForCardSizedLandscapeQuad() {
        let quad = rectQuad(x: 0.1, y: 0.1, width: 0.8, height: 0.5)

        XCTAssertTrue(quad.isReliable())
    }

    func testUnreliableWhenRegionIsTooSmall() {
        // 面积 0.02，远低于 0.12，多半是误检的局部纹理。
        let quad = rectQuad(x: 0.1, y: 0.1, width: 0.2, height: 0.1)

        XCTAssertFalse(quad.isReliable())
    }

    func testUnreliableWhenRegionCoversWholeImage() {
        // 几乎铺满整幅图，多半把背景边界当成了名片，规格要求不得整图当名片。
        let quad = rectQuad(x: 0, y: 0, width: 1, height: 1)

        XCTAssertFalse(quad.isReliable())
    }

    func testUnreliableWhenAspectRatioIsNotCardLike() {
        // 正方形轮廓不在名片比例范围内，多半是屏幕或标签边框。
        let square = rectQuad(x: 0.1, y: 0.1, width: 0.5, height: 0.5)

        XCTAssertFalse(square.isReliable())
    }

    // MARK: - 旋转建议

    func testLandscapeQuadNeedsNoRotation() {
        let landscape = rectQuad(x: 0.1, y: 0.2, width: 0.8, height: 0.5)

        XCTAssertEqual(landscape.suggestedRotation(), .none)
    }

    func testPortraitQuadSuggestsQuarterTurn() {
        let portrait = rectQuad(x: 0.2, y: 0.05, width: 0.4, height: 0.8)

        XCTAssertEqual(portrait.suggestedRotation(), .quarterTurnClockwise)
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

    func testCorrectedPixelSizeUsesLongerEdges() {
        let quad = rectQuad(x: 0.25, y: 0.5, width: 0.5, height: 0.25)
        let size = quad.correctedPixelSize(in: CGSize(width: 400, height: 200))

        XCTAssertEqual(size, CGSize(width: 200, height: 50))
    }

    // MARK: - 结果分类

    func testOutcomeIsDetectedForReliableQuad() {
        let quad = rectQuad(x: 0.1, y: 0.1, width: 0.8, height: 0.5)

        XCTAssertEqual(VisionCardBoundaryDetector.outcome(for: quad), .detected(quad))
    }

    func testOutcomeIsUnreliableForImplausibleQuad() {
        let quad = rectQuad(x: 0, y: 0, width: 1, height: 1)

        XCTAssertEqual(VisionCardBoundaryDetector.outcome(for: quad), .unreliable(quad))
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

        let result = try VisionCardBoundaryDetector.correct(
            imageData: imageData,
            quad: quad,
            rotation: .none
        )

        XCTAssertFalse(result.imageData.isEmpty)
        let size = decodedSize(of: result.imageData)
        XCTAssertNotNil(size)
        XCTAssertEqual(result.pixelSize, size ?? .zero)
        XCTAssertGreaterThan(result.pixelSize.width, result.pixelSize.height)
    }

    func testCorrectWithQuarterTurnSwapsOrientation() throws {
        let imageData = makeCardImageData()
        let quad = rectQuad(x: 0.1, y: 0.2, width: 0.8, height: 0.6)

        let landscape = try VisionCardBoundaryDetector.correct(
            imageData: imageData,
            quad: quad,
            rotation: .none
        )
        let portrait = try VisionCardBoundaryDetector.correct(
            imageData: imageData,
            quad: quad,
            rotation: .quarterTurnClockwise
        )

        XCTAssertGreaterThan(landscape.pixelSize.width, landscape.pixelSize.height)
        XCTAssertGreaterThan(portrait.pixelSize.height, portrait.pixelSize.width)
        XCTAssertEqual(landscape.pixelSize.width, portrait.pixelSize.height, accuracy: 1)
        XCTAssertEqual(landscape.pixelSize.height, portrait.pixelSize.width, accuracy: 1)
    }

    func testCorrectRejectsUndecodableImageData() {
        let quad = rectQuad(x: 0.1, y: 0.2, width: 0.8, height: 0.6)

        XCTAssertThrowsError(
            try VisionCardBoundaryDetector.correct(
                imageData: Data([0xFF, 0xFE]),
                quad: quad,
                rotation: .none
            )
        ) { error in
            XCTAssertEqual(error as? CardBoundaryError, .invalidImageData)
        }
    }

    func testCorrectCardUsesSuggestedRotation() throws {
        let imageData = makeCardImageData()
        let portrait = rectQuad(x: 0.2, y: 0.05, width: 0.4, height: 0.8)
        let detector = VisionCardBoundaryDetector()

        let result = try detector.correctCard(in: imageData, quad: portrait)

        XCTAssertGreaterThan(result.pixelSize.height, result.pixelSize.width)
    }
}
