import CoreGraphics
import XCTest
@testable import CamCardClone

/// `ScanReviewViewModel` 单元测试。
///
/// 覆盖任务书 4.3「打通人工校正与保存流程」：T11（修改识别错误的字段后保存的是修改后的内容）、
/// T12（确认保存后名片库出现新名片）、E4（识别不到文字时提示重试）、
/// E5（姓名为空拒绝保存），以及规格 `Human verification and save` 的
/// 「未确认前不写库」与 `Abandon recognition`（放弃确认不新增名片）。
///
/// 检测、校正、识别与仓库都以替身注入，整条链路不依赖真机与相机；
/// 确认页的真实观感、检测框展示与手动调整手势属人工验收（见 `docs/UI验收清单.md`）。
@MainActor
final class ScanReviewViewModelTests: XCTestCase {

    // MARK: - 替身

    /// 可控的区域检测替身。
    private final class StubDetector: CardBoundaryDetecting {

        var result: Result<CardDetectionOutcome, Error>
        private(set) var detectCount = 0
        private(set) var receivedImageData: Data?

        init(result: Result<CardDetectionOutcome, Error>) {
            self.result = result
        }

        func detectCard(in imageData: Data) async throws -> CardDetectionOutcome {
            detectCount += 1
            receivedImageData = imageData
            return try result.get()
        }
    }

    /// 可控的透视校正替身。
    private final class StubCorrector: CardBoundaryCorrecting {

        var result: Result<CorrectedCardImage, Error>
        private(set) var correctCount = 0
        private(set) var receivedImageData: Data?
        private(set) var receivedQuad: CardQuad?

        init(result: Result<CorrectedCardImage, Error>) {
            self.result = result
        }

        func correctCard(in imageData: Data, quad: CardQuad) throws -> CorrectedCardImage {
            correctCount += 1
            receivedImageData = imageData
            receivedQuad = quad
            return try result.get()
        }
    }

    /// 可控的文字识别替身。
    private final class StubOCR: OCRService {

        var result: Result<OCRTextResult, Error>
        private(set) var recognizeCount = 0
        private(set) var receivedImageData: Data?

        init(result: Result<OCRTextResult, Error>) {
            self.result = result
        }

        func recognizeText(in imageData: Data) async throws -> OCRTextResult {
            recognizeCount += 1
            receivedImageData = imageData
            return try result.get()
        }
    }

    /// 预期之外的错误，用来验证兜底文案。
    private struct UnexpectedError: LocalizedError {
        var errorDescription: String? { "底层出错" }
    }

    // MARK: - 夹具

    private struct Harness {
        let model: ScanReviewViewModel
        let detector: StubDetector
        let corrector: StubCorrector
        let ocr: StubOCR
        let repository: InMemoryBusinessCardRepository
        let imageStore: CardImageStore?
    }

    private let photoBytes = Data([0xFF, 0xD8, 0xFF, 0xE0])
    private let correctedBytes = Data([0x89, 0x50, 0x4E, 0x47])

    /// 常见名片比例（90×54mm）的候选四边形：归一化 0.8 × 0.48，长宽比约 1.67，可判为可靠。
    private var reliableQuad: CardQuad {
        CardQuad(
            topLeft: CGPoint(x: 0.10, y: 0.74),
            topRight: CGPoint(x: 0.90, y: 0.74),
            bottomRight: CGPoint(x: 0.90, y: 0.26),
            bottomLeft: CGPoint(x: 0.10, y: 0.26)
        )
    }

    /// 面积远小于阈值的候选，应被判为不可靠（不得当作名片整图识别）。
    private var tinyQuad: CardQuad {
        CardQuad(
            topLeft: CGPoint(x: 0.40, y: 0.43),
            topRight: CGPoint(x: 0.45, y: 0.43),
            bottomRight: CGPoint(x: 0.45, y: 0.40),
            bottomLeft: CGPoint(x: 0.40, y: 0.40)
        )
    }

    /// 手写 OCR 文本：姓名、公司、手机齐全（规则来自 `BusinessCardFieldParserTests`）。
    private static let recognizedLines = [
        "姓名：李娜",
        "公司：环宇国际贸易有限公司",
        "手机：139-0000-0002"
    ]

    /// 只有公司没有姓名，用于验证「姓名为空拒绝保存」。
    private static let companyOnlyLines = ["公司：星辉传媒"]

