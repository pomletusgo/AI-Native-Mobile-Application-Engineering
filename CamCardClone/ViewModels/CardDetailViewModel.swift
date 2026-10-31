import Foundation
import Combine

/// 名片详情 / 编辑 ViewModel（对应 P06、P07，标签编辑对应 P09，导出对应 P10）。
///
/// 标签的增删都发生在草稿上，因此「取消编辑丢弃草稿」同样会丢弃这次标签改动。
@MainActor
final class CardDetailViewModel: ObservableObject {

    /// 已保存的名片（`nil` 表示名片不存在，例如被删除后返回）。
    @Published private(set) var card: BusinessCard?

    /// 编辑中的草稿。非 `nil` 表示处于编辑态（状态 D2）。
    @Published var draft: BusinessCard?

    /// 最近一次导出的结果；`nil` 表示没有待展示的提示（P10）。
    @Published private(set) var exportNotice: ContactExportNotice?

    private let repository: BusinessCardRepository
    private let cardID: UUID
    /// 图像存储；为 `nil` 时详情页不展示图像。
    private let imageStore: CardImageStore?
    /// 系统联系人导出器；为 `nil` 时详情页不提供「存入系统联系人」。
    private let contactExporter: ContactExporting?

    init(
        repository: BusinessCardRepository,
        cardID: UUID,
        imageStore: CardImageStore? = nil,
        contactExporter: ContactExporting? = nil
    ) {
        self.repository = repository
        self.cardID = cardID
        self.imageStore = imageStore
        self.contactExporter = contactExporter
        reload()
    }

    // MARK: - 派生状态

    var isEditing: Bool { draft != nil }

    var isMissing: Bool { card == nil }

    /// 详情页要展示的图像：优先原始图，缺失时退回校正图（P06）。
    ///
    /// 返回 `nil` 表示这张名片没有可展示的图像（手动录入，或文件已被清理），界面据此不显示图像区。
    var displayImageData: Data? {
        guard let card else { return nil }
        if let data = imageStore?.load(named: card.originalImageName) { return data }
        return imageStore?.load(named: card.processedImageName)
    }

    /// 当前名片对应的 vCard 文本；名片不存在时为 `nil`（P10 / T19）。
    var vCardText: String? {
        card.map(VCardExporter.vCard(for:))
    }

    /// 是否能导出到系统联系人：名片存在且已注入导出器。
    var canExportToContacts: Bool {
        card != nil && contactExporter != nil
    }

    // MARK: - 操作

    func reload() {
        card = repository.card(withID: cardID)
    }

    /// 进入编辑态。
    func beginEditing() {
        guard let card else { return }
        draft = card
    }

    /// 取消编辑，丢弃草稿。
    func cancelEditing() {
        draft = nil
    }

    // MARK: - 标签编辑（P09：添加 / 删除标签，随草稿一起保存或丢弃）

    /// 当前可编辑的标签：编辑态取草稿，否则取已保存名片。
    var editableTags: [String] {
        draft?.tags ?? card?.tags ?? []
    }

    /// 向草稿添加一个标签。
    ///
    /// - 空字符串与纯空白不写入（与「空字段即不存在」一致）。
    /// - 与已有标签重复（忽略大小写）时不写入。
    /// - 非编辑态不写入。
    /// - 返回 `true` 表示标签已加入草稿。
    @discardableResult
    func addTag(_ raw: String) -> Bool {
        guard var working = draft else { return false }
        let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return false }
        guard !working.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else {
            return false
        }
        working.tags.append(tag)
        draft = working
        return true
    }

    /// 从草稿移除一个标签（忽略大小写）。
    ///
    /// - 返回 `true` 表示确实移除了一个标签。
    @discardableResult
    func removeTag(_ tag: String) -> Bool {
        guard var working = draft else { return false }
        let before = working.tags.count
        working.tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
        guard working.tags.count != before else { return false }
        draft = working
        return true
    }

    /// 保存编辑。
    ///
    /// - 返回 `true` 表示保存成功。
    /// - 姓名为空时拒绝保存并返回 `false`（对应 T20「字段为空」异常路径）。
    @discardableResult
    func saveEditing() -> Bool {
        guard var edited = draft else { return false }

        let trimmedName = edited.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        edited.name = trimmedName

        repository.update(edited)
        draft = nil
        reload()
        return true
    }

    /// 删除当前名片，并清理它的图像文件。
    func delete() {
        repository.delete(id: cardID)
        imageStore?.deleteImages(for: cardID)
        reload()
    }

    // MARK: - 导出（P10：存入系统联系人 / 分享 VCF 文件）

    /// 把当前名片写入系统联系人。
    ///
    /// 未注入导出器或名片不存在时不做任何事，也不产生提示。
    /// 结果统一落到 `exportNotice`，由界面弹出提示（成功与失败都要让用户知道）。
    func exportToContacts() async {
        guard let card, let contactExporter else { return }
        exportNotice = await ContactExportCoordinator.export(card, using: contactExporter)
    }

    /// 生成用于分享的临时 `.vcf` 文件；名片不存在或写盘失败时返回 `nil`。
    func makeVCardFileURL() -> URL? {
        guard let card else { return nil }
        return try? VCardExporter.temporaryFileURL(for: card)
    }

    /// 关闭导出提示。
    func clearExportNotice() {
        exportNotice = nil
    }
}
