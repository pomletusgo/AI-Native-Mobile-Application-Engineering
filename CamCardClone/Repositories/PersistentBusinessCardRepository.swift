import Foundation

/// 基于本地 JSON 文件的持久化名片仓库（Week5）。
///
/// 设计目标（对应 card-library 规格的 Card persistence 需求与 T18）：
/// - 与 `InMemoryBusinessCardRepository` 行为语义完全一致，可直接替换 App 层注入的内存实现，
///   此时 `BusinessCardRepository` 协议与所有调用方**零改动**，从而保证既有测试不被破坏。
/// - 进程内持有一份 `[BusinessCard]` 内存副本，读入后所有查询都在该副本上完成；
///   `add` / `update` / `delete` 之后立即原子落盘，应用重新启动时从同一文件恢复数据。
/// - 文件不存在、内容损坏或解码失败时**不崩溃**，一律按空库处理。
///
/// 存储格式：`JSONEncoder` / `JSONDecoder`，日期策略统一为 `.iso8601`。
final class PersistentBusinessCardRepository: BusinessCardRepository {

    // MARK: - 存储

    /// 落盘的 JSON 文件位置。
    private let fileURL: URL

    /// 内存副本，语义与 `InMemoryBusinessCardRepository.storage` 保持一致。
    private var storage: [BusinessCard]

    // MARK: - 初始化

    /// 使用指定的文件路径初始化；文件缺失或损坏时视为空库。
    init(fileURL: URL) {
        self.fileURL = fileURL
        self.storage = Self.load(from: fileURL)
    }

    /// 便捷构造：在指定目录下以给定文件名创建仓库。
    ///
    /// - Parameters:
    ///   - directory: 存放 JSON 文件的目录；目录不存在时会在首次写入时自动创建。
    ///   - fileName: JSON 文件名，默认为 `business-cards.json`。
    convenience init(directory: URL, fileName: String = "business-cards.json") {
        self.init(fileURL: directory.appendingPathComponent(fileName))
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
        persist()
    }

    func update(_ card: BusinessCard) {
        guard let index = storage.firstIndex(where: { $0.id == card.id }) else { return }
        storage[index] = card
        persist()
    }

    func delete(id: UUID) {
        storage.removeAll { $0.id == id }
        persist()
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

    // MARK: - 磁盘读写

    /// 从磁盘读取全部名片；文件不存在、损坏或解码失败时返回空数组。
    private static func load(from fileURL: URL) -> [BusinessCard] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([BusinessCard].self, from: data)) ?? []
    }

    /// 将当前内存副本原子写入磁盘。
    ///
    /// 目录缺失时自动创建；写入失败时静默忽略（协议方法不抛错，无法向调用方反馈）。
    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(storage) else { return }

        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try? data.write(to: fileURL, options: .atomic)
    }
}