    private func correctedImage() -> CorrectedCardImage {
        CorrectedCardImage(imageData: correctedBytes, pixelSize: CGSize(width: 800, height: 480))
    }

    private func makeHarness(
        detection: Result<CardDetectionOutcome, Error>,
        correction: Result<CorrectedCardImage, Error>? = nil,
        recognition: Result<OCRTextResult, Error>,
        existingCards: [BusinessCard] = [],
        imageStore: CardImageStore? = nil
    ) -> Harness {
        let detector = StubDetector(result: detection)
        let corrector = StubCorrector(result: correction ?? .success(correctedImage()))
        let ocr = StubOCR(result: recognition)
        let repository = InMemoryBusinessCardRepository(cards: existingCards)
        let model = ScanReviewViewModel(
            originalImageData: photoBytes,
            repository: repository,
            detector: detector,
            corrector: corrector,
            ocr: ocr,
            parser: BusinessCardFieldParser(),
            imageStore: imageStore
        )
        return Harness(
            model: model,
            detector: detector,
            corrector: corrector,
            ocr: ocr,
            repository: repository,
            imageStore: imageStore
        )
    }

    /// 走通一遍成功链路：检测可靠 → 校正成功 → 识别到 `lines`。
    private func makeReviewHarness(
        lines: [String]? = nil,
        existingCards: [BusinessCard] = [],
        imageStore: CardImageStore? = nil
    ) -> Harness {
        makeHarness(
            detection: .success(.detected(reliableQuad)),
            recognition: .success(OCRTextResult(lines: lines ?? Self.recognizedLines)),
            existingCards: existingCards,
            imageStore: imageStore
        )
    }

    // MARK: - 初始状态

    func testInitialPhaseIsAnalyzingAndRepositoryIsUntouched() {
        let harness = makeReviewHarness()

        XCTAssertEqual(harness.model.phase, .analyzing)
        XCTAssertNil(harness.model.failureMessage)
        XCTAssertFalse(harness.model.isWorking)
        XCTAssertTrue(harness.repository.fetchAll().isEmpty)
    }

    func testEditableKeysCoverEveryFieldWithNameFirst() {
        XCTAssertEqual(ScanReviewViewModel.editableKeys, CardFieldKey.allCases)
        XCTAssertEqual(ScanReviewViewModel.editableKeys.first, .name, "姓名置顶，便于发现「姓名为空」")
    }

    // MARK: - 检测与识别（P03 / P04）

    func testAnalyzeDetectsCorrectsAndRecognizesThenEntersReview() async {
        let harness = makeReviewHarness()
        await harness.model.analyze()

        XCTAssertEqual(harness.model.phase, .review)
        XCTAssertNil(harness.model.failureMessage)
        XCTAssertFalse(harness.model.isWorking)

        XCTAssertEqual(harness.detector.detectCount, 1)
        XCTAssertEqual(harness.detector.receivedImageData, photoBytes)
        XCTAssertEqual(harness.corrector.correctCount, 1)
        XCTAssertEqual(harness.corrector.receivedQuad, reliableQuad)
        XCTAssertEqual(harness.ocr.recognizeCount, 1)
        XCTAssertEqual(harness.ocr.receivedImageData, correctedBytes, "应识别校正后的图片，而不是原图")
        XCTAssertEqual(harness.model.correctedImageData, correctedBytes)

        XCTAssertEqual(harness.model.fields.name, "李娜")
        XCTAssertEqual(harness.model.fields.company, "环宇国际贸易有限公司")
        XCTAssertEqual(harness.model.fields.mobile, "139-0000-0002")
    }

    func testAnalyzeAloneDoesNotWriteToRepository() async {
        let harness = makeReviewHarness()
        await harness.model.analyze()

        XCTAssertEqual(harness.model.phase, .review)
        XCTAssertTrue(harness.repository.fetchAll().isEmpty, "未点「保存」前不得写库")
    }

