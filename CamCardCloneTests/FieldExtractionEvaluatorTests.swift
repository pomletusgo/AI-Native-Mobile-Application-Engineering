import XCTest
@testable import CamCardClone

/// `FieldExtractionEvaluator` 单元测试。
///
/// 覆盖的是**评价逻辑本身**：正确 / 抽错 / 漏抽 / 虚构 / 本应为空 五种判定、归一化规则、
/// ground truth 数据集读取，以及报告生成。对 30 张测试卡片的真实准确率统计需要 OCR 原文，
/// 见 `testFieldAccuracyOnCorpusIsPendingUntilOCRTextsExist`（数据未到位时跳过，不编造数字）。
final class FieldExtractionEvaluatorTests: XCTestCase {

    private static let sampleTruth = FieldExtractionEvaluator.GroundTruthCard(
        id: "TC01",
        values: [
            .name: "张伟",
            .company: "上海远景科技有限公司",
            .mobile: "138-0000-0001",
        ],
        absentKeys: [.phone, .fax, .website, .email, .jobTitle, .address]
    )

    // MARK: - 五种判定

    func testPerfectExtractionCountsCorrectAndAbsentFieldsWithoutErrors() {
        let actual = ExtractedCardFields(
            name: "张伟", company: "上海远景科技有限公司", mobile: "138-0000-0001"
        )

        let result = FieldExtractionEvaluator.compare(card: Self.sampleTruth, actual: actual)
        let summary = FieldExtractionEvaluator.summarize([result])

        XCTAssertEqual(result.fields.count, 9)
        XCTAssertEqual(result.fields.filter { $0.outcome == .correct }.count, 3)
        XCTAssertEqual(result.fields.filter { $0.outcome == .absent }.count, 6)
        XCTAssertEqual(summary.correctCount, 3)
        XCTAssertEqual(summary.evaluatedFieldCount, 9)
        XCTAssertEqual(summary.inventedCount, 0)
        XCTAssertEqual(summary.absentFieldCount, 6)
        XCTAssertEqual(summary.accuracy, 3.0 / 9.0, accuracy: 0.0001)
        XCTAssertEqual(summary.falsePositiveRate, 0, accuracy: 0.0001)
    }

    func testInventedFieldIsCountedAsFalsePositive() {
        let actual = ExtractedCardFields(
            name: "张伟",
            company: "上海远景科技有限公司",
            mobile: "138-0000-0001",
            website: "www.example.com"
        )

        let result = FieldExtractionEvaluator.compare(card: Self.sampleTruth, actual: actual)
        let summary = FieldExtractionEvaluator.summarize([result])

        let website = result.fields.first { $0.key == .website }
        XCTAssertEqual(website?.outcome, .invented)
        XCTAssertEqual(website?.expected, nil)
        XCTAssertEqual(website?.actual, "www.example.com")
        XCTAssertEqual(summary.inventedCount, 1)
        XCTAssertEqual(summary.falsePositiveRate, 1.0 / 6.0, accuracy: 0.0001)
        XCTAssertEqual(summary.accuracy, 3.0 / 9.0, accuracy: 0.0001)
    }

    func testMissingFieldIsCountedAsMissed() {
        let truth = FieldExtractionEvaluator.GroundTruthCard(id: "TC-X", values: [.name: "张伟"], absentKeys: [])

        let result = FieldExtractionEvaluator.compare(card: truth, actual: ExtractedCardFields())
        let summary = FieldExtractionEvaluator.summarize([result])

        XCTAssertEqual(result.fields.count, 1)
        XCTAssertEqual(result.fields.first?.outcome, .missed)
        XCTAssertEqual(summary.accuracy, 0, accuracy: 0.0001)
    }

    func testMismatchedValueIsCountedAsMismatch() {
        let truth = FieldExtractionEvaluator.GroundTruthCard(id: "TC-X", values: [.name: "张伟"], absentKeys: [])

        let result = FieldExtractionEvaluator.compare(card: truth, actual: ExtractedCardFields(name: "张伟明"))

        XCTAssertEqual(result.fields.first?.outcome, .mismatch)
        XCTAssertEqual(result.fields.first?.expected, "张伟")
        XCTAssertEqual(result.fields.first?.actual, "张伟明")
    }

    /// ground truth 没标注、也不在 `expectedAbsent` 里的字段不参与评价，避免把数据集缺口算成模型错误。
    func testUndeclaredFieldIsNotEvaluated() {
        let truth = FieldExtractionEvaluator.GroundTruthCard(id: "TC-X", values: [:], absentKeys: [.website])

        let result = FieldExtractionEvaluator.compare(card: truth, actual: ExtractedCardFields(email: "a@b.com"))

        XCTAssertEqual(result.fields.count, 1)
        XCTAssertEqual(result.fields.first?.key, .website)
        XCTAssertEqual(result.fields.first?.outcome, .absent)
    }

