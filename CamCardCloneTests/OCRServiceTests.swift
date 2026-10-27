import CoreGraphics
import ImageIO
import XCTest
@testable import CamCardClone

/// `OCRService` 相关单元测试。
///
/// 覆盖 card-scanner 的 Optical character recognition 需求（T07）：识别结果要产出**原始文本**、
/// 失败要能区分「图片不可读」与「没有文字」。
///
/// 这里只测不依赖真机的部分：阅读顺序整理、结果规范化、错误映射，以及对无效图片数据与
/// 无文字图片的两条真实 `VisionOCRService` 失败路径。真机拍摄、相册导入与倾斜名片的识别
/// 效果属人工验收（见 `docs/UI验收清单.md`），不在本文件覆盖范围。
final class OCRServiceTests: XCTestCase {

    // MARK: - Fixtures

    /// 构造一条识别结果，`y` 为矩形底边（Vision 坐标原点在左下角，y 越大越靠上）。
    private func line(
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        height: CGFloat = 0.05
    ) -> RecognizedLine {
        RecognizedLine(
            text: text,
            boundingBox: CGRect(x: x, y: y, width: 0.2, height: height)
        )
    }

    /// 生成一张纯白图片并编码为 PNG，用来验证「可读但无文字」的失败路径。
    private func makeBlankImageData(width: Int = 240, height: Int = 160) -> Data {
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

    // MARK: - 结果规范化

    func testResultTrimsWhitespaceAndDropsEmptyLines() {
        let result = OCRTextResult(lines: ["  张伟 ", "", "   ", "\t上海远景科技有限公司\n"])

        XCTAssertEqual(result.lines, ["张伟", "上海远景科技有限公司"])
        XCTAssertEqual(result.rawText, "张伟\n上海远景科技有限公司")
        XCTAssertFalse(result.isEmpty)
    }

    func testEmptyResultIsReportedAsEmpty() {
        let result = OCRTextResult(lines: ["", "   "])

        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(result.rawText, "")
    }

    // MARK: - 阅读顺序

    func testReadingOrderSortsTopRowBeforeBottomRow() {
        let shuffled = [
            line("手机: 138-0000-0001", x: 0.1, y: 0.45),
            line("上海远景科技有限公司", x: 0.1, y: 0.75),
            line("张伟", x: 0.1, y: 0.60),
        ]

        XCTAssertEqual(
            shuffled.sortedInReadingOrder().map(\.text),
            ["上海远景科技有限公司", "张伟", "手机: 138-0000-0001"]
        )
    }

    func testReadingOrderSortsLeftToRightWithinRow() {
        let shuffled = [
            line("伟", x: 0.30, y: 0.60),
            line("张", x: 0.10, y: 0.60),
        ]

        XCTAssertEqual(shuffled.sortedInReadingOrder().map(\.text), ["张", "伟"])
    }

    func testReadingOrderKeepsSlightlyMisalignedBlocksInSameRow() {
        // 同一行内存在 0.005 的纵向抖动，行高 0.05，容差 0.03，应仍归为同一行。
        let shuffled = [
            line("科技有限公司", x: 0.40, y: 0.605),
            line("上海远景", x: 0.10, y: 0.600),
        ]

        XCTAssertEqual(
            shuffled.sortedInReadingOrder().map(\.text),
            ["上海远景", "科技有限公司"]
        )
    }

    func testReadingOrderOfEmptyInputIsEmpty() {
        XCTAssertTrue([RecognizedLine]().sortedInReadingOrder().isEmpty)
    }

    // MARK: - 错误信息

    func testErrorsCarryReadableDescriptions() {
        XCTAssertNotNil(OCRError.invalidImageData.errorDescription)
        XCTAssertNotNil(OCRError.noTextFound.errorDescription)
        XCTAssertEqual(OCRError.failed(reason: "超时").errorDescription, "识别失败：超时")
    }

    // MARK: - VisionOCRService 失败路径

    func testRecognizeRejectsUndecodableImageData() {
        XCTAssertThrowsError(
            try VisionOCRService.recognize(
                imageData: Data([0x00, 0x01, 0x02, 0x03]),
                level: .accurate,
                languages: ["zh-Hans", "en-US"]
            )
        ) { error in
            XCTAssertEqual(error as? OCRError, .invalidImageData)
        }
    }

    func testRecognizeReportsNoTextFoundForTextlessImage() throws {
        let imageData = makeBlankImageData()
        XCTAssertFalse(imageData.isEmpty, "测试图片应能成功编码为 PNG")

        XCTAssertThrowsError(
            try VisionOCRService.recognize(
                imageData: imageData,
                level: .accurate,
                languages: ["zh-Hans", "en-US"]
            )
        ) { error in
            XCTAssertEqual(error as? OCRError, .noTextFound)
        }
    }

    func testAsyncRecognizePropagatesInvalidImageError() async {
        let service = VisionOCRService()

        do {
            _ = try await service.recognizeText(in: Data([0xFF]))
            XCTFail("不可解码的图片数据应以 invalidImageData 失败")
        } catch let error as OCRError {
            XCTAssertEqual(error, .invalidImageData)
        } catch {
            XCTFail("出现了预期之外的错误类型：\(error)")
        }
    }
}