    func testUnreliableDetectionStopsBeforeCorrectionAndRecognition() async {
        let harness = makeHarness(
            detection: .success(.unreliable(tinyQuad)),
            recognition: .success(OCRTextResult(lines: Self.recognizedLines))
        )
        await harness.model.analyze()

        XCTAssertEqual(harness.model.phase, .analyzing)
        XCTAssertEqual(harness.corrector.correctCount, 0, "不可靠的候选不得直接送去校正")
        XCTAssertEqual(harness.ocr.recognizeCount, 0, "不得把整张图当作名片去识别")
        XCTAssertEqual(harness.model.failureMessage, "未能可靠识别名片边界，请把名片放正并占满取景框后重试，或改用手动录入。")
        XCTAssertTrue(harness.repository.fetchAll().isEmpty)
    }

    func testNotFoundDetectionStopsBeforeCorrection() async {
        let harness = makeHarness(
            detection: .success(.notFound),
            recognition: .success(OCRTextResult(lines: Self.recognizedLines))
        )
        await harness.model.analyze()

        XCTAssertEqual(harness.model.phase, .analyzing)
        XCTAssertEqual(harness.corrector.correctCount, 0)
        XCTAssertEqual(harness.ocr.recognizeCount, 0)
        XCTAssertEqual(harness.model.failureMessage, "照片中未找到名片，请让名片占满取景框后重试，或改用手动录入。")
    }

    func testCorrectionFailureIsSurfacedAndSkipsRecognition() async {
        let harness = makeHarness(
            detection: .success(.detected(reliableQuad)),
            correction: .failure(CardBoundaryError.correctionFailed(reason: "透视校正未产出图像。")),
            recognition: .success(OCRTextResult(lines: Self.recognizedLines))
        )
        await harness.model.analyze()

        XCTAssertEqual(harness.model.phase, .analyzing)
        XCTAssertEqual(harness.ocr.recognizeCount, 0)
        XCTAssertEqual(harness.model.failureMessage, "名片校正失败：透视校正未产出图像。")
        XCTAssertNil(harness.model.correctedImageData)
    }

    func testNoTextFoundIsReportedWithE4Message() async {
        let harness = makeHarness(
            detection: .success(.detected(reliableQuad)),
            recognition: .failure(OCRError.noTextFound)
        )
        await harness.model.analyze()

        XCTAssertEqual(harness.model.phase, .analyzing)
        XCTAssertEqual(harness.model.failureMessage, "未识别到文字，请重试或改用手动录入。")
    }

    func testUnexpectedErrorFallsBackToReadableMessage() async {
        let harness = makeHarness(
            detection: .failure(UnexpectedError()),
            recognition: .success(OCRTextResult(lines: Self.recognizedLines))
        )
        await harness.model.analyze()

        XCTAssertEqual(harness.model.phase, .analyzing)
        XCTAssertEqual(harness.model.failureMessage, "底层出错")
    }

    func testRetryAfterFailureEntersReview() async {
        let harness = makeHarness(
            detection: .success(.notFound),
            recognition: .success(OCRTextResult(lines: Self.recognizedLines))
        )
        await harness.model.analyze()
        XCTAssertNotNil(harness.model.failureMessage)

        harness.detector.result = .success(.detected(reliableQuad))
        await harness.model.analyze()

        XCTAssertEqual(harness.model.phase, .review)
        XCTAssertNil(harness.model.failureMessage, "重试成功后应清掉上一次的失败提示")
        XCTAssertEqual(harness.detector.detectCount, 2)
    }

    func testDismissFailureClearsMessage() async {
        let harness = makeHarness(
            detection: .success(.notFound),
            recognition: .success(OCRTextResult(lines: Self.recognizedLines))
        )
        await harness.model.analyze()

        harness.model.dismissFailure()
        XCTAssertNil(harness.model.failureMessage)
    }

    // MARK: - 人工校正与保存（T11 / T12 / E5）