    // MARK: - 归一化

    func testPhoneComparisonIgnoresSeparators() {
        let truth = FieldExtractionEvaluator.GroundTruthCard(id: "TC-X", values: [.mobile: "138-0000-0001"], absentKeys: [])

        let result = FieldExtractionEvaluator.compare(card: truth, actual: ExtractedCardFields(mobile: "13800000001"))

        XCTAssertEqual(result.fields.first?.outcome, .correct)
        XCTAssertEqual(result.fields.first?.actual, "13800000001")
    }

    func testComparisonIgnoresCaseAndExtraSpacing() {
        let truth = FieldExtractionEvaluator.GroundTruthCard(
            id: "TC-X", values: [.company: "ABC Technologies"], absentKeys: []
        )

        let result = FieldExtractionEvaluator.compare(card: truth, actual: ExtractedCardFields(company: "abc   technologies"))

        XCTAssertEqual(result.fields.first?.outcome, .correct)
    }

    func testBlankExtractedValueIsTreatedAsMissing() {
        let truth = FieldExtractionEvaluator.GroundTruthCard(id: "TC-X", values: [.name: "张伟"], absentKeys: [])

        let result = FieldExtractionEvaluator.compare(card: truth, actual: ExtractedCardFields(name: "   "))

        XCTAssertEqual(result.fields.first?.outcome, .missed)
    }

    // MARK: - 数据集

    func testGroundTruthCorpusHasThirtyLabeledCards() throws {
        let cards = try FieldExtractionEvaluator.loadGroundTruth(from: try groundTruthURL())

        XCTAssertEqual(cards.count, 30)
        let first = try XCTUnwrap(cards.first { $0.id == "TC01" })
        XCTAssertEqual(first.values[.name], "张伟")
        XCTAssertEqual(first.values[.company], "上海远景科技有限公司")
        XCTAssertEqual(first.values[.address], "上海市浦东新区世纪大道100号")
        XCTAssertNil(first.values[.phone])
        XCTAssertEqual(first.absentKeys, [.phone, .fax, .website])
        XCTAssertTrue(cards.contains { $0.values[.company] == "Apple" }, "数据集应包含品牌名当公司的歧义卡片")
    }

    func testGroundTruthValuesOnlyContainEvaluatedKeys() throws {
        let cards = try FieldExtractionEvaluator.loadGroundTruth(from: try groundTruthURL())

        let unknown = cards.flatMap { $0.values.keys }.filter { !FieldExtractionEvaluator.evaluatedKeys.contains($0) }
        XCTAssertTrue(unknown.isEmpty, "数据集出现了评价范围外的字段：\(unknown)")
    }

    // MARK: - 报告

    func testReportListsPerFieldAccuracyAndErrors() {
        let actual = ExtractedCardFields(
            name: "张伟", company: "上海远景科技有限公司", mobile: "138-0000-0001", fax: "021-6000-0001"
        )

        let result = FieldExtractionEvaluator.compare(card: Self.sampleTruth, actual: actual)
        let report = FieldExtractionEvaluator.report(summary: FieldExtractionEvaluator.summarize([result]), cards: [result])

        XCTAssertTrue(report.contains("## 字段级准确率"))
        XCTAssertTrue(report.contains("| 姓名 | 1 | 1 | 100.0% |"))
        XCTAssertTrue(report.contains("错误明细"))
        XCTAssertTrue(report.contains("| TC01 | 传真 | invented |"))
    }

    // MARK: - 真实准确率（待执行）

    func testFieldAccuracyOnCorpusIsPendingUntilOCRTextsExist() throws {
        let root = FieldExtractionEvaluator.repositoryRoot(sourceFilePath: #filePath)
        let ocrDirectory = root.appendingPathComponent("testcards/ocr", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: ocrDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw XCTSkip("testcards/ocr 下还没有 OCR 原文（Week 3 产出），字段级准确率待执行")
        }

        let cards = try FieldExtractionEvaluator.loadGroundTruth(from: try groundTruthURL())
        let parser = BusinessCardFieldParser()
        var results: [FieldExtractionEvaluator.CardResult] = []
        for card in cards {
            let url = FieldExtractionEvaluator.ocrTextURL(cardID: card.id, repositoryRoot: root)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            results.append(FieldExtractionEvaluator.compare(card: card, actual: parser.parse(text)))
        }

        let summary = FieldExtractionEvaluator.summarize(results)
        print(FieldExtractionEvaluator.report(summary: summary, cards: results))
        XCTAssertEqual(results.count, cards.count, "OCR 原文不完整，无法统计全部 30 张")
    }

    // MARK: - 工具

    private func groundTruthURL() throws -> URL {
        let url = FieldExtractionEvaluator.repositoryRoot(sourceFilePath: #filePath)
            .appendingPathComponent("testcards/ground_truth.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("找不到 ground truth 数据集：\(url.path)")
        }
        return url
    }
}
