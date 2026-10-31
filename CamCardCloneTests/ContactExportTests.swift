import Contacts
import XCTest
@testable import CamCardClone

/// 可指定授权状态与写入结果的假导出器。
///
/// 放在文件作用域是为了让详情页 ViewModel 的测试复用同一份替身，
/// 避免两个测试文件各自维护一份会走样的假实现。
final class FakeContactExporter: ContactExporting {

    /// 当前授权状态。
    var status: CNAuthorizationStatus
    /// 申请之后返回的状态。
    var statusAfterRequest: CNAuthorizationStatus
    /// 非 `nil` 时 `save` 抛错，用于模拟写入失败。
    var saveError: Error?

    private(set) var requestCount = 0
    private(set) var savedCards: [BusinessCard] = []

    init(
        status: CNAuthorizationStatus,
        statusAfterRequest: CNAuthorizationStatus = .authorized,
        saveError: Error? = nil
    ) {
        self.status = status
        self.statusAfterRequest = statusAfterRequest
        self.saveError = saveError
    }

    func authorizationStatus() -> CNAuthorizationStatus { status }

    func requestAccess() async -> CNAuthorizationStatus {
        requestCount += 1
        status = statusAfterRequest
        return status
    }

    func save(_ card: BusinessCard) throws {
        if let saveError { throw saveError }
        savedCards.append(card)
    }
}

/// 联系人导出单元测试（P10 / T19）。
///
/// 覆盖三块：名片 → 系统联系人条目的字段映射（缺失字段不写占位值）、
/// 授权状态的判定、以及「查询 → 按需申请 → 写入」这段流程的各条分支。
///
/// 用测试替身驱动授权与写入，因此不依赖通讯录权限弹窗，也不写入真实通讯录。
final class ContactExportTests: XCTestCase {

    private struct SaveFailure: Error {}

    private func makeCard(
        name: String = "张伟",
        company: String? = "远景科技",
        jobTitle: String? = "技术总监",
        mobile: String? = "138-0000-0001"
    ) -> BusinessCard {
        BusinessCard(name: name, company: company, jobTitle: jobTitle, mobile: mobile)
    }

    // MARK: - 字段映射：基本信息

    func testContactCarriesNameOrganizationAndDepartment() {
        let card = BusinessCard(name: "李娜", company: "环宇国际贸易", department: "国际业务部")

        let contact = ContactExportMapping.contact(from: card)

        XCTAssertEqual(contact.givenName, "李娜")
        XCTAssertEqual(contact.organizationName, "环宇国际贸易")
        XCTAssertEqual(contact.departmentName, "国际业务部")
    }

    func testOrganizationFallsBackToDepartmentWhenCompanyIsMissing() {
        let card = BusinessCard(name: "王芳", department: "销售部")

        let contact = ContactExportMapping.contact(from: card)

        XCTAssertEqual(contact.organizationName, "销售部")
    }

    func testContactCarriesJobTitle() {
        let contact = ContactExportMapping.contact(from: makeCard())

        XCTAssertEqual(contact.jobTitle, "技术总监")
    }

    // MARK: - 字段映射：联系方式

    func testMobileMainAndFaxMapWithDistinctLabels() {
        let card = BusinessCard(
            name: "张伟",
            mobile: "138-0000-0001",
            phone: "021-8888-0001",
            fax: "021-8888-0002"
        )

        let contact = ContactExportMapping.contact(from: card)

        let labels = contact.phoneNumbers.map(\.label)
        XCTAssertEqual(labels, [CNLabelPhoneNumberMobile, CNLabelPhoneNumberMain, CNLabelFax])
        XCTAssertEqual(contact.phoneNumbers[0].value.stringValue, "138-0000-0001")
        XCTAssertEqual(contact.phoneNumbers[2].value.stringValue, "021-8888-0002")
    }

    func testAbsentFaxProducesNoPhoneEntry() {
        let card = BusinessCard(name: "张伟", mobile: "138-0000-0001", phone: "021-8888-0001")

        let contact = ContactExportMapping.contact(from: card)

        XCTAssertEqual(contact.phoneNumbers.map(\.label), [CNLabelPhoneNumberMobile, CNLabelPhoneNumberMain])
        XCTAssertFalse(contact.phoneNumbers.contains { $0.label == CNLabelFax })
    }

    func testEmailMapsToWorkLabel() {
        let card = BusinessCard(name: "张伟", email: "zhangwei@example.com")

        let contact = ContactExportMapping.contact(from: card)

        XCTAssertEqual(contact.emailAddresses.count, 1)
        XCTAssertEqual(contact.emailAddresses[0].label, CNLabelWork)
        XCTAssertEqual(contact.emailAddresses[0].value as String, "zhangwei@example.com")
    }

    func testAbsentEmailProducesNoEmailEntry() {
        let contact = ContactExportMapping.contact(from: makeCard())

        XCTAssertTrue(contact.emailAddresses.isEmpty)
    }

    func testWebsiteMapsToHomePageURL() {
        let card = BusinessCard(name: "张伟", website: "https://example.com")

        let contact = ContactExportMapping.contact(from: card)

        XCTAssertEqual(contact.urlAddresses.count, 1)
        XCTAssertEqual(contact.urlAddresses[0].value as String, "https://example.com")
    }

