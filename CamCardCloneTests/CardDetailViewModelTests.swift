import XCTest
@testable import CamCardClone

/// 名片详情 / 编辑 ViewModel 单元测试。
///
/// 覆盖 T13 详情、T14 编辑保存、T17 删除，以及 T20「姓名为空不得保存」。
@MainActor
final class CardDetailViewModelTests: XCTestCase {

    private func makeRepositoryWithCard() -> (repository: InMemoryBusinessCardRepository, card: BusinessCard) {
        let card = BusinessCard(
            name: "张伟",
            company: "远景科技",
            jobTitle: "技术总监",
            mobile: "138-0000-0001"
        )
        return (InMemoryBusinessCardRepository(cards: [card]), card)
    }

    // MARK: - T13 详情

    func testReloadFindsExistingCard() {
        let (repository, card) = makeRepositoryWithCard()
        let viewModel = CardDetailViewModel(repository: repository, cardID: card.id)

        XCTAssertFalse(viewModel.isMissing)
        XCTAssertEqual(viewModel.card?.name, "张伟")
        XCTAssertFalse(viewModel.isEditing)
    }

    func testMissingCardReportsMissing() {
        let repository = InMemoryBusinessCardRepository()
        let viewModel = CardDetailViewModel(repository: repository, cardID: UUID())

        XCTAssertTrue(viewModel.isMissing)
        XCTAssertNil(viewModel.card)
    }

    // MARK: - T14 编辑

    func testBeginEditingCreatesDraftCopy() {
        let (repository, card) = makeRepositoryWithCard()
        let viewModel = CardDetailViewModel(repository: repository, cardID: card.id)

        viewModel.beginEditing()

        XCTAssertTrue(viewModel.isEditing)
        XCTAssertEqual(viewModel.draft?.name, "张伟")
        // 编辑态下修改草稿不应影响已保存数据
        viewModel.draft?.name = "张伟（改）"
        XCTAssertEqual(viewModel.card?.name, "张伟")
    }

    func testCancelEditingDiscardsDraft() {
        let (repository, card) = makeRepositoryWithCard()
        let viewModel = CardDetailViewModel(repository: repository, cardID: card.id)

        viewModel.beginEditing()
        viewModel.draft?.name = "不应保存"
        viewModel.cancelEditing()

        XCTAssertFalse(viewModel.isEditing)
        XCTAssertEqual(viewModel.card?.name, "张伟")
    }

    func testSaveEditingPersistsChanges() {
        let (repository, card) = makeRepositoryWithCard()
        let viewModel = CardDetailViewModel(repository: repository, cardID: card.id)

        viewModel.beginEditing()
        viewModel.draft?.name = "张伟明"
        viewModel.draft?.company = "远景科技（上海）"
        let result = viewModel.saveEditing()

        XCTAssertTrue(result)
        XCTAssertFalse(viewModel.isEditing)
        XCTAssertEqual(repository.card(withID: card.id)?.name, "张伟明")
        XCTAssertEqual(repository.card(withID: card.id)?.company, "远景科技（上海）")
    }

    func testSaveEditingTrimsWhitespaceInName() {
        let (repository, card) = makeRepositoryWithCard()
        let viewModel = CardDetailViewModel(repository: repository, cardID: card.id)

        viewModel.beginEditing()
        viewModel.draft?.name = "  李娜  "
        viewModel.saveEditing()

        XCTAssertEqual(repository.card(withID: card.id)?.name, "李娜")
    }

    // MARK: - T20 字段为空

    func testSaveEditingRejectsWhitespaceOnlyName() {
        let (repository, card) = makeRepositoryWithCard()
        let viewModel = CardDetailViewModel(repository: repository, cardID: card.id)

        viewModel.beginEditing()
        viewModel.draft?.name = "   "
        let result = viewModel.saveEditing()

        XCTAssertFalse(result, "姓名为空时必须拒绝保存")
        XCTAssertTrue(viewModel.isEditing, "保存失败后应保持编辑态")
        XCTAssertEqual(repository.card(withID: card.id)?.name, "张伟", "原始数据不应被破坏")
    }

    func testSaveWithoutEditingReturnsFalse() {
        let (repository, card) = makeRepositoryWithCard()
        let viewModel = CardDetailViewModel(repository: repository, cardID: card.id)

        XCTAssertFalse(viewModel.saveEditing())
    }

    // MARK: - T17 删除

    func testDeleteRemovesCardFromRepository() {
        let (repository, card) = makeRepositoryWithCard()
        let viewModel = CardDetailViewModel(repository: repository, cardID: card.id)

        viewModel.delete()

        XCTAssertTrue(repository.fetchAll().isEmpty)
        XCTAssertTrue(viewModel.isMissing)
    }
}
