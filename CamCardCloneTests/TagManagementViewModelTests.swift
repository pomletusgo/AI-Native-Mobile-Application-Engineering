import XCTest
@testable import CamCardClone

/// `TagManagementViewModel` 单元测试，覆盖 P09「创建 / 添加 / 按标签查看 / 删除标签」中的全局管理部分。
///
/// 这里验证的是标签管理页的读写语义（张数统计、按标签查看、删除整个标签、新建标签的校验与落盘）；
/// 页面呈现与手势属人工验收，见 `docs/UI验收清单.md`。
@MainActor
final class TagManagementViewModelTests: XCTestCase {

    private func makeCard(_ name: String, tags: [String] = []) -> BusinessCard {
        var card = BusinessCard(name: name)
        card.tags = tags
        return card
    }

    private func makeRepository(_ cards: [BusinessCard]) -> InMemoryBusinessCardRepository {
        InMemoryBusinessCardRepository(cards: cards)
    }

    // MARK: - 标签列表与张数

    func testLoadExposesTagsWithCardCounts() {
        let repository = makeRepository([
            makeCard("张伟", tags: ["VIP", "客户"]),
            makeCard("李娜", tags: ["VIP"])
        ])
        let viewModel = TagManagementViewModel(repository: repository)

        XCTAssertEqual(Set(viewModel.tags.map(\.name)), ["VIP", "客户"])
        XCTAssertEqual(viewModel.tags.first { $0.name == "VIP" }?.cardCount, 2)
        XCTAssertEqual(viewModel.tags.first { $0.name == "客户" }?.cardCount, 1)
    }

    func testCardWithRepeatedTagCountsOnce() {
        let repository = makeRepository([makeCard("张伟", tags: ["VIP", "vip"])])
        let viewModel = TagManagementViewModel(repository: repository)

        XCTAssertEqual(viewModel.tags.count, 1)
        XCTAssertEqual(viewModel.tags.first?.cardCount, 1)
    }

    func testEmptyRepositoryHasNoTags() {
        let viewModel = TagManagementViewModel(repository: makeRepository([]))

        XCTAssertTrue(viewModel.tags.isEmpty)
        XCTAssertTrue(viewModel.cards.isEmpty)
        XCTAssertNil(viewModel.viewingTag)
        XCTAssertFalse(viewModel.isCreating)
    }

    // MARK: - 删除标签

    func testDeleteTagRemovesItFromEveryCard() {
        let cardA = makeCard("张伟", tags: ["VIP", "客户"])
        let cardB = makeCard("李娜", tags: ["VIP"])
        let repository = makeRepository([cardA, cardB])
        let viewModel = TagManagementViewModel(repository: repository)

        XCTAssertTrue(viewModel.deleteTag("VIP"))

        XCTAssertEqual(repository.card(withID: cardA.id)?.tags, ["客户"])
        XCTAssertEqual(repository.card(withID: cardB.id)?.tags, [])
        XCTAssertEqual(viewModel.tags.map(\.name), ["客户"])
    }

    func testDeleteTagIsCaseInsensitive() {
        let card = makeCard("张伟", tags: ["VIP"])
        let repository = makeRepository([card])
        let viewModel = TagManagementViewModel(repository: repository)

        XCTAssertTrue(viewModel.deleteTag("vip"))

        XCTAssertEqual(repository.card(withID: card.id)?.tags, [])
        XCTAssertTrue(viewModel.tags.isEmpty)
    }

    func testDeleteUnknownTagChangesNothing() {
        let card = makeCard("张伟", tags: ["VIP"])
        let repository = makeRepository([card])
        let viewModel = TagManagementViewModel(repository: repository)

        XCTAssertFalse(viewModel.deleteTag("不存在"))

        XCTAssertEqual(repository.card(withID: card.id)?.tags, ["VIP"])
        XCTAssertEqual(viewModel.tags.map(\.name), ["VIP"])
    }

    // MARK: - 按标签查看

    func testBeginViewingShowsOnlyCardsWithThatTag() {
        let cardA = makeCard("张伟", tags: ["VIP"])
        let cardB = makeCard("李娜", tags: ["客户"])
        let viewModel = TagManagementViewModel(repository: makeRepository([cardA, cardB]))

        viewModel.beginViewing(tag: "VIP")

        XCTAssertEqual(viewModel.viewingTag, "VIP")
        XCTAssertEqual(viewModel.viewingCards.map(\.name), ["张伟"])
    }

    func testViewingCardsIsCaseInsensitive() {
        let card = makeCard("张伟", tags: ["VIP"])
        let viewModel = TagManagementViewModel(repository: makeRepository([card]))

        viewModel.beginViewing(tag: "vip")

        XCTAssertEqual(viewModel.viewingCards.map(\.name), ["张伟"])
    }

    func testEndViewingClearsViewedCards() {
        let viewModel = TagManagementViewModel(repository: makeRepository([makeCard("张伟", tags: ["VIP"])]))

        viewModel.beginViewing(tag: "VIP")
        viewModel.endViewing()

        XCTAssertNil(viewModel.viewingTag)
        XCTAssertTrue(viewModel.viewingCards.isEmpty)
    }

