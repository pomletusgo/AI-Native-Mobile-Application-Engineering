import XCTest
@testable import CamCardClone

/// Model 层单元测试。
///
/// 覆盖 spec.md 第 4 节字段规则，以及 T09「缺失字段不得虚构」。
final class BusinessCardModelTests: XCTestCase {

    // MARK: - subtitle（列表副标题）

    func testSubtitleCombinesCompanyAndJobTitle() {
        let card = BusinessCard(name: "张伟", company: "远景科技", jobTitle: "技术总监")
        XCTAssertEqual(card.subtitle, "远景科技 · 技术总监")
    }

    func testSubtitleWithOnlyCompany() {
        let card = BusinessCard(name: "张伟", company: "远景科技")
        XCTAssertEqual(card.subtitle, "远景科技")
    }

    func testSubtitleNilWhenCompanyAndJobTitleMissing() {
        let card = BusinessCard(name: "林俊")
        XCTAssertNil(card.subtitle)
    }

    // MARK: - primaryPhone（首选电话优先级）

    func testPrimaryPhonePrefersMobile() {
        let card = BusinessCard(name: "A", mobile: "138", phone: "021", fax: "021f")
        XCTAssertEqual(card.primaryPhone, "138")
    }

    func testPrimaryPhoneFallsBackToPhoneThenFax() {
        XCTAssertEqual(BusinessCard(name: "A", phone: "021", fax: "021f").primaryPhone, "021")
        XCTAssertEqual(BusinessCard(name: "A", fax: "021f").primaryPhone, "021f")
        XCTAssertNil(BusinessCard(name: "A").primaryPhone)
    }

    // MARK: - 缺失字段不得虚构（T09）

    func testMissingFieldsRemainNil() {
        let card = BusinessCard(name: "David Chen", company: "ABC Technologies")
        XCTAssertNil(card.website)
        XCTAssertNil(card.email)
        XCTAssertNil(card.mobile)
        XCTAssertNil(card.phone)
        XCTAssertNil(card.address)
    }

    func testDefaultTagsIsEmptyArray() {
        let card = BusinessCard(name: "A")
        XCTAssertTrue(card.tags.isEmpty)
    }

    // MARK: - 序列化

    func testCodableRoundTripPreservesAllFields() throws {
        let card = BusinessCard(
            originalImageName: "tc03.jpg",
            processedImageName: "tc03_processed.jpg",
            name: "李娜",
            company: "环宇国际贸易有限公司",
            jobTitle: "市场经理",
            mobile: "139-0000-0002",
            phone: "021-6000-1000",
            fax: nil,
            email: "lina@example.com",
            website: nil,
            address: "上海市静安区南京西路500号",
            tags: ["Conference"],
            notes: "备注内容",
            createdAt: Date(timeIntervalSince1970: 1_730_000_000)
        )

        let data = try JSONEncoder().encode(card)
        let decoded = try JSONDecoder().decode(BusinessCard.self, from: data)

        XCTAssertEqual(decoded, card)
    }

    // MARK: - 搜索文本

    func testSearchableTextContainsAllSearchableFieldsAndIsLowercased() {
        let card = BusinessCard(
            name: "David Chen",
            company: "ABC Technologies",
            jobTitle: "Technical Director",
            email: "David.Chen@Example.com"
        )
        XCTAssertTrue(card.searchableText.contains("david chen"))
        XCTAssertTrue(card.searchableText.contains("abc technologies"))
        XCTAssertTrue(card.searchableText.contains("technical director"))
        XCTAssertTrue(card.searchableText.contains("david.chen@example.com"))
    }
}