    func testAddressAndPostalCodeMapToPostalAddress() {
        let card = BusinessCard(
            name: "李娜",
            address: "上海市浦东新区世纪大道 100 号",
            postalCode: "200120"
        )

        let contact = ContactExportMapping.contact(from: card)

        XCTAssertEqual(contact.postalAddresses.count, 1)
        XCTAssertEqual(contact.postalAddresses[0].value.street, "上海市浦东新区世纪大道 100 号")
        XCTAssertEqual(contact.postalAddresses[0].value.postalCode, "200120")
    }

    func testAbsentAddressAndPostalCodeProduceNoPostalAddress() {
        let contact = ContactExportMapping.contact(from: makeCard())

        XCTAssertTrue(contact.postalAddresses.isEmpty)
    }

    func testNotesMapToNote() {
        let card = BusinessCard(name: "张伟", notes: "展会认识，关注企业版")

        XCTAssertEqual(ContactExportMapping.contact(from: card).note, "展会认识，关注企业版")
    }

    // MARK: - 字段映射：不得伪造

    func testEmptyOptionalFieldsBecomeEmptyNotPlaceholder() {
        let card = BusinessCard(name: "张伟", company: "", department: "", jobTitle: "", notes: "")

        let contact = ContactExportMapping.contact(from: card)

        XCTAssertEqual(contact.organizationName, "")
        XCTAssertEqual(contact.departmentName, "")
        XCTAssertEqual(contact.jobTitle, "")
        XCTAssertEqual(contact.note, "")
    }

    func testCardWithoutContactFieldsProducesEmptyCollections() {
        let contact = ContactExportMapping.contact(from: BusinessCard(name: "张伟"))

        XCTAssertTrue(contact.phoneNumbers.isEmpty)
        XCTAssertTrue(contact.emailAddresses.isEmpty)
        XCTAssertTrue(contact.urlAddresses.isEmpty)
        XCTAssertTrue(contact.postalAddresses.isEmpty)
    }

    // MARK: - 授权状态判定

    func testAuthorizedStatusProceeds() {
        XCTAssertEqual(ContactExportAccess.decision(for: .authorized), .proceed)
    }

    func testNotDeterminedStatusRequestsAccess() {
        XCTAssertEqual(ContactExportAccess.decision(for: .notDetermined), .requestAccess)
    }

    func testDeniedStatusPromptsForSettings() {
        XCTAssertEqual(ContactExportAccess.decision(for: .denied), .promptForSettings)
    }

    func testRestrictedStatusPromptsForSettings() {
        XCTAssertEqual(ContactExportAccess.decision(for: .restricted), .promptForSettings)
    }

    // MARK: - 导出流程

    func testExportSavesWhenAuthorizedWithoutRequesting() async {
        let exporter = FakeContactExporter(status: .authorized)
        let card = makeCard()

        let notice = await ContactExportCoordinator.export(card, using: exporter)

        XCTAssertEqual(notice, .saved)
        XCTAssertEqual(exporter.requestCount, 0, "已授权时不应再向系统申请")
        XCTAssertEqual(exporter.savedCards.map(\.id), [card.id])
    }

    func testExportRequestsAccessAndSavesWhenGranted() async {
        let exporter = FakeContactExporter(status: .notDetermined, statusAfterRequest: .authorized)

        let notice = await ContactExportCoordinator.export(makeCard(), using: exporter)

        XCTAssertEqual(notice, .saved)
        XCTAssertEqual(exporter.requestCount, 1)
        XCTAssertEqual(exporter.savedCards.count, 1)
    }

    func testExportStopsWhenAlreadyDenied() async {
        let exporter = FakeContactExporter(status: .denied)

        let notice = await ContactExportCoordinator.export(makeCard(), using: exporter)

        XCTAssertEqual(notice, .permissionDenied)
        XCTAssertEqual(exporter.requestCount, 0, "被拒状态下申请不会弹窗，不应浪费一次调用")
        XCTAssertTrue(exporter.savedCards.isEmpty)
    }

    func testExportStopsWhenRequestedAccessIsDenied() async {
        let exporter = FakeContactExporter(status: .notDetermined, statusAfterRequest: .denied)

        let notice = await ContactExportCoordinator.export(makeCard(), using: exporter)

        XCTAssertEqual(notice, .permissionDenied)
        XCTAssertEqual(exporter.requestCount, 1)
        XCTAssertTrue(exporter.savedCards.isEmpty)
    }

    func testExportReportsFailureWhenSavingFails() async {
        let exporter = FakeContactExporter(status: .authorized, saveError: SaveFailure())

        let notice = await ContactExportCoordinator.export(makeCard(), using: exporter)

        XCTAssertEqual(notice, .failed)
    }

    // MARK: - 提示文案

    func testNoticeMessagesAreDistinctAndOnlyPermissionNoticeNeedsSettings() {
        let messages = [ContactExportNotice.saved, .permissionDenied, .failed].map(\.message)

        XCTAssertEqual(Set(messages).count, 3, "三种结果的文案应互不相同")
        XCTAssertTrue(ContactExportNotice.permissionDenied.needsSettings)
        XCTAssertFalse(ContactExportNotice.saved.needsSettings)
        XCTAssertFalse(ContactExportNotice.failed.needsSettings)
    }
}
