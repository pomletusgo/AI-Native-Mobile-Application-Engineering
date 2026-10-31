import XCTest
@testable import CamCardClone

/// `VCardExporter` 单元测试。
///
/// 覆盖 card-library 的 Contact export 需求（T19）：字段一一映射、缺失字段不写占位值、
/// 特殊字符转义、多名片拼接与 CRLF 行分隔符。
final class VCardExporterTests: XCTestCase {

    // MARK: - 结构与姓名

    func testExportStartsWithBeginVCardAndUsesVersion30() {
        let output = VCardExporter.vCard(for: BusinessCard(name: "张伟"))
        XCTAssertTrue(output.hasPrefix("BEGIN:VCARD\r\n"))
        XCTAssertTrue(output.contains("VERSION:3.0\r\n"))
        XCTAssertTrue(output.hasSuffix("END:VCARD\r\n"))
    }

    func testExportWritesNameIntoFNandN() {
        let output = VCardExporter.vCard(for: BusinessCard(name: "张伟"))
        XCTAssertTrue(output.contains("FN:张伟\r\n"))
        XCTAssertTrue(output.contains("N:张伟;;;;\r\n"))
    }

    // MARK: - 电话与邮箱映射

    func testExportIncludesMobileAndEmail() {
        let card = BusinessCard(name: "李娜", mobile: "139-0000-0002", email: "lina@example.com")
        let output = VCardExporter.vCard(for: card)
        XCTAssertTrue(output.contains("TEL;TYPE=CELL:139-0000-0002\r\n"))
        XCTAssertTrue(output.contains("EMAIL;TYPE=INTERNET:lina@example.com\r\n"))
    }

    func testExportMapsPhoneFieldsToOneToOneLines() {
        let card = BusinessCard(name: "A", mobile: "138", phone: "021", fax: "021f")
        let output = VCardExporter.vCard(for: card)
        XCTAssertTrue(output.contains("TEL;TYPE=CELL:138\r\n"))
        XCTAssertTrue(output.contains("TEL;TYPE=VOICE:021\r\n"))
        XCTAssertTrue(output.contains("TEL;TYPE=FAX:021f\r\n"))
    }

    func testExportOmitsFaxWhenMissing() {
        let card = BusinessCard(name: "A", mobile: "138", email: "a@example.com")
        let output = VCardExporter.vCard(for: card)
        XCTAssertFalse(output.contains("TEL;TYPE=FAX:"))
    }

    // MARK: - 网站

    func testExportIncludesWebsite() {
        let card = BusinessCard(name: "A", website: "https://example.com")
        XCTAssertTrue(VCardExporter.vCard(for: card).contains("URL:https://example.com\r\n"))
    }

    func testExportOmitsWebsiteWhenMissing() {
        let output = VCardExporter.vCard(for: BusinessCard(name: "A"))
        XCTAssertFalse(output.contains("URL:"))
    }

    // MARK: - 公司 / 部门 / 职位

    func testExportPrefersCompanyOverDepartmentForORG() {
        let card = BusinessCard(name: "张伟", company: "远景科技", department: "研发部")
        let output = VCardExporter.vCard(for: card)
        XCTAssertTrue(output.contains("ORG:远景科技\r\n"))
        XCTAssertFalse(output.contains("ORG:研发部"))
    }

    func testExportUsesDepartmentWhenCompanyMissing() {
        let card = BusinessCard(name: "朱宏明", department: "计算机系")
        XCTAssertTrue(VCardExporter.vCard(for: card).contains("ORG:计算机系\r\n"))
    }

    // MARK: - 地址（ADR 七分量）

    func testExportMapsAddressAndPostalCodeIntoADR() {
        let card = BusinessCard(name: "李娜", address: "上海市静安区南京西路500号", postalCode: "200041")
        let output = VCardExporter.vCard(for: card)
        XCTAssertTrue(output.contains("ADR;TYPE=WORK:;;上海市静安区南京西路500号;;;200041;\r\n"))
    }

    func testExportOmitsADRWhenAddressAndPostalCodeMissing() {
        let output = VCardExporter.vCard(for: BusinessCard(name: "A"))
        XCTAssertFalse(output.contains("ADR"))
    }

    // MARK: - 标签

    func testExportIncludesCategoriesWhenTagsPresent() {
        let card = BusinessCard(name: "A", tags: ["Customer", "VIP"])
        XCTAssertTrue(VCardExporter.vCard(for: card).contains("CATEGORIES:Customer,VIP\r\n"))
    }

    func testExportOmitsCategoriesWhenNoTags() {
        let output = VCardExporter.vCard(for: BusinessCard(name: "A"))
        XCTAssertFalse(output.contains("CATEGORIES"))
    }

    // MARK: - 空字符串按缺失处理

    func testExportTreatsEmptyStringAsAbsent() {
        let card = BusinessCard(name: "张伟", company: "", website: "", notes: "")
        let output = VCardExporter.vCard(for: card)
        XCTAssertFalse(output.contains("ORG:"))
        XCTAssertFalse(output.contains("URL:"))
        XCTAssertFalse(output.contains("NOTE:"))
    }

    // MARK: - 转义

    func testExportEscapesSpecialCharacters() {
        let card = BusinessCard(name: "Smith;John, Jr.\\Co")
        let output = VCardExporter.vCard(for: card)
        XCTAssertTrue(output.contains("FN:Smith\\;John\\, Jr.\\\\Co\r\n"))
    }

    func testExportEscapesNewlinesInValues() {
        let card = BusinessCard(name: "张伟", notes: "第一行\n第二行")
        let output = VCardExporter.vCard(for: card)
        XCTAssertTrue(output.contains("NOTE:第一行\\n第二行\r\n"))
    }

    // MARK: - 多名片与行分隔符

    func testDocumentConcatenatesMultipleCards() {
        let cards = [BusinessCard(name: "张伟"), BusinessCard(name: "李娜")]
        let output = VCardExporter.document(for: cards)
        XCTAssertEqual(output.components(separatedBy: "BEGIN:VCARD").count - 1, 2)
        XCTAssertEqual(output.components(separatedBy: "END:VCARD").count - 1, 2)
    }

    func testDocumentForEmptyCardsReturnsEmptyString() {
        XCTAssertTrue(VCardExporter.document(for: []).isEmpty)
    }

    func testLineSeparatorIsCRLF() {
        let output = VCardExporter.vCard(for: BusinessCard(name: "张伟", company: "远景科技"))
        XCTAssertTrue(output.contains("\r\n"))

        let withoutCRLF = output.replacingOccurrences(of: "\r\n", with: "")
        XCTAssertFalse(withoutCRLF.contains("\n"), "不应出现裸的 LF 行分隔符")
        XCTAssertFalse(withoutCRLF.contains("\r"), "不应出现裸的 CR 行分隔符")
    }

    // MARK: - 分享用的临时文件（P10）

    func testTemporaryFileURLWritesVCardContent() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VCardExporterTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let card = BusinessCard(name: "张伟", company: "远景科技")

        let url = try VCardExporter.temporaryFileURL(for: card, directory: directory)

        XCTAssertTrue(url.pathExtension == "vcf")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), VCardExporter.vCard(for: card))
    }

    func testFileNameFallsBackWhenNameIsUnusable() {
        XCTAssertEqual(VCardExporter.fileName(for: BusinessCard(name: "张伟")), "张伟.vcf")
        XCTAssertEqual(VCardExporter.fileName(for: BusinessCard(name: "  ")), "contact.vcf")
        XCTAssertEqual(VCardExporter.fileName(for: BusinessCard(name: "a/b:c")), "a-b-c.vcf")
    }
}
