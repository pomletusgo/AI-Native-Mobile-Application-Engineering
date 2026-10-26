import Foundation

/// 内存版名片仓库（Week2 使用）。
///
/// 说明：仅用于工程骨架与单元测试，App 重启后数据不保留。
/// Week5 将新增基于本地存储（如 SwiftData / 文件）的 `PersistentBusinessCardRepository`，
/// 本类**保持不动**，以保证既有测试继续通过（Regression Protection）。
final class InMemoryBusinessCardRepository: BusinessCardRepository {

    private var storage: [BusinessCard]

    init(cards: [BusinessCard] = []) {
        self.storage = cards
    }

    // MARK: - BusinessCardRepository

    func fetchAll() -> [BusinessCard] {
        storage.sorted { $0.createdAt > $1.createdAt }
    }

    func card(withID id: UUID) -> BusinessCard? {
        storage.first { $0.id == id }
    }

    func add(_ card: BusinessCard) {
        storage.append(card)
    }

    func update(_ card: BusinessCard) {
        guard let index = storage.firstIndex(where: { $0.id == card.id }) else { return }
        storage[index] = card
    }

    func delete(id: UUID) {
        storage.removeAll { $0.id == id }
    }

    func search(_ query: String) -> [BusinessCard] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return fetchAll() }
        return fetchAll().filter { $0.searchableText.contains(keyword) }
    }

    func cards(taggedWith tag: String) -> [BusinessCard] {
        fetchAll().filter { card in
            card.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
        }
    }

    var allTags: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in storage.flatMap({ $0.tags }) {
            if seen.insert(tag.lowercased()).inserted {
                result.append(tag)
            }
        }
        return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
