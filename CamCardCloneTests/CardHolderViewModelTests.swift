import XCTest
@testable import CamCardClone

/// 名片夹 ViewModel 单元测试。
///
/// 覆盖 T01 空状态、T15 搜索、T16 标签筛选、T17 删除后的列表更新。
@MainActor
final class CardHolderViewModelTests: XCTestCase {

    private func makeCard(
        name: String,
        company: String? = nil,
        email: String? = nil,
        tags: [String] = [],
        createdAtOffset: TimeInterval = 0
    ) -> BusinessCard {
        BusinessCard(
            name: name,
            company: company,
            email: email,
            tags: tags,
            createdAt: Date(timeIntervalSince1970: createdAtOffset)
        )
    }

    // MARK: - S1 空名片夹（T01）

    func testEmptyStateWhenNoCards() {
        let viewModel = CardHolderViewModel(repository: InMemoryBusinessCardRepository())
        viewModel.load()

        XCTAssertTrue(viewModel.isEmpty)
        XCTAssertTrue(viewModel.visibleCards.isEmpty)
        XCTAssertFalse(viewModel.hasNoResults)
    }

    // MARK: - S2 有名片

    func testLoadShowsCards() {
        let repository = InMemoryBusinessCardRepository(cards: [
            makeCard(name: "张伟", createdAtOffset: 100),
            makeCard(name: "李娜", createdAtOffset: 200)
        ])
        let viewModel = CardHolderViewModel(repository: repository)
        viewModel.load()

        XCTAssertFalse(viewModel.isEmpty)
        XCTAssertEqual(viewModel.visibleCards.map(\.name), ["李娜", "张伟"])
    }

    // MARK: - S3 搜索中

    func testSearchFiltersVisibleCards() {
        let repository = InMemoryBusinessCardRepository(cards: [
            makeCard(name: "张伟", company: "远景科技"),
            makeCard(name: "李娜", company: "环宇贸易")
        ])
        let viewModel = CardHolderViewModel(repository: repository)
        viewModel.load()

        viewModel.searchText = "环宇"
        XCTAssertEqual(viewModel.visibleCards.map(\.name), ["李娜"])
        XCTAssertTrue(viewModel.isSearching)
        XCTAssertFalse(viewModel.hasNoResults)
    }

    func testSearchWithNoResultReportsHasNoResults() {
        let repository = InMemoryBusinessCardRepository(cards: [makeCard(name: "张伟")])
        let viewModel = CardHolderViewModel(repository: repository)
        viewModel.load()

        viewModel.searchText = "不存在"
        XCTAssertTrue(viewModel.visibleCards.isEmpty)
        XCTAssertTrue(viewModel.hasNoResults)
        XCTAssertFalse(viewModel.isEmpty)
    }

    // MARK: - S4 标签筛选（T16）

    func testToggleTagFilter() {
        let repository = InMemoryBusinessCardRepository(cards: [
            makeCard(name: "A", tags: ["Conference"]),
            makeCard(name: "B", tags: ["Customer"])
        ])
        let viewModel = CardHolderViewModel(repository: repository)
        viewModel.load()

        viewModel.toggleTagFilter("Conference")
        XCTAssertEqual(viewModel.selectedTag, "Conference")
        XCTAssertEqual(viewModel.visibleCards.map(\.name), ["A"])

        // 再次点击同一标签应取消筛选
        viewModel.toggleTagFilter("Conference")
        XCTAssertNil(viewModel.selectedTag)
        XCTAssertEqual(viewModel.visibleCards.count, 2)
    }

    func testSearchAndTagFilterCombine() {
        let repository = InMemoryBusinessCardRepository(cards: [
            makeCard(name: "A", company: "远景科技", tags: ["Conference"]),
            makeCard(name: "B", company: "远景科技", tags: ["Customer"]),
            makeCard(name: "C", company: "环宇贸易", tags: ["Conference"])
        ])
        let viewModel = CardHolderViewModel(repository: repository)
        viewModel.load()

        viewModel.searchText = "远景"
        viewModel.toggleTagFilter("Conference")

        XCTAssertEqual(viewModel.visibleCards.map(\.name), ["A"])
    }

    func testAllTagsExposedFromRepository() {
        let repository = InMemoryBusinessCardRepository(cards: [
            makeCard(name: "A", tags: ["Conference"]),
            makeCard(name: "B", tags: ["Customer"])
        ])
        let viewModel = CardHolderViewModel(repository: repository)

        XCTAssertEqual(viewModel.allTags, ["Conference", "Customer"])
    }

    // MARK: - T17 删除

    func testDeleteRemovesCardAndReloads() {
        let repository = InMemoryBusinessCardRepository(cards: [
            makeCard(name: "张伟", createdAtOffset: 100),
            makeCard(name: "李娜", createdAtOffset: 200)
        ])
        let viewModel = CardHolderViewModel(repository: repository)
        viewModel.load()

        let target = viewModel.visibleCards.first { $0.name == "张伟" }!
        viewModel.delete(id: target.id)

        XCTAssertEqual(viewModel.visibleCards.map(\.name), ["李娜"])
        XCTAssertFalse(viewModel.isEmpty)
    }

    func testDeleteLastCardReturnsToEmptyState() {
        let repository = InMemoryBusinessCardRepository(cards: [makeCard(name: "张伟")])
        let viewModel = CardHolderViewModel(repository: repository)
        viewModel.load()

        viewModel.delete(id: viewModel.visibleCards[0].id)

        XCTAssertTrue(viewModel.isEmpty)
    }

    func testDeleteAtIndexOffsetsUsesVisibleOrder() {
        let repository = InMemoryBusinessCardRepository(cards: [
            makeCard(name: "旧", createdAtOffset: 100),
            makeCard(name: "新", createdAtOffset: 200)
        ])
        let viewModel = CardHolderViewModel(repository: repository)
        viewModel.load()

        // visibleCards = [新, 旧]，删除第 0 行应删掉「新」
        viewModel.delete(at: IndexSet(integer: 0))

        XCTAssertEqual(viewModel.visibleCards.map(\.name), ["旧"])
    }
}
