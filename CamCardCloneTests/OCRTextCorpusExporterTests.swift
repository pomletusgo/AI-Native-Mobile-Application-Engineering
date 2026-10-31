import XCTest
@testable import CamCardClone

/// 用 `testcards/images/` 里的合成名片图片跑一次真实 OCR，把识别原文导出成
/// `testcards/ocr/<名片 ID>.txt`，供 `FieldExtractionEvaluatorTests` 统计字段级准确率（任务 4.4）。
///
/// ## 为什么写成「默认跳过」的用例
///
/// `FieldExtractionEvaluatorTests` 的评价对象是 `BusinessCardFieldParser` 在 **OCR 原文**上的输出，
/// 而 OCR 原文必须在有 Vision 的环境里跑出来。本机没有 Mac，因此这里能做的只是把导出动作
/// 固化成可复跑的用例：在 Mac 上带 `EXPORT_OCR_TEXT=1` 跑一次，产出 30 个 txt，提交后评价
/// 用例就会从 skip 转为真跑，并打印字段级准确率报告。
///
/// 默认跳过、需显式开启，与 UI 基线的 `RECORD_GOLDEN` 同一思路——避免 CI 里悄悄改写数据集。
///
/// ## 边界（如实声明）
///
/// - 这里对**整张图片**做识别，不经过「检测 → 透视校正」。理由是 4.4 衡量的是字段抽取器在
///   OCR 原文上的准确率（见 `FieldExtractionEvaluator` 的类型注释）；检测与校正的影响属于
///   T06 / T07，不计入该指标。端到端的识别效果另需按 `docs/UI验收清单.md` 在真机上验收。
/// - 图片是程序化渲染的合成名片，真实 OCR 质量要跑过才知道；渲染文字比真实拍照干净，
///   因此由它得到的准确率偏乐观。
final class OCRTextCorpusExporterTests: XCTestCase {

    /// 显式开启导出（`EXPORT_OCR_TEXT=1`）才执行，避免 CI 改写数据集。
    private static let optInFlag = "EXPORT_OCR_TEXT"

    func testExportOCRTextForWholeCorpus() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment[Self.optInFlag] == "1",
            "导出 OCR 原文是一次性引导步骤，需要显式设置 \(Self.optInFlag)=1 才执行"
        )

        let root = FieldExtractionEvaluator.repositoryRoot(sourceFilePath: #filePath)
        let imagesDirectory = root.appendingPathComponent("testcards/images")
        let outputDirectory = root.appendingPathComponent("testcards/ocr")
        let cards = try FieldExtractionEvaluator.loadGroundTruth(
            from: root.appendingPathComponent("testcards/ground_truth.json")
        )
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let service = VisionOCRService()
        var exported: [String] = []
        var problems: [String] = []

        for card in cards {
            let imageURL = imagesDirectory.appendingPathComponent("\(card.id).png")
            guard FileManager.default.fileExists(atPath: imageURL.path) else {
                problems.append("\(card.id)：缺少图片 \(imageURL.lastPathComponent)")
                continue
            }
            do {
                let imageData = try Data(contentsOf: imageURL)
                let result = try await service.recognizeText(in: imageData)
                let textURL = FieldExtractionEvaluator.ocrTextURL(cardID: card.id, repositoryRoot: root)
                try (result.rawText + "\n").write(to: textURL, atomically: true, encoding: .utf8)
                exported.append(card.id)
                print("  \(card.id)：\(result.lines.count) 行")
                if result.lines.count < 2 {
                    problems.append("\(card.id)：只识别到 \(result.lines.count) 行，原文「\(result.rawText)」")
                }
            } catch {
                problems.append("\(card.id)：识别失败 \(error.localizedDescription)")
            }
        }

        print("已导出 \(exported.count)/\(cards.count) 个 OCR 原文到 \(outputDirectory.path)")

        XCTAssertTrue(problems.isEmpty, "导出过程中有问题：\n" + problems.joined(separator: "\n"))
        XCTAssertEqual(exported.count, cards.count, "OCR 原文不完整，评价用例无法统计全部名片")
    }
}
