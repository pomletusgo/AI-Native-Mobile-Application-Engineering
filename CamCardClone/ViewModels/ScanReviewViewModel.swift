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
/// 以及 `Card boundary detection` 的「自动检测不可靠时允许用户手动调整或重拍」：
/// 检测不可靠或未找到时提供 `canAdjustBoundary`，用户可拖四个角自行指出名片区域，
/// 应用后再走同一条「校正 → 识别 → 抽取」链路（见 `beginManualAdjustment` 一组方法）。
///
/// 检测、校正、识别与仓库都以协议注入，因此上述行为可以脱离真机与系统框架单测。
@MainActor
final class ScanReviewViewModel: ObservableObject {

    /// 页面阶段。
    enum Phase: Equatable {
        /// P03/P04：正在检测名片区域并识别文字。
        case analyzing
        /// P03 手动调整：自动检测不可靠或未找到时，由用户拖四个角指出名片区域。
        case adjustingBoundary
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
    /// 是否允许进入手动调整边界：只有自动检测「不可靠」或「未找到」时才为 true
    /// （规格：检测不可靠时允许手动调整或重拍，且不得把整张图片当作名片去识别）。
    @Published private(set) var canAdjustBoundary = false
    /// 手动调整的编辑状态；非调整态为 `nil`。
    @Published private(set) var adjustment: CardBoundaryAdjustment?

    /// 本次要复核的原始图片（拍摄或相册导入得到）。
    let originalImageData: Data

    private let repository: BusinessCardRepository
    private let detector: CardBoundaryDetecting
    private let corrector: CardBoundaryCorrecting
    private let ocr: OCRService
    private let parser: BusinessCardFieldParser
    /// 图像存储；为 `nil` 时不落图像文件（详情页也就没有图可展示）。
    private let imageStore: CardImageStore?

    /// 最近一次检测的结果，进入手动调整时作为起点框。
    private var lastDetectionOutcome: CardDetectionOutcome?
    /// 最近一次「检测不可靠 / 未找到」的提示文案，放弃手动调整时恢复展示。
    private var detectionFailureMessage: String?

    init(
        originalImageData: Data,
        repository: BusinessCardRepository,
        detector: CardBoundaryDetecting,
        corrector: CardBoundaryCorrecting,
        ocr: OCRService,
        parser: BusinessCardFieldParser,
        imageStore: CardImageStore? = nil
    ) {
        self.originalImageData = originalImageData
        self.repository = repository
        self.detector = detector
        self.corrector = corrector
        self.ocr = ocr
        self.parser = parser
        self.imageStore = imageStore
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
        canAdjustBoundary = false
        adjustment = nil
        lastDetectionOutcome = nil
        detectionFailureMessage = nil
        defer { isWorking = false }

        do {
            let outcome = try await detector.detectCard(in: originalImageData)
            lastDetectionOutcome = outcome
            switch outcome {
            case .detected(let quad):
                try await recognizeText(using: quad)
            case .unreliable:
                // 规格要求：检测不可靠时允许重拍或手动调整，不得把整张图当作名片去识别。
                detectionFailureMessage = "未能可靠识别名片边界，请把名片放正并占满取景框后重试，或改用手动录入。"
                canAdjustBoundary = true
                failureMessage = detectionFailureMessage
            case .notFound:
                detectionFailureMessage = "照片中未找到名片，请让名片占满取景框后重试，或改用手动录入。"
                canAdjustBoundary = true
                failureMessage = detectionFailureMessage
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

    // MARK: - 手动调整边界（P03，规格 `Card boundary detection`）

    /// 是否正处于手动调整态。
    var isAdjustingBoundary: Bool {
        phase == .adjustingBoundary
    }

    /// 进入手动调整：起点优先沿用最近一次检测到的候选框（含被判为不可靠的那个），
    /// 找不到候选时用居中默认框；若上一次手动调整失败后仍留有编辑状态，则接着上次的框继续。
    func beginManualAdjustment() {
        guard canAdjustBoundary else { return }
        if adjustment == nil {
            adjustment = CardBoundaryAdjustment.starting(from: lastDetectionOutcome ?? .notFound)
        }
        failureMessage = nil
        phase = .adjustingBoundary
    }

    /// 拖动某个角到归一化坐标；仅在调整态生效。
    func moveBoundaryCorner(_ corner: CardQuadCorner, to point: CGPoint) {
        guard phase == .adjustingBoundary else { return }
        adjustment?.move(corner, to: point)
    }

    /// 回到进入调整态时的起点框。
    func resetBoundaryAdjustment() {
        guard phase == .adjustingBoundary else { return }
        adjustment?.reset()
    }

    /// 放弃手动调整：回到调整前的提示状态，不产生任何名片。
    func cancelBoundaryAdjustment() {
        guard phase == .adjustingBoundary else { return }
        adjustment = nil
        phase = .analyzing
        failureMessage = detectionFailureMessage
    }

    /// 应用手动调整后的边界：用它做透视校正与识别，成功即进入确认页。
    ///
    /// 调整结果不可用（拖成自交 / 凹形 / 退化成一条线，或几乎覆盖整张图）时拒绝继续并提示，
    /// 不做「随便挑一个框凑合识别」的兜底。
    func applyBoundaryAdjustment() async {
        guard phase == .adjustingBoundary, let adjustment else { return }
        guard adjustment.isUsable else {
            failureMessage = "手动调整后的名片区域不可用，请把四个角围成一个贴合名片的四边形。"
            return
        }

        isWorking = true
        failureMessage = nil
        phase = .analyzing
        defer { isWorking = false }

        do {
            try await recognizeText(using: adjustment.quad)
            self.adjustment = nil
            canAdjustBoundary = false
            detectionFailureMessage = nil
        } catch {
            // 校正或识别仍失败时保留编辑状态，用户可以接着微调后重试。
            canAdjustBoundary = true
            failureMessage = Self.readableMessage(for: error)
        }
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
    /// 配置了图像存储时，同时落盘原始图与校正图，并把文件名写回名片（详情页据此展示原始图）。
    @discardableResult
    func confirmSave() -> Bool {
        guard phase == .review else { return false }
        guard var card = fields.makeCard() else {
            failureMessage = "姓名不能为空，请填写姓名后再保存。"
            return false
        }
        if let imageStore {
            card.originalImageName = imageStore.save(originalImageData, cardID: card.id, kind: .original)
            card.processedImageName = correctedImageData.flatMap {
                imageStore.save($0, cardID: card.id, kind: .processed)
            }
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
