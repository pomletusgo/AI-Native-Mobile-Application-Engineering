import XCTest
@testable import CamCardClone

/// 名片详情 / 编辑 ViewModel 单元测试。
///
/// 覆盖 T13 详情（含 `postalCode` / `department`）、T14 编辑保存、T16 标签增删、
/// T17 删除，以及 T20「姓名为空不得保存」；P06 详情展示原始图（5.1 第二段）另见文末一组用例。
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

    func testReloadExposesPostalCodeAndDepartment() {
        let card = BusinessCard(
            name: "李娜",
            company: "环宇国际贸易有限公司",
            address: "上海市浦东新区世纪大道 100 号",
            postalCode: "200120",
            department: "国际业务部"
        )
        let repository = InMemoryBusinessCardRepository(cards: [card])
        let viewModel = CardDetailViewModel(repository: repository, cardID: card.id)

        XCTAssertEqual(viewModel.card?.postalCode, "200120")
        XCTAssertEqual(viewModel.card?.department, "国际业务部")
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

    func testSaveEditingPersistsPostalCodeAndDepartment() {
        let (repository, card) = makeRepositoryWithCard()
        let viewModel = CardDetailViewModel(repository: repository, cardID: card.id)

        viewModel.beginEditing()
        viewModel.draft?.department = "技术中心"
        viewModel.draft?.postalCode = "200092"
        let result = viewModel.saveEditing()

        XCTAssertTrue(result)
        XCTAssertEqual(repository.card(withID: card.id)?.department, "技术中心")
        XCTAssertEqual(repository.card(withID: card.id)?.postalCode, "200092")
    }

    func testSaveEditingClearsOptionalFieldWhenEmptied() {
        let card = BusinessCard(name: "张伟", jobTitle: "技术总监")
        let repository = InMemoryBusinessCardRepository(cards: [card])
        let viewModel = CardDetailViewModel(repository: repository, cardID: card.id)

        viewModel.beginEditing()
        viewModel.draft?.jobTitle = nil
        viewModel.saveEditing()

        XCTAssertNil(repository.card(withID: card.id)?.jobTitle, "清空的字段应回到 nil，而不是空字符串")
    }

    // MARK: - T16 标签

    func testEditableTagsFallBackToSavedCardWhenNotEditing() {
        let card = BusinessCard(name: "张伟", tags: ["客户", "上海"])
        let repository = InMemoryBusinessCardRepository(cards: [card])
        let viewModel = CardDetailViewModel(repository: repository, cardID: card.id)

        XCTAssertFalse(viewModel.isEditing)
        XCTAssertEqual(viewModel.editableTags, ["客户", "上海"])
    }

    func testAddTagAppendsTrimmedTag() {
        let (repository, card) = makeRepositoryWithCard()
        let viewModel = CardDetailViewModel(repository: repository, cardID: card.id)
        viewModel.beginEditing()

        XCTAssertTrue(viewModel.addTag("  客户  "))

        XCTAssertEqual(viewModel.editableTags, ["客户"])
    }

    func testAddTagRejectsBlankTag() {
        let (repository, card) = makeRepositoryWithCard()
        let viewModel = CardDetailViewModel(repository: repository, cardID: card.id)
        viewModel.beginEditing()

        XCTAssertFalse(viewModel.addTag(""))
        XCTAssertFalse(viewModel.addTag("   "))
        XCTAssertTrue(viewModel.editableTags.isEmpty)
    }

    func testAddTagRejectsDuplicateIgnoringCase() {
        let card = BusinessCard(name: "张伟", tags: ["Client"])
        let repository = InMemoryBusinessCardRepository(cards: [card])
        let viewModel = CardDetailViewModel(repository: repository, cardID: card.id)
        viewModel.beginEditing()

        XCTAssertFalse(viewModel.addTag("client"))
        XCTAssertEqual(viewModel.editableTags, ["Client"], "重复标签不应被追加，也不应改变原有写法")
    }

    func testAddTagRequiresEditingState() {
        let (repository, card) = makeRepositoryWithCard()
        let viewModel = CardDetailViewModel(repository: repository, cardID: card.id)

        XCTAssertFalse(viewModel.addTag("客户"), "未进入编辑态时不得改动标签")
        XCTAssertTrue(viewModel.editableTags.isEmpty)
        XCTAssertEqual(repository.card(withID: card.id)?.tags, [])
    }

    func testRemoveTagDropsMatchingTagIgnoringCase() {
        let card = BusinessCard(name: "张伟", tags: ["Client", "上海"])
        let repository = InMemoryBusinessCardRepository(cards: [card])
        let viewModel = CardDetailViewModel(repository: repository, cardID: card.id)
        viewModel.beginEditing()

        XCTAssertTrue(viewModel.removeTag("client"))
        XCTAssertEqual(viewModel.editableTags, ["上海"])
    }

    func testRemoveTagReportsFalseForUnknownTag() {
        let card = BusinessCard(name: "张伟", tags: ["客户"])
        let repository = InMemoryBusinessCardRepository(cards: [card])
        let viewModel = CardDetailViewModel(repository: repository, cardID: card.id)
        viewModel.beginEditing()

        XCTAssertFalse(viewModel.removeTag("不存在"))
        XCTAssertEqual(viewModel.editableTags, ["客户"])
    }

    func testRemoveTagRequiresEditingState() {
        let card = BusinessCard(name: "张伟", tags: ["客户"])
        let repository = InMemoryBusinessCardRepository(cards: [card])
        let viewModel = CardDetailViewModel(repository: repository, cardID: card.id)

        XCTAssertFalse(viewModel.removeTag("客户"))
        XCTAssertEqual(repository.card(withID: card.id)?.tags, ["客户"])
    }

    func testTagEditsPersistOnSave() {
        let (repository, card) = makeRepositoryWithCard()
        let viewModel = CardDetailViewModel(repository: repository, cardID: card.id)

        viewModel.beginEditing()
        viewModel.addTag("客户")
        viewModel.addTag("重点")
        viewModel.removeTag("重点")
        let result = viewModel.saveEditing()

        XCTAssertTrue(result)
        XCTAssertEqual(repository.card(withID: card.id)?.tags, ["客户"])
    }

    func testCancelEditingDiscardsTagEdits() {
        let (repository, card) = makeRepositoryWithCard()
        let viewModel = CardDetailViewModel(repository: repository, cardID: card.id)

        viewModel.beginEditing()
        viewModel.addTag("客户")
        viewModel.cancelEditing()

        XCTAssertEqual(repository.card(withID: card.id)?.tags, [], "取消编辑必须丢弃这次标签改动")
        XCTAssertEqual(viewModel.editableTags, [])
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

    // MARK: - P06 详情展示原始图（5.1 第二段）

    private func makeImageStore() -> (store: FileCardImageStore, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CardDetailViewModelTests-\(UUID().uuidString)", isDirectory: true)
        return (FileCardImageStore(directory: directory), directory)
    }

    func testDisplayImageDataReturnsStoredOriginalImage() throws {
        let (store, directory) = makeImageStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let card = BusinessCard(name: "张伟")
        let bytes = Data([0x01, 0x02, 0x03])
        let name = try XCTUnwrap(store.save(bytes, cardID: card.id, kind: .original))
        var stored = card
        stored.originalImageName = name
        let repository = InMemoryBusinessCardRepository(cards: [stored])

        let viewModel = CardDetailViewModel(repository: repository, cardID: card.id, imageStore: store)

        XCTAssertEqual(viewModel.displayImageData, bytes)
    }

    func testDisplayImageDataFallsBackToProcessedImage() throws {
        let (store, directory) = makeImageStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let card = BusinessCard(name: "张伟")
        let bytes = Data([0x04, 0x05])
        let name = try XCTUnwrap(store.save(bytes, cardID: card.id, kind: .processed))
        var stored = card
        stored.processedImageName = name
        let repository = InMemoryBusinessCardRepository(cards: [stored])

        let viewModel = CardDetailViewModel(repository: repository, cardID: card.id, imageStore: store)

        XCTAssertEqual(viewModel.displayImageData, bytes, "原始图缺失时应退回校正图，而不是不显示")
    }

    func testDisplayImageDataIsNilWithoutStore() {
        let (repository, card) = makeRepositoryWithCard()
        let viewModel = CardDetailViewModel(repository: repository, cardID: card.id)

        XCTAssertNil(viewModel.displayImageData)
    }

    func testDeleteCleansUpStoredImages() throws {
        let (store, directory) = makeImageStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let card = BusinessCard(name: "张伟")
        let name = try XCTUnwrap(store.save(Data([0x09]), cardID: card.id, kind: .original))
        let repository = InMemoryBusinessCardRepository(cards: [card])
        let viewModel = CardDetailViewModel(repository: repository, cardID: card.id, imageStore: store)

        viewModel.delete()

        XCTAssertNil(store.load(named: name), "删除名片后应清理图像文件")
    }

    // MARK: - P10 导出

    func testExportToContactsReportsSavedAndWritesCard() async {
        let (repository, card) = makeRepositoryWithCard()
        let exporter = FakeContactExporter(status: .authorized)
        let viewModel = CardDetailViewModel(
            repository: repository,
            cardID: card.id,
            contactExporter: exporter
        )

        await viewModel.exportToContacts()

        XCTAssertEqual(viewModel.exportNotice, .saved)
        XCTAssertEqual(exporter.savedCards.map(\.id), [card.id])
    }

    func testExportToContactsReportsPermissionDeniedWithoutWriting() async {
        let (repository, card) = makeRepositoryWithCard()
        let exporter = FakeContactExporter(status: .denied)
        let viewModel = CardDetailViewModel(
            repository: repository,
            cardID: card.id,
            contactExporter: exporter
        )

        await viewModel.exportToContacts()

        XCTAssertEqual(viewModel.exportNotice, .permissionDenied)
        XCTAssertTrue(exporter.savedCards.isEmpty)
    }

    func testExportToContactsReportsFailureWhenWritingFails() async {
        let (repository, card) = makeRepositoryWithCard()
        let exporter = FakeContactExporter(status: .authorized, saveError: ExportStubFailure())
        let viewModel = CardDetailViewModel(
            repository: repository,
            cardID: card.id,
            contactExporter: exporter
        )

        await viewModel.exportToContacts()

        XCTAssertEqual(viewModel.exportNotice, .failed)
    }

    func testExportToContactsWithoutExporterKeepsNoticeEmpty() async {
        let (repository, card) = makeRepositoryWithCard()
        let viewModel = CardDetailViewModel(repository: repository, cardID: card.id)

        await viewModel.exportToContacts()

        XCTAssertFalse(viewModel.canExportToContacts, "没有导出器时界面不应提供入口")
        XCTAssertNil(viewModel.exportNotice)
    }

    func testClearExportNoticeResetsNotice() async {
        let (repository, card) = makeRepositoryWithCard()
        let viewModel = CardDetailViewModel(
            repository: repository,
            cardID: card.id,
            contactExporter: FakeContactExporter(status: .authorized)
        )
        await viewModel.exportToContacts()

        viewModel.clearExportNotice()

        XCTAssertNil(viewModel.exportNotice)
    }

    func testVCardTextMatchesExporterOutput() {
        let card = BusinessCard(name: "张伟", company: "远景科技", mobile: "138-0000-0001")
        let repository = InMemoryBusinessCardRepository(cards: [card])
        let viewModel = CardDetailViewModel(repository: repository, cardID: card.id)

        XCTAssertEqual(viewModel.vCardText, VCardExporter.vCard(for: card))
    }

    func testVCardTextIsNilForMissingCard() {
        let viewModel = CardDetailViewModel(repository: InMemoryBusinessCardRepository(), cardID: UUID())

        XCTAssertNil(viewModel.vCardText)
        XCTAssertNil(viewModel.makeVCardFileURL())
    }

    func testMakeVCardFileURLWritesShareableFile() throws {
        let card = BusinessCard(name: "张伟", company: "远景科技")
        let repository = InMemoryBusinessCardRepository(cards: [card])
        let viewModel = CardDetailViewModel(repository: repository, cardID: card.id)

        let url = try XCTUnwrap(viewModel.makeVCardFileURL())
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(url.pathExtension, "vcf")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), VCardExporter.vCard(for: card))
    }
}

/// 导出失败用例用的错误类型。
private struct ExportStubFailure: Error {}
