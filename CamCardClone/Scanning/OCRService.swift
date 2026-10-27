import CoreGraphics
import Foundation

/// 一次文字识别的结果。
///
/// `lines` 是识别出的原始文本行，按阅读顺序排列；`rawText` 用换行拼接供字段抽取使用。
/// 这里只做「文本搬运」，不做任何字段解释——解释交给 `BusinessCardFieldParser`，
/// 以保持 OCR 与字段抽取的职责边界（见 card-scanner 规格的 Optical character recognition）。
struct OCRTextResult: Equatable {
    /// 按阅读顺序排列的文本行，已去除首尾空白并丢弃空行。
    let lines: [String]

    init(lines: [String]) {
        self.lines = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 原始识别文本，各行以换行拼接；无有效文本时为空字符串。
    var rawText: String {
        lines.joined(separator: "\n")
    }

    /// 是否没有识别到任何有效文本。
    var isEmpty: Bool {
        lines.isEmpty
    }
}

/// 识别到的单行文字及其在图片中的位置。
///
/// 坐标使用 Vision 的归一化坐标系：原点在左下角，取值范围 0...1。
/// 抽成独立类型是为了让「阅读顺序排序」成为可单独测试的纯逻辑。
struct RecognizedLine: Equatable {
    let text: String
    let boundingBox: CGRect
}

extension Sequence where Element == RecognizedLine {
    /// 按阅读顺序返回：先自上而下分行，同一行内再从左到右。
    ///
    /// Vision 的坐标原点在左下角，因此 `midY` 越大越靠上。分行的依据是相邻文本块的
    /// 纵向重叠程度，而不是逐对比较——逐对比较会破坏排序的传递性，结果不稳定。
    func sortedInReadingOrder() -> [RecognizedLine] {
        let lines = Array(self)
        guard !lines.isEmpty else { return [] }

        let topToBottom = lines.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        var rows: [[RecognizedLine]] = []

        for line in topToBottom {
            if let reference = rows.last?.first {
                let tolerance = max(reference.boundingBox.height, line.boundingBox.height) * 0.6
                if abs(reference.boundingBox.midY - line.boundingBox.midY) <= tolerance {
                    rows[rows.count - 1].append(line)
                    continue
                }
            }
            rows.append([line])
        }

        return rows.flatMap { row in
            row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
        }
    }
}

/// OCR 过程中可预期的失败。
///
/// 规格要求识别失败时提示重试或转手动录入，并且「不得保存空名片」，
/// 因此「没识别到文本」被当作失败而不是成功返回空结果。
enum OCRError: LocalizedError, Equatable {
    /// 图片数据无法解码成图像。
    case invalidImageData
    /// 图像可读但没有任何文字。
    case noTextFound
    /// 识别引擎本身报错。
    case failed(reason: String)

    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            return "无法读取图片，请重新拍摄或选择图片。"
        case .noTextFound:
            return "未识别到文字，请重试或改用手动录入。"
        case .failed(let reason):
            return "识别失败：\(reason)"
        }
    }
}

/// 文字识别能力。
///
/// 输入是图片数据（而非 `UIImage`），这样实现与测试都不必依赖 UIKit；
/// 上层在拿到图片后转成 `Data` 再调用。具体实现见 `VisionOCRService`。
protocol OCRService: AnyObject {
    /// 识别图片中的文字。识别不到文本时抛 `OCRError.noTextFound`。
    func recognizeText(in imageData: Data) async throws -> OCRTextResult
}
