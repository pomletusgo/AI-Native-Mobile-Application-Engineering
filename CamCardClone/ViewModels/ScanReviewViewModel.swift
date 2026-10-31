import Foundation

/// 扫描结果复核页（P03 检测与校正 → P04 识别中 → P05 结果确认与校正）的状态机。
///
/// 承接 `ScannerEntryViewModel` 拿到的照片，依次完成：
/// 区域检测 → 透视校正 → 文字识别 → 字段抽取 → 人工逐字段校正 → 落库。
///
/// 对应 card-scanner 规格的 `Human verification and save` 三条约束：
/// - 识别结果先进入可编辑的确认页，**未确认前不写库**；
/// - 「确认保存」时姓名为空必须被拒绝（规格 E5）；
/// - 确认页取消不新增任何名片（`Abandon recognition`）。
///
/// 检测、校正、识别与仓库都以协议注入，因此上述行为可以脱离真机与系统框架单测。
@MainActor
final class ScanReviewViewModel: ObservableObject {

    /// 页面阶段。
    enum Phase: Equatable {
        /// P03/P04：正在检测名片区域并识别文字。
        case analyzing
        /// P05：识别结果待人工确认与逐字段校正。
        case review
        /// 已确认并写入名片库。
        case saved
    }

    /// 确认页展示与可编辑的字段顺序：姓名在最前，「姓名为空不得保存」的第一落点。
    static let editableKeys: [CardFieldKey] = CardFieldKey.allCases

    @Published private(set) var phase: Phase = .analyzing
    /// 抽取出的字段。确认页直接编辑这份草稿，**未点「保存」前不会进入名片库**。
    @Published private(set) var fields = ExtractedCardFields()
    /// 校正后的图片数据，用于确认页预览；检测未通过时为 nil。
    @Published private(set) var correctedImageData: Data?
    /// 检测/校正/识别失败，或保存被拒时的提示文案。
    @Published private(set) var failureMessage: String?
    /// 检测与识别进行中，界面据此给出 P04 的进行中反馈。
    @Published private(set) var isWorking = false

    /// 本次要复核的原始图片（拍摄或相册导入得到）。
    let originalImageData: Data

    private let repository: BusinessCardRepository
    private let detector: CardBoundaryDetecting
    private let corrector: CardBoundaryCorrecting
    private let ocr: OCRService
    private let parser: BusinessCardFieldParser

    init(
        originalImageData: Data,
        repository: BusinessCardRepository,
        detector: CardBoundaryDetecting,
        corrector: CardBoundaryCorrecting,
        ocr: OCRService,
        parser: BusinessCardFieldParser
    ) {
        self.originalImageData = originalImageData
        self.repository = repository
        self.detector = detector
        self.corrector = corrector
        self.ocr = ocr
        self.parser = parser
    }

    // MARK: - 检测与识别（P03 / P04）

    /// 执行一次完整的「检测 → 校正 → 识别 → 抽取」。
    ///
    /// 失败不抛给界面：把可读文案放进 `failureMessage`，界面据此提示「重试」或「重拍」。
    /// 重试时直接再次调用本方法即可。
    func analyze() async {
        isWorking = true
        failureMessage = nil
        phase = .analyzing
        defer { isWorking = false }

        do {
            switch try await detector.detectCard(in: originalImageData) {
            case .detected(let quad):
                try await recognizeText(using: quad)
            case .unreliable:
                // 规格要求：检测不可靠时允许重拍或手动调整，不得把整张图当作名片去识别。
                failureMessage = "未能可靠识别名片边界，请把名片放正并占满取景框后重试，或改用手动录入。"
            case .notFound:
                failureMessage = "照片中未找到名片，请让名片占满取景框后重试，或改用手动录入。"
            }
        } catch {
            failureMessage = Self.readableMessage(for: error)
        }
    }

    /// 校正后识别；只有走到这里才可能进入确认页。
    private func recognizeText(using quad: CardQuad) async throws {
        let corrected = try corrector.correctCard(in: originalImageData, quad: quad)
        correctedImageData = corrected.imageData

        let text = try await ocr.recognizeText(in: corrected.imageData)
        fields = parser.parse(text.rawText)
        phase = .review
    }

    // MARK: - 人工校正（P05）

    /// 读取单个字段用于界面绑定，无值为空串。
    func field(_ key: CardFieldKey) -> String {
        fields[key] ?? ""
    }

    /// 逐字段修改草稿（T11）。空串按「清空该字段」处理，首尾空白在保存时统一裁剪。
    func setField(_ value: String, for key: CardFieldKey) {
        fields[key] = value.isEmpty ? nil : value
    }

    // MARK: - 确认与放弃

    /// 确认并保存（T12）。
    ///
    /// 姓名（去掉首尾空白后）为空时拒绝构造名片并提示，返回 false（规格 E5）；
    /// 未进入确认页时直接返回 false，保证「未确认前不写库」。
    @discardableResult
    func confirmSave() -> Bool {
        guard phase == .review else { return false }
        guard let card = fields.makeCard() else {
            failureMessage = "姓名不能为空，请填写姓名后再保存。"
            return false
        }
        repository.add(card)
        failureMessage = nil
        phase = .saved
        return true
    }

    func dismissFailure() {
        failureMessage = nil
    }

    // MARK: - 内部

    /// 取错误自带的文案；非预期错误也要给出可读提示，不留空白提示。
    private static func readableMessage(for error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
            return localized
        }
        return "识别未完成，请重试或改用手动录入。"
    }
}