    func testDeletingViewedTagEndsViewing() {
        let viewModel = TagManagementViewModel(repository: makeRepository([makeCard("张伟", tags: ["VIP"])]))

        viewModel.beginViewing(tag: "VIP")
        viewModel.deleteTag("VIP")

        XCTAssertNil(viewModel.viewingTag, "正在查看的标签被删除后不应停在已不存在的筛选上")
    }

    // MARK: - 新建标签

    func testBeginCreatingClearsPreviousDraft() {
        let card = makeCard("张伟")
        let viewModel = TagManagementViewModel(repository: makeRepository([card]))

        viewModel.beginCreating()
        viewModel.newTagName = "旧输入"
        viewModel.toggleSelection(card.id)

        viewModel.beginCreating()

        XCTAssertTrue(viewModel.isCreating)
        XCTAssertEqual(viewModel.newTagName, "")
        XCTAssertTrue(viewModel.selectedCardIDs.isEmpty)
        XCTAssertNil(viewModel.creationError)
    }

    func testToggleSelectionAddsAndRemoves() {
        let card = makeCard("张伟")
        let viewModel = TagManagementViewModel(repository: makeRepository([card]))

        viewModel.beginCreating()
        viewModel.toggleSelection(card.id)
        XCTAssertEqual(viewModel.selectedCardIDs, [card.id])

        viewModel.toggleSelection(card.id)
        XCTAssertTrue(viewModel.selectedCardIDs.isEmpty)
    }

    func testSaveNewTagAttachesTagToSelectedCards() {
        let cardA = makeCard("张伟")
        let cardB = makeCard("李娜")
        let repository = makeRepository([cardA, cardB])
        let viewModel = TagManagementViewModel(repository: repository)

        viewModel.beginCreating()
        viewModel.newTagName = "重点"
        viewModel.toggleSelection(cardA.id)

        XCTAssertTrue(viewModel.saveNewTag())

        XCTAssertEqual(repository.card(withID: cardA.id)?.tags, ["重点"])
        XCTAssertEqual(repository.card(withID: cardB.id)?.tags, [])
        XCTAssertFalse(viewModel.isCreating, "保存成功后应退出新建流程")
    }

    func testSaveNewTagUpdatesTagList() {
        let card = makeCard("张伟", tags: ["VIP"])
        let viewModel = TagManagementViewModel(repository: makeRepository([card]))

        viewModel.beginCreating()
        viewModel.newTagName = "重点"
        viewModel.toggleSelection(card.id)
        viewModel.saveNewTag()

        XCTAssertEqual(Set(viewModel.tags.map(\.name)), ["VIP", "重点"])
        XCTAssertEqual(viewModel.tags.first { $0.name == "重点" }?.cardCount, 1)
    }

    func testSaveNewTagTrimsWhitespace() {
        let card = makeCard("张伟")
        let repository = makeRepository([card])
        let viewModel = TagManagementViewModel(repository: repository)

        viewModel.beginCreating()
        viewModel.newTagName = "  重点  "
        viewModel.toggleSelection(card.id)

        XCTAssertTrue(viewModel.saveNewTag())
        XCTAssertEqual(repository.card(withID: card.id)?.tags, ["重点"])
    }

    func testSaveNewTagRejectsBlankName() {
        let card = makeCard("张伟")
        let repository = makeRepository([card])
        let viewModel = TagManagementViewModel(repository: repository)

        viewModel.beginCreating()
        viewModel.newTagName = "   "
        viewModel.toggleSelection(card.id)

        XCTAssertFalse(viewModel.saveNewTag())
        XCTAssertNotNil(viewModel.creationError)
        XCTAssertTrue(viewModel.isCreating, "被拒后应停留在新建流程以便改正")
        XCTAssertEqual(repository.card(withID: card.id)?.tags, [])
    }

    func testSaveNewTagRejectsDuplicateIgnoringCase() {
        let card = makeCard("张伟", tags: ["VIP"])
        let repository = makeRepository([card])
        let viewModel = TagManagementViewModel(repository: repository)

        viewModel.beginCreating()
        viewModel.newTagName = "vip"
        viewModel.toggleSelection(card.id)

        XCTAssertFalse(viewModel.saveNewTag())
        XCTAssertNotNil(viewModel.creationError)
        XCTAssertEqual(repository.card(withID: card.id)?.tags, ["VIP"], "重名不得追加出第二个标签")
    }

    func testSaveNewTagRejectsEmptySelection() {
        let card = makeCard("张伟", tags: ["VIP"])
        let repository = makeRepository([card])
        let viewModel = TagManagementViewModel(repository: repository)

        viewModel.beginCreating()
        viewModel.newTagName = "重点"

        XCTAssertFalse(viewModel.saveNewTag())
        XCTAssertNotNil(viewModel.creationError)
        XCTAssertEqual(repository.card(withID: card.id)?.tags, ["VIP"])
    }

    func testCancelCreatingLeavesRepositoryUntouched() {
        let card = makeCard("张伟")
        let repository = makeRepository([card])
        let viewModel = TagManagementViewModel(repository: repository)

        viewModel.beginCreating()
        viewModel.newTagName = "重点"
        viewModel.toggleSelection(card.id)
        viewModel.cancelCreating()

        XCTAssertFalse(viewModel.isCreating)
        XCTAssertEqual(viewModel.newTagName, "")
        XCTAssertTrue(viewModel.selectedCardIDs.isEmpty)
        XCTAssertEqual(repository.card(withID: card.id)?.tags, [])
    }
}
