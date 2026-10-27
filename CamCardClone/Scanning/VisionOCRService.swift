import CoreGraphics
import Foundation
import ImageIO
import Vision

/// 基于 Vision 的 `OCRService` 实现。
///
/// 使用 `VNRecognizeTextRequest` 做端上识别，默认走 `.accurate` 级别并同时支持
/// 简体中文与英文，覆盖名片常见的中英混排版式。识别结果按阅读顺序整理成
/// `OCRTextResult`，字段含义仍由 `BusinessCardFieldParser` 解释。
final class VisionOCRService: OCRService {

    private let recognitionLevel: VNRequestTextRecognitionLevel
    private let recognitionLanguages: [String]

    init(
        recognitionLevel: VNRequestTextRecognitionLevel = .accurate,
        recognitionLanguages: [String] = ["zh-Hans", "en-US"]
    ) {
        self.recognitionLevel = recognitionLevel
        self.recognitionLanguages = recognitionLanguages
    }

    /// 在后台队列执行识别，避免阻塞调用方（通常是主线程上的 ViewModel）。
    func recognizeText(in imageData: Data) async throws -> OCRTextResult {
        let level = recognitionLevel
        let languages = recognitionLanguages
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try VisionOCRService.recognize(
                        imageData: imageData,
                        level: level,
                        languages: languages
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// 同步执行一次识别，抽成静态方法便于在测试中直接调用。
    static func recognize(
        imageData: Data,
        level: VNRequestTextRecognitionLevel,
        languages: [String]
    ) throws -> OCRTextResult {
        guard
            let source = CGImageSourceCreateWithData(imageData as CFData, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw OCRError.invalidImageData
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages

        do {
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        } catch {
            throw OCRError.failed(reason: error.localizedDescription)
        }

        let lines: [RecognizedLine] = (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecognizedLine(text: candidate.string, boundingBox: observation.boundingBox)
        }

        let result = OCRTextResult(lines: lines.sortedInReadingOrder().map(\.text))
        guard !result.isEmpty else { throw OCRError.noTextFound }
        return result
    }
}
