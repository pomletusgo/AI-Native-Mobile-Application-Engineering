import XCTest
@testable import CamCardClone

/// `PersistentBusinessCardRepository` 单元测试。
///
/// 覆盖 card-library 的 Card repository contract / Search and tag query / Card persistence 需求，
/// 对应 T13–T18。所有用例使用临时目录，不依赖网络与固定绝对路径，`tearDown` 中清理。
final class PersistentBusinessCardRepositoryTests: XCTestCase {

    private var temporaryDirectory: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        fileURL = temporaryDirectory.appendingPathComponent("business-cards.json")
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory = temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        fileURL = nil
    }

    private func makeCard(
        name: String,
        company: String? = nil,
        tags: [String] = [],
        createdAtOffset: TimeInterval = 0
    ) -> BusinessCard {
        BusinessCard(
            name: name,
            company: company,
            tags: tags,
            createdAt: Date(timeIntervalSince1970: createdAtOffset)
        )
    }

    // MARK: - 增删改查

    func testNewRepositoryOnMissingFileIsEmpty() {
        let repository = PersistentBusinessCardRepository(fileURL: fileURL)
        XCTAssertTrue(repository.fetchAll().isEmpty)
    }

    func testAddAndFetchAll() {
        let repository = PersistentBusinessCardRepository(fileURL: fileURL)
        repository.add(makeCard(name: "张伟"))

        let all = repository.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.name, "张伟")
    }

    func testFetchAllSortedByCreatedAtDescending() {
        let repository = PersistentBusinessCardRepository(fileURL: fileURL)
        repository.add(makeCard(name: "旧", createdAtOffset: 100))
        repository.add(makeCard(name: "新", createdAtOffset: 200))
        repository.add(makeCard(name: "中", createdAtOffset: 150))

        XCTAssertEqual(repository.fetchAll().map(\.name), ["新", "中", "旧"])
    }

    func testCardWithIDReturnsMatchingCard() {
        let repository = PersistentBusinessCardRepository(fileURL: fileURL)
        let card = makeCard(name: "李娜")
        repository.add(card)

        XCTAssertEqual(repository.card(withID: card.id)?.name, "李娜")
        XCTAssertNil(repository.card(withID: UUID()))
    }

    func testUpdateReplacesExistingCard() {
        let repository = PersistentBusinessCardRepository(fileURL: fileURL)
        var card = makeCard(name: "张伟", company: "远景科技")
        repository.add(card)

        card.company = "远景科技（新）"
        repository.update(card)

        XCTAssertEqual(repository.card(withID: card.id)?.company, "远景科技（新）")
        XCTAssertEqual(repository.fetchAll().count, 1)
    }

    func testUpdateIgnoresUnknownCard() {
        let repository = PersistentBusinessCardRepository(fileURL: fileURL)
        repository.add(makeCard(name: "张伟"))

        repository.update(makeCard(name: "不存在"))
        XCTAssertEqual(repository.fetchAll().count, 1)
    }

    func testDeleteRemovesCard() {
        let repository = PersistentBusinessCardRepository(fileURL: fileURL)
        let card = makeCard(name: "张伟")
        repository.add(card)
        repository.add(makeCard(name: "李娜"))

        repository.delete(id: card.id)

        XCTAssertNil(repository.card(withID: card.id))
        XCTAssertEqual(repository.fetchAll().map(\.name), ["李娜"])
    }

    // MARK: - 搜索（T15）

    func testSearchIsCaseInsensitive() {
        let repository = PersistentBusinessCardRepository(fileURL: fileURL)
        repository.add(makeCard(name: "David Chen", company: "ABC Technologies"))

        XCTAssertEqual(repository.search("abc").count, 1)
        XCTAssertEqual(repository.search("DAVID").count, 1)
    }

    func testSearchWithEmptyKeywordReturnsAll() {
        let repository = PersistentBusinessCardRepository(fileURL: fileURL)
        repository.add(makeCard(name: "张伟"))
        repository.add(makeCard(name: "李娜"))

        XCTAssertEqual(repository.search("   ").count, 2)
    }

    // MARK: - 标签（T16）

    func testCardsTaggedWithIsCaseInsensitive() {
        let repository = PersistentBusinessCardRepository(fileURL: fileURL)
        repository.add(makeCard(name: "A", tags: ["Conference"]))
        repository.add(makeCard(name: "B", tags: ["Customer"]))

        XCTAssertEqual(repository.cards(taggedWith: "conference").map(\.name), ["A"])
        XCTAssertTrue(repository.cards(taggedWith: "Unknown").isEmpty)
    }

    func testAllTagsDeduplicatedCaseInsensitiveAndSorted() {
        let repository = PersistentBusinessCardRepository(fileURL: fileURL)
        repository.add(makeCard(name: "A", tags: ["Conference", "Customer"]))
        repository.add(makeCard(name: "B", tags: ["conference", "Partner"]))

        XCTAssertEqual(repository.allTags, ["Conference", "Customer", "Partner"])
    }

    // MARK: - 重启保留（T18 / Card persistence）

    func testDataSurvivesRelaunch() {
        let card = BusinessCard(
            name: "李娜",
            company: "环宇国际贸易有限公司",
            jobTitle: "市场经理",
            mobile: "139-0000-0002",
            email: "lina@example.com",
            website: "www.example.com",
            address: "上海市静安区南京西路500号",
            postalCode: "200041",
            tags: ["Customer", "VIP"],
            notes: "2026 春季展会",
            createdAt: Date(timeIntervalSince1970: 1_730_100_000)
        )
        let first = PersistentBusinessCardRepository(fileURL: fileURL)
        first.add(card)

        // 模拟重启：新建指向同一文件的实例。
        let reopened = PersistentBusinessCardRepository(fileURL: fileURL)
        XCTAssertEqual(reopened.fetchAll().count, 1)

        let restored = reopened.card(withID: card.id)
        XCTAssertEqual(restored, Optional(card))
        XCTAssertEqual(restored?.tags, ["Customer", "VIP"])
        XCTAssertEqual(restored?.notes, "2026 春季展会")
        XCTAssertEqual(restored?.website, "www.example.com")
        XCTAssertEqual(restored?.postalCode, "200041")
    }

    func testEditsSurviveRelaunch() {
        var card = BusinessCard(
            name: "张伟",
            company: "远景科技",
            createdAt: Date(timeIntervalSince1970: 1_730_000_000)
        )
        let first = PersistentBusinessCardRepository(fileURL: fileURL)
        first.add(card)

        card.company = "远景科技（新）"
        card.jobTitle = "技术总监"
        card.tags = ["Partner"]
        first.update(card)

        // 模拟重启：编辑后的内容应被保留。
        let reopened = PersistentBusinessCardRepository(fileURL: fileURL)
        let restored = reopened.card(withID: card.id)
        XCTAssertEqual(restored?.company, "远景科技（新）")
        XCTAssertEqual(restored?.jobTitle, "技术总监")
        XCTAssertEqual(restored?.tags, ["Partner"])
    }

    // MARK: - 容错

    func testCorruptedFileIsTreatedAsEmpty() throws {
        try Data("{ 这不是合法的 JSON".utf8).write(to: fileURL)

        let repository = PersistentBusinessCardRepository(fileURL: fileURL)
        XCTAssertTrue(repository.fetchAll().isEmpty)

        // 损坏文件被忽略后仍可正常写入并被重新读取。
        let card = makeCard(name: "张伟")
        repository.add(card)

        let reopened = PersistentBusinessCardRepository(fileURL: fileURL)
        XCTAssertEqual(reopened.fetchAll().map(\.name), ["张伟"])
    }

    func testCreatesMissingDirectoryOnWrite() {
        let missingDirectory = temporaryDirectory
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("deep", isDirectory: true)
        let nestedFileURL = missingDirectory.appendingPathComponent("business-cards.json")

        let repository = PersistentBusinessCardRepository(fileURL: nestedFileURL)
        repository.add(makeCard(name: "张伟"))

        XCTAssertTrue(FileManager.default.fileExists(atPath: nestedFileURL.path))
        let reopened = PersistentBusinessCardRepository(fileURL: nestedFileURL)
        XCTAssertEqual(reopened.fetchAll().map(\.name), ["张伟"])
    }

    func testConvenienceInitUsesDirectoryAndDefaultFileName() {
        let writer = PersistentBusinessCardRepository(directory: temporaryDirectory)
        writer.add(makeCard(name: "张伟"))

        let expectedURL = temporaryDirectory.appendingPathComponent("business-cards.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedURL.path))

        let reader = PersistentBusinessCardRepository(directory: temporaryDirectory)
        XCTAssertEqual(reader.fetchAll().map(\.name), ["张伟"])
    }
}
