import XCTest
@testable import CamCardClone

/// Repository 层单元测试（`InMemoryBusinessCardRepository`）。
///
/// 覆盖 T12 保存、T14 编辑、T15 搜索、T16 标签、T17 删除的仓储行为。
final class BusinessCardRepositoryTests: XCTestCase {

    private func makeCard(
        name: String,
        company: String? = nil,
        jobTitle: String? = nil,
        email: String? = nil,
        tags: [String] = [],
        createdAtOffset: TimeInterval = 0
    ) -> BusinessCard {
        BusinessCard(
            name: name,
            company: company,
            jobTitle: jobTitle,
            email: email,
            tags: tags,
            createdAt: Date(timeIntervalSince1970: createdAtOffset)
        )
    }

    // MARK: - 增删改查

    func testNewRepositoryIsEmpty() {
        let repository = InMemoryBusinessCardRepository()
        XCTAssertTrue(repository.fetchAll().isEmpty)
    }

    func testAddAndFetchAll() {
        let repository = InMemoryBusinessCardRepository()
        repository.add(makeCard(name: "张伟"))

        let all = repository.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.name, "张伟")
    }

    func testFetchAllSortedByCreatedAtDescending() {
        let repository = InMemoryBusinessCardRepository()
        repository.add(makeCard(name: "旧", createdAtOffset: 100))
        repository.add(makeCard(name: "新", createdAtOffset: 200))
        repository.add(makeCard(name: "中", createdAtOffset: 150))

        XCTAssertEqual(repository.fetchAll().map(\.name), ["新", "中", "旧"])
    }

    func testCardWithIDReturnsMatchingCard() {
        let repository = InMemoryBusinessCardRepository()
        let card = makeCard(name: "李娜")
        repository.add(card)

        XCTAssertEqual(repository.card(withID: card.id)?.name, "李娜")
        XCTAssertNil(repository.card(withID: UUID()))
    }

    func testUpdateReplacesExistingCard() {
        let repository = InMemoryBusinessCardRepository()
        var card = makeCard(name: "张伟", company: "远景科技")
        repository.add(card)

        card.company = "远景科技（新）"
        card.jobTitle = "技术总监"
        repository.update(card)

        let stored = repository.card(withID: card.id)
        XCTAssertEqual(stored?.company, "远景科技（新）")
        XCTAssertEqual(stored?.jobTitle, "技术总监")
        XCTAssertEqual(repository.fetchAll().count, 1)
    }

    func testUpdateIgnoresUnknownCard() {
        let repository = InMemoryBusinessCardRepository()
        repository.add(makeCard(name: "张伟"))

        repository.update(makeCard(name: "不存在"))
        XCTAssertEqual(repository.fetchAll().count, 1)
    }

    func testDeleteRemovesCard() {
        let repository = InMemoryBusinessCardRepository()
        let card = makeCard(name: "张伟")
        repository.add(card)
        repository.add(makeCard(name: "李娜"))

        repository.delete(id: card.id)

        XCTAssertNil(repository.card(withID: card.id))
        XCTAssertEqual(repository.fetchAll().map(\.name), ["李娜"])
    }

    // MARK: - 搜索（T15）

    func testSearchByExactName() {
        let repository = InMemoryBusinessCardRepository(cards: [
            makeCard(name: "张伟", company: "远景科技"),
            makeCard(name: "李娜", company: "环宇贸易")
        ])

        XCTAssertEqual(repository.search("张伟").map(\.name), ["张伟"])
    }

    func testSearchByCompany() {
        let repository = InMemoryBusinessCardRepository(cards: [
            makeCard(name: "张伟", company: "远景科技"),
            makeCard(name: "李娜", company: "环宇贸易")
        ])

        XCTAssertEqual(repository.search("环宇").map(\.name), ["李娜"])
    }

    func testSearchIsCaseInsensitive() {
        let repository = InMemoryBusinessCardRepository(cards: [
            makeCard(name: "David Chen", company: "ABC Technologies")
        ])

        XCTAssertEqual(repository.search("abc").count, 1)
        XCTAssertEqual(repository.search("DAVID").count, 1)
    }

    func testSearchWithEmptyKeywordReturnsAll() {
        let repository = InMemoryBusinessCardRepository(cards: [
            makeCard(name: "张伟"),
            makeCard(name: "李娜")
        ])

        XCTAssertEqual(repository.search("   ").count, 2)
    }

    func testSearchWithNoMatchReturnsEmpty() {
        let repository = InMemoryBusinessCardRepository(cards: [makeCard(name: "张伟")])
        XCTAssertTrue(repository.search("不存在的关键字").isEmpty)
    }

    // MARK: - 标签（T16）

    func testCardsTaggedWithIsCaseInsensitive() {
        let repository = InMemoryBusinessCardRepository(cards: [
            makeCard(name: "A", tags: ["Conference"]),
            makeCard(name: "B", tags: ["Customer"]),
            makeCard(name: "C", tags: [])
        ])

        XCTAssertEqual(repository.cards(taggedWith: "conference").map(\.name), ["A"])
        XCTAssertEqual(repository.cards(taggedWith: "Conference").map(\.name), ["A"])
        XCTAssertTrue(repository.cards(taggedWith: "Unknown").isEmpty)
    }

    func testAllTagsDeduplicatedCaseInsensitiveAndSorted() {
        let repository = InMemoryBusinessCardRepository(cards: [
            makeCard(name: "A", tags: ["Conference", "Customer"]),
            makeCard(name: "B", tags: ["conference", "Partner"])
        ])

        XCTAssertEqual(repository.allTags, ["Conference", "Customer", "Partner"])
    }
}
