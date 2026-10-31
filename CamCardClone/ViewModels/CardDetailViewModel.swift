import Foundation
import Combine

/// 名片详情 / 编辑 ViewModel（对应 P06、P07，标签编辑对应 P09）。
///
/// 标签的增删都发生在草稿上，因此「取消编辑丢弃草稿」同样会丢弃这次标签改动。
@MainActor
final class CardDetailViewModel: ObservableObject {

    /// 已保存的名片（`nil` 表示名片不存在，例如被删除后返回）。
    @Published private(set) var card: BusinessCard?

    /// 编辑中的草稿。非 `nil` 表示处于编辑态（状态 D2）。
    @Published var draft: BusinessCard?

    private let repository: BusinessCardRepository
    private let cardID: UUID

    init(repository: BusinessCardRepository, cardID: UUID) {
        self.repository = repository
        self.cardID = cardID
        reload()
    }

    // MARK: - 派生状态

    var isEditing: Bool { draft != nil }

    var isMissing: Bool { card == nil }

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

    /// 删除当前名片。
    func delete() {
        repository.delete(id: cardID)
        reload()
    }
}
