import Foundation
import Combine

/// 标签管理页（P09）的 ViewModel。
///
/// 与名片详情里的「添加 / 删除标签」不同，这里是**全局**视角：列出全部标签及其使用张数、
/// 按标签查看名片、删除整个标签（从所有名片上移除），以及新建标签（输入名称并勾选要打上该标签的名片）。
///
/// 标签依附于名片存在（`allTags` 由名片上的标签汇总而来），因此「新建」必须至少勾选一张名片，
/// 否则标签无处存放。
@MainActor
final class TagManagementViewModel: ObservableObject {

    /// 标签及其使用张数。
    struct TagSummary: Equatable, Identifiable {
        let name: String
        let cardCount: Int
        var id: String { name }
    }

    /// 全部标签（按名称排序，含使用张数）。
    @Published private(set) var tags: [TagSummary] = []

    /// 仓库中的全部名片（供新建时勾选）。
    @Published private(set) var cards: [BusinessCard] = []

    /// 正在查看的标签；`nil` 表示停在标签列表。
    @Published private(set) var viewingTag: String?

    /// 新建标签的名称输入。
    @Published var newTagName: String = ""

    /// 新建标签时勾选的名片。
    @Published private(set) var selectedCardIDs: Set<UUID> = []

    /// 是否处于新建标签流程。
    @Published private(set) var isCreating: Bool = false

    /// 新建失败时的提示文案。
    @Published private(set) var creationError: String?

    private let repository: BusinessCardRepository

    init(repository: BusinessCardRepository) {
        self.repository = repository
        load()
    }

    // MARK: - 派生状态

    /// 当前查看的标签下的名片（P09「按标签查看」）。
    var viewingCards: [BusinessCard] {
        guard let viewingTag else { return [] }
        return repository.cards(taggedWith: viewingTag)
    }

    // MARK: - 读取

    /// 从仓库重新加载标签与名片（进入页面、增删后调用）。
    func load() {
        cards = repository.fetchAll()
        tags = Self.summaries(from: cards)
    }

    /// 汇总标签与使用张数。同一张名片上重复出现同一标签（忽略大小写）只计一次。
    private static func summaries(from cards: [BusinessCard]) -> [TagSummary] {
        var order: [String] = []
        var nameByKey: [String: String] = [:]
        var countByKey: [String: Int] = [:]

        for card in cards {
            var seenInCard = Set<String>()
            for tag in card.tags {
                let key = tag.lowercased()
                guard seenInCard.insert(key).inserted else { continue }
                if nameByKey[key] == nil {
                    nameByKey[key] = tag
                    order.append(key)
                }
                countByKey[key, default: 0] += 1
            }
        }

        return order
            .compactMap { key in
                nameByKey[key].map { TagSummary(name: $0, cardCount: countByKey[key] ?? 0) }
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - 按标签查看

    func beginViewing(tag: String) {
        viewingTag = tag
    }

    func endViewing() {
        viewingTag = nil
    }

    // MARK: - 删除标签

    /// 删除整个标签：从所有带有它的名片上移除（忽略大小写），并落盘。
    ///
    /// - 返回 `true` 表示确实删掉了一个标签；标签不存在时返回 `false` 且不改动任何名片。
    @discardableResult
    func deleteTag(_ tag: String) -> Bool {
        let affected = repository.cards(taggedWith: tag)
        guard !affected.isEmpty else { return false }

        for card in affected {
            var updated = card
            updated.tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
            repository.update(updated)
        }

        // 正在查看的标签被删掉后，退回标签列表，避免停在一个已经不存在的筛选上。
        if let viewingTag, viewingTag.caseInsensitiveCompare(tag) == .orderedSame {
            self.viewingTag = nil
        }
        load()
        return true
    }

    // MARK: - 新建标签

    func beginCreating() {
        isCreating = true
        resetCreationDraft()
    }

    func cancelCreating() {
        isCreating = false
        resetCreationDraft()
    }

    /// 勾选 / 取消勾选一张名片。
    func toggleSelection(_ cardID: UUID) {
        if selectedCardIDs.contains(cardID) {
            selectedCardIDs.remove(cardID)
        } else {
            selectedCardIDs.insert(cardID)
        }
    }

    /// 保存新建的标签：名称去首尾空白后写到勾选的名片上。
    ///
    /// - 返回 `true` 表示保存成功。
    /// - 名称为空、与已有标签重名（忽略大小写）或一张名片都没勾选时返回 `false` 并给出提示文案。
    @discardableResult
    func saveNewTag() -> Bool {
        let tag = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else {
            creationError = "请输入标签名称。"
            return false
        }
        guard !tags.contains(where: { $0.name.caseInsensitiveCompare(tag) == .orderedSame }) else {
            creationError = "标签「\(tag)」已存在，请直接使用。"
            return false
        }
        guard !selectedCardIDs.isEmpty else {
            creationError = "请至少选择一张要打上该标签的名片。"
            return false
        }

        for card in cards where selectedCardIDs.contains(card.id) {
            var updated = card
            updated.tags.append(tag)
            repository.update(updated)
        }

        isCreating = false
        resetCreationDraft()
        load()
        return true
    }

    private func resetCreationDraft() {
        newTagName = ""
        selectedCardIDs = []
        creationError = nil
    }
}