    func testConfirmSavePersistsEditedFields() async {
        let harness = makeReviewHarness()
        await harness.model.analyze()
        XCTAssertEqual(harness.model.phase, .review)

        // T11：修改识别错误的字段后再保存，落库的是修改后的内容。
        harness.model.setField("李娜娜", for: .name)
        harness.model.setField("环宇国际集团", for: .company)

        XCTAssertTrue(harness.model.confirmSave())
        XCTAssertEqual(harness.model.phase, .saved)

        let stored = harness.repository.fetchAll()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.name, "李娜娜")
        XCTAssertEqual(stored.first?.company, "环宇国际集团")
        XCTAssertEqual(stored.first?.mobile, "139-0000-0002", "未修改的字段保持识别结果")
    }

    func testConfirmSaveRejectedWhenNameIsEmpty() async {
        let harness = makeReviewHarness(lines: Self.companyOnlyLines)
        await harness.model.analyze()

        XCTAssertEqual(harness.model.phase, .review)
        XCTAssertNil(harness.model.fields.name)

        XCTAssertFalse(harness.model.confirmSave(), "姓名为空必须拒绝保存（E5）")
        XCTAssertEqual(harness.model.failureMessage, "姓名不能为空，请填写姓名后再保存。")
        XCTAssertTrue(harness.repository.fetchAll().isEmpty)
        XCTAssertEqual(harness.model.phase, .review, "被拒后停留在确认页，等用户补齐姓名")
    }

    func testConfirmSaveRejectedWhenNameIsOnlyWhitespace() async {
        let harness = makeReviewHarness()
        await harness.model.analyze()

        harness.model.setField("   ", for: .name)

        XCTAssertFalse(harness.model.confirmSave())
        XCTAssertTrue(harness.repository.fetchAll().isEmpty)
        XCTAssertEqual(harness.model.phase, .review)
    }

    func testConfirmSaveIsRejectedBeforeReview() {
        // 尚未进入确认页（仍在分析阶段）：直接保存不得写库。
        let harness = makeReviewHarness()

        XCTAssertFalse(harness.model.confirmSave())
        XCTAssertEqual(harness.model.phase, .analyzing)
        XCTAssertTrue(harness.repository.fetchAll().isEmpty)
    }

    func testAbandonRecognitionLeavesExistingCardsUntouched() async {
        // 规格 Abandon recognition：确认页取消/返回后，名片库数量与内容都不变。
        let existing = BusinessCard(name: "既有名片")
        let harness = makeReviewHarness(existingCards: [existing])

        await harness.model.analyze()
        XCTAssertEqual(harness.model.phase, .review)

        XCTAssertEqual(harness.repository.fetchAll().map(\.name), ["既有名片"])
    }

    func testSetFieldTreatsEmptyInputAsClearingAndDropsItOnSave() async {
        let harness = makeReviewHarness()
        await harness.model.analyze()
        XCTAssertEqual(harness.model.field(.mobile), "139-0000-0002")

        harness.model.setField("", for: .mobile)

        XCTAssertEqual(harness.model.field(.mobile), "")
        XCTAssertNil(harness.model.fields.mobile)

        // 清空后保存：该字段不得落库（缺失字段不虚构，对应 T09）。
        XCTAssertTrue(harness.model.confirmSave())
        XCTAssertNil(harness.repository.fetchAll().first?.mobile)
    }

    // MARK: - 保存原始图（5.1 第二段，P06 展示所需）

    private func makeImageStore() -> (store: FileCardImageStore, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScanReviewViewModelTests-\(UUID().uuidString)", isDirectory: true)
        return (FileCardImageStore(directory: directory), directory)
    }

    func testConfirmSaveStoresOriginalAndProcessedImagesAndNamesThem() async throws {
        let (store, directory) = makeImageStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let harness = makeReviewHarness(imageStore: store)
        await harness.model.analyze()

        XCTAssertTrue(harness.model.confirmSave())

        let card = try XCTUnwrap(harness.repository.fetchAll().first)
        XCTAssertEqual(store.load(named: card.originalImageName), harness.photoBytes)
        XCTAssertEqual(store.load(named: card.processedImageName), correctedBytes)
    }

    func testConfirmSaveWithoutStoreLeavesImageNamesNil() async throws {
        let harness = makeReviewHarness()
        await harness.model.analyze()

        XCTAssertTrue(harness.model.confirmSave())

        let card = try XCTUnwrap(harness.repository.fetchAll().first)
        XCTAssertNil(card.originalImageName)
        XCTAssertNil(card.processedImageName)
    }

    func testRejectedSaveDoesNotWriteImages() async {
        let (store, directory) = makeImageStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let harness = makeReviewHarness(lines: Self.companyOnlyLines, imageStore: store)
        await harness.model.analyze()

        XCTAssertFalse(harness.model.confirmSave())
        XCTAssertTrue(harness.repository.fetchAll().isEmpty)

        let written = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        XCTAssertTrue(written.isEmpty, "保存被拒时不应留下图像文件")
    }
}
