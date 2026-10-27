import Foundation
@testable import CamCardClone

/// 字段抽取的量化评价（对应任务书 4.4「用 ground truth 统计字段级准确率并记录错误分析」）。
///
/// 评价对象是 `BusinessCardFieldParser` 在 OCR 原始文本上的输出，基准是
/// `testcards/ground_truth.json`。输出两个指标：
/// - **字段级准确率** = 判定正确的字段数 / 参与评价的字段数；
/// - **缺失字段误报率** = 本应为空却被抽出值的字段数 / 本应为空的字段数，用于量化「不得虚构」。
///
/// ground truth 用 `JSONSerialization` 读取：`groundTruth` 里值为 `null` 的字段表示名片上确实
/// 没有该信息，与 `expectedAbsent` 一致；既不在 `groundTruth` 里、也不在 `expectedAbsent` 里的
/// 字段不参与评价，避免把「数据集没标注」算成模型错误。
enum FieldExtractionEvaluator {

    /// 参与评价的字段，与 `testcards/ground_truth.json` 的 `fieldSchema` 一致。
    static let evaluatedKeys: [CardFieldKey] = [
        .name, .company, .jobTitle, .mobile, .phone, .fax, .email, .website, .address,
    ]

    enum Outcome: String {
        /// 与 ground truth 一致。
        case correct
        /// 本应有值但抽成了别的内容。
        case mismatch
        /// 本应有值但没抽出来。
        case missed
        /// 本应为空却抽出了值（虚构）。
        case invented
        /// 本应为空且确实为空。
        case absent
    }

    struct FieldResult: Equatable {
        let key: CardFieldKey
        /// ground truth 上的原文（未归一化）。
        let expected: String?
        /// 抽取器给出的原文（未归一化）。
        let actual: String?
        let outcome: Outcome
    }

    struct CardResult: Equatable {
        let cardID: String
        let fields: [FieldResult]
    }

    /// 一张名片在数据集里的标注。
    struct GroundTruthCard: Equatable {
        let id: String
        /// 名片上确实存在的字段。
        let values: [CardFieldKey: String]
        /// 名片上确实没有、因此抽取结果必须为空的字段。
        let absentKeys: Set<CardFieldKey>
    }

    struct Summary {
        let cardCount: Int
        let evaluatedFieldCount: Int
        let correctCount: Int
        let inventedCount: Int
        let absentFieldCount: Int

        var accuracy: Double {
            evaluatedFieldCount == 0 ? 0 : Double(correctCount) / Double(evaluatedFieldCount)
        }

        var falsePositiveRate: Double {
            absentFieldCount == 0 ? 0 : Double(inventedCount) / Double(absentFieldCount)
        }
    }

    // MARK: - 归一化

    /// 比对前的归一化：去首尾空白、压缩内部空白、忽略大小写；电话类字段进一步忽略分隔符。
    ///
    /// 这是「同一串号码写法不同」的既定等价规则（`138-0000-0001` 与 `13800000001` 视为相同），
    /// 而不是放宽字段内容本身。
    static func normalized(_ value: String, for key: CardFieldKey) -> String? {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if key == .mobile || key == .phone || key == .fax {
            text = String(text.filter { !" -()．.·/".contains($0) })
        }
        return text
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .lowercased()
    }

    // MARK: - 比对与统计

    static func compare(card: GroundTruthCard, actual: ExtractedCardFields) -> CardResult {
        var results: [FieldResult] = []
        for key in evaluatedKeys {
            let expected = card.values[key]
            guard expected != nil || card.absentKeys.contains(key) else { continue }

            let actualValue = actual[key]
            let normalizedExpected = expected.flatMap { normalized($0, for: key) }
            let normalizedActual = actualValue.flatMap { normalized($0, for: key) }

            let outcome: Outcome
            switch (normalizedExpected, normalizedActual) {
            case let (expected?, actual?):
                outcome = expected == actual ? .correct : .mismatch
            case (.some, .none):
                outcome = .missed
            case (.none, .some):
                outcome = .invented
            case (.none, .none):
                outcome = .absent
            }
            results.append(FieldResult(key: key, expected: expected, actual: actualValue, outcome: outcome))
        }
        return CardResult(cardID: card.id, fields: results)
    }

