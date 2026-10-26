import Foundation
import Combine

/// 名片夹首页 ViewModel（对应 P01）。
@MainActor
final class CardHolderViewModel: ObservableObject {

    /// 仓库中的全部名片（未经搜索/标签过滤）。
    @Published private(set) var cards: [BusinessCard] = []

    /// 搜索关键字（绑定到 `.searchable`）。
    @Published var searchText: String = ""

    /// 当前选中的标签筛选；`nil` 表示不筛选。
    @Published private(set) var selectedTag: String?

    private let repository: BusinessCardRepository

    init(repository: BusinessCardRepository) {
        self.repository = repository
    }

    // MARK: - 派生状态

    /// 当前应显示的名片（已应用搜索与标签筛选）。
    var visibleCards: [BusinessCard] {
        var result = repository.search(searchText)
        if let tag = selectedTag {
            result = result.filter { card in
                card.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
            }
        }
        return result
    }

    /// 状态 S1：名片夹为空。
    var isEmpty: Bool { cards.isEmpty }

    /// 是否处于搜索中。
    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 状态 S3 的「无结果」分支：有名片但过滤后为空。
    var hasNoResults: Bool { !cards.isEmpty && visibleCards.isEmpty }

    /// 全部标签（用于标签筛选栏）。
    var allTags: [String] { repository.allTags }

    // MARK: - 操作

    /// 从仓库重新加载（进入页面、保存/删除后调用）。
    func load() {
        cards = repository.fetchAll()
    }

    func delete(id: UUID) {
        repository.delete(id: id)
        load()
    }

    /// 支持列表滑动删除。
    func delete(at offsets: IndexSet) {
        let targets = offsets.map { visibleCards[$0] }
        targets.forEach { repository.delete(id: $0.id) }
        load()
    }

    /// 切换标签筛选（再次点击同一标签即取消筛选）。
    func toggleTagFilter(_ tag: String) {
        selectedTag = (selectedTag == tag) ? nil : tag
    }
}