    static func summarize(_ cards: [CardResult]) -> Summary {
        let fields = cards.flatMap { $0.fields }
        return Summary(
            cardCount: cards.count,
            evaluatedFieldCount: fields.count,
            correctCount: fields.filter { $0.outcome == .correct }.count,
            inventedCount: fields.filter { $0.outcome == .invented }.count,
            absentFieldCount: fields.filter { $0.outcome == .absent || $0.outcome == .invented }.count
        )
    }

    /// 逐字段的正确数 / 参与数，用于定位是哪一类字段在拉低准确率。
    static func perFieldCounts(_ cards: [CardResult]) -> [(key: CardFieldKey, correct: Int, total: Int)] {
        evaluatedKeys.map { key in
            let ofKey = cards.flatMap { $0.fields }.filter { $0.key == key }
            return (key, ofKey.filter { $0.outcome == .correct }.count, ofKey.count)
        }
    }

    // MARK: - 数据集

    static func loadGroundTruth(from url: URL) throws -> [GroundTruthCard] {
        let data = try Data(contentsOf: url)
        let root = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let rawCards = root["cards"] as? [[String: Any]] ?? []
        return rawCards.compactMap { raw in
            guard let id = raw["id"] as? String else { return nil }
            var values: [CardFieldKey: String] = [:]
            for (name, value) in raw["groundTruth"] as? [String: Any] ?? [:] {
                // `null` 在这里是 NSNull，转不成 String，正好表示「本应为空」。
                guard let key = CardFieldKey(rawValue: name), let text = value as? String else { continue }
                values[key] = text
            }
            let absent = Set((raw["expectedAbsent"] as? [String] ?? []).compactMap(CardFieldKey.init(rawValue:)))
            return GroundTruthCard(id: id, values: values, absentKeys: absent)
        }
    }

    /// 由测试源文件的编译期路径推出仓库根目录（`<repo>/CamCardCloneTests/<file>.swift`）。
    static func repositoryRoot(sourceFilePath: String) -> URL {
        URL(fileURLWithPath: sourceFilePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// OCR 原文的约定位置：`testcards/ocr/<名片 ID>.txt`，由 Week 3 的识别流程产出。
    static func ocrTextURL(cardID: String, repositoryRoot: URL) -> URL {
        repositoryRoot.appendingPathComponent("testcards/ocr/\(cardID).txt")
    }

    // MARK: - 报告

    static func report(summary: Summary, cards: [CardResult]) -> String {
        var lines: [String] = []
        lines.append("## 字段级准确率")
        lines.append("")
        lines.append("- 参与评价：\(summary.cardCount) 张名片 / \(summary.evaluatedFieldCount) 个字段")
        lines.append(String(
            format: "- 字段级准确率：%.1f%%（正确 %d / 总计 %d）",
            summary.accuracy * 100, summary.correctCount, summary.evaluatedFieldCount
        ))
        lines.append(String(
            format: "- 缺失字段误报率：%.1f%%（虚构 %d / 本应为空 %d）",
            summary.falsePositiveRate * 100, summary.inventedCount, summary.absentFieldCount
        ))
        lines.append("")
        lines.append("| 字段 | 正确 | 参与 | 准确率 |")
        lines.append("|---|---|---|---|")
        for item in perFieldCounts(cards) {
            let rate = item.total == 0 ? 0 : Double(item.correct) / Double(item.total) * 100
            lines.append(String(
                format: "| %@ | %d | %d | %.1f%% |",
                item.key.displayName, item.correct, item.total, rate
            ))
        }

        let errors = cards.flatMap { card in
            card.fields
                .filter { $0.outcome != .correct && $0.outcome != .absent }
                .map { (card.cardID, $0) }
        }
        if !errors.isEmpty {
            lines.append("")
            lines.append("### 错误明细")
            lines.append("")
            lines.append("| 名片 | 字段 | 判定 | ground truth | 抽取结果 |")
            lines.append("|---|---|---|---|---|")
            for (cardID, field) in errors {
                lines.append("| \(cardID) | \(field.key.displayName) | \(field.outcome.rawValue) | \(field.expected ?? "—") | \(field.actual ?? "—") |")
            }
        }
        return lines.joined(separator: "\n")
    }
}
