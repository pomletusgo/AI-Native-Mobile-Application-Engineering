import XCTest
@testable import CamCardClone

/// `BusinessCardFieldParser` 单元测试。
///
/// 覆盖 card-scanner 的 Structured field extraction 需求（T08–T10）：核心字段分类、公司名不得
/// 当成姓名、缺失字段不虚构、多个电话号码分别归位、中英混排不翻译，以及任务书 4.3 要求处理的
/// 五类歧义（字段歧义 / 人名与公司混淆 / 多电话归属 / 中英混排 / 同字段多候选）。
///
/// 这里的 OCR 原始文本都是手写 fixture，只用来验证规则本身；对 `testcards/ground_truth.json`
/// 那 30 张卡片的字段级准确率统计见 `FieldExtractionEvaluatorTests`（等 Week 3 产出 OCR 原文后执行）。
final class BusinessCardFieldParserTests: XCTestCase {

    private let parser = BusinessCardFieldParser()

    // MARK: - Fixtures（手写 OCR 原始文本）

    private static let chineseStandardCard = """
        上海远景科技有限公司
        张伟
        技术总监
        手机: 138-0000-0001
        邮箱: zhangwei@example.com
        地址: 上海市浦东新区世纪大道100号
        """

    private static let englishStandardCard = """
        David Chen
        ABC Technologies
        Technical Director
        +1-555-0100
        david.chen@example.com
        www.example.com
        """

    private static let multiplePhoneCard = """
        刘洋
        中远物流有限公司
        销售部
        手机: 139-0000-0005
        电话: 021-6000-3000
        传真: 021-6000-3001
        liuyang@example.com
        """

    /// 字段歧义：`Apple` 既是品牌也可能是产品名，整段只有一个西文单词。
    private static let ambiguousBrandCard = """
        徐磊
        Apple
        技术总监
        手机: 138-0000-0028
        xulei@example.com
        """

    /// 人名与公司混淆：`Jordan Lee` / `Lee Consulting`。
    private static let personVersusCompanyCard = """
        Jordan Lee
        Lee Consulting
        Technical Lead
        jordan@leeconsulting.example.com
        """

    /// 中英混排在同一行，且职位词在段首。
    private static let bilingualSingleLineCard = """
        朱宏明 Professor Tongji University
        zhuhongming@example.edu.cn
        """

    /// 只有公司没有姓名，电话与公司名都不是人名。
    private static let companyOnlyCard = """
        星辉传媒
        021-6000-5000
        """

    /// 同字段多个候选：两个邮箱、两个手机号。
    private static let duplicatedFieldCard = """
        李娜
        环宇国际贸易有限公司
        lina@example.com
        lina.backup@example.com
        手机: 139-0000-0002
        139-0000-0003
        """

    /// 全角冒号与「标签: 值」混排。
    private static let fullWidthLabelCard = """
        公司：环宇国际贸易有限公司
        姓名：李娜
        电话：021-6000-1000
        邮编：200040
        """

    /// 无法识别的内容（版式说明与标语）。
    private static let unrecognizableCard = """
        （正面）
        千里之行 始于足下
        """

    // MARK: - 核心字段分类（T08）

    func testParsesChineseStandardCard() {
        let fields = parser.parse(Self.chineseStandardCard)

        XCTAssertEqual(fields.name, "张伟")
        XCTAssertEqual(fields.company, "上海远景科技有限公司")
        XCTAssertEqual(fields.jobTitle, "技术总监")
        XCTAssertEqual(fields.mobile, "138-0000-0001")
        XCTAssertEqual(fields.email, "zhangwei@example.com")
        XCTAssertEqual(fields.address, "上海市浦东新区世纪大道100号")
        XCTAssertNil(fields.phone)
        XCTAssertNil(fields.fax)
        XCTAssertNil(fields.website)
        XCTAssertNil(fields.postalCode)
        XCTAssertNil(fields.department)
    }

    func testParsesEnglishStandardCard() {
        let fields = parser.parse(Self.englishStandardCard)

        XCTAssertEqual(fields.name, "David Chen")
        XCTAssertEqual(fields.company, "ABC Technologies")
        XCTAssertEqual(fields.jobTitle, "Technical Director")
        XCTAssertEqual(fields.mobile, "+1-555-0100")
        XCTAssertEqual(fields.email, "david.chen@example.com")
        XCTAssertEqual(fields.website, "www.example.com")
        XCTAssertNil(fields.phone)
        XCTAssertNil(fields.fax)
        XCTAssertNil(fields.address)
    }

    // MARK: - 缺失字段不得虚构（T09）

    func testMissingWebsiteIsNotInvented() {
        let fields = parser.parse(Self.chineseStandardCard)

        XCTAssertNil(fields.website, "名片上没有网站字段时不得生成任何网址")
    }

    func testUnrecognizableSegmentsAreDiscarded() {
        let fields = parser.parse(Self.unrecognizableCard)

        XCTAssertTrue(fields.isEmpty, "版式说明与标语不得被塞进任何字段")
        XCTAssertNil(fields.makeCard())
    }

    func testEmptyTextYieldsEmptyFields() {
        XCTAssertTrue(parser.parse("").isEmpty)
        XCTAssertTrue(parser.parse("\n\n   \n").isEmpty)
    }

    // MARK: - 多个电话号码分别归位（T10）

    func testSplitsMultiplePhoneNumbersIntoMobilePhoneAndFax() {
        let fields = parser.parse(Self.multiplePhoneCard)

        XCTAssertEqual(fields.mobile, "139-0000-0005")
        XCTAssertEqual(fields.phone, "021-6000-3000")
        XCTAssertEqual(fields.fax, "021-6000-3001")
        XCTAssertEqual(fields.department, "销售部")
        XCTAssertEqual(fields.company, "中远物流有限公司")
    }

    func testUntypedPhoneLineStartingWithZeroBecomesLandline() {
        let fields = parser.parse("021-6598-1000")

        XCTAssertEqual(fields.phone, "021-6598-1000")
        XCTAssertNil(fields.mobile)
    }

    // MARK: - 公司名不得当姓名

    func testCompanyOnlyCardHasNoNameAndCannotBecomeCard() {
        let fields = parser.parse(Self.companyOnlyCard)

        XCTAssertNil(fields.name, "没有姓名候选时不得用公司名顶替")
        XCTAssertEqual(fields.company, "星辉传媒")
        XCTAssertEqual(fields.phone, "021-6000-5000")
        XCTAssertNil(fields.makeCard(), "姓名为空时不得保存名片")
    }

    func testPersonVersusCompanyAmbiguity() {
        let fields = parser.parse(Self.personVersusCompanyCard)

        XCTAssertEqual(fields.name, "Jordan Lee")
        XCTAssertEqual(fields.company, "Lee Consulting")
        XCTAssertEqual(fields.jobTitle, "Technical Lead")
        XCTAssertEqual(fields.email, "jordan@leeconsulting.example.com")
    }

    func testSingleLatinWordIsNeitherNameNorCompany() {
        let fields = parser.parse(Self.ambiguousBrandCard)

        XCTAssertEqual(fields.name, "徐磊")
        XCTAssertNil(fields.company, "单个西文单词不判为机构，宁可留空交人工校正")
        XCTAssertEqual(fields.jobTitle, "技术总监")
        XCTAssertNil(fields.website, "`Apple` 不是网址")
    }

    // MARK: - 中英混排

    func testBilingualLineIsSplitIntoNameJobTitleAndCompany() {
        let fields = parser.parse(Self.bilingualSingleLineCard)

        XCTAssertEqual(fields.name, "朱宏明")
        XCTAssertEqual(fields.jobTitle, "Professor")
        XCTAssertEqual(fields.company, "Tongji University")
        XCTAssertEqual(fields.email, "zhuhongming@example.edu.cn")
    }

    func testBilingualNameKeepsOriginalLanguage() {
        let fields = parser.parse(Self.bilingualSingleLineCard)

        XCTAssertEqual(fields.name, "朱宏明", "姓名保持名片上原有的语言，不做翻译或音译")
    }

    // MARK: - 同字段多候选

    func testOnlyFirstCandidatePerFieldIsKept() {
        let fields = parser.parse(Self.duplicatedFieldCard)

        XCTAssertEqual(fields.email, "lina@example.com")
        XCTAssertEqual(fields.mobile, "139-0000-0002")
        XCTAssertEqual(fields.name, "李娜")
        XCTAssertEqual(fields.additionalEmails, ["lina.backup@example.com"],
                       "主邮箱之外的其余邮箱按出现顺序保留，不丢弃（规格 4.3 多 Email）")
    }

    func testDuplicateEmailIsNotCollectedTwice() {
        let fields = parser.parse("李娜\nlina@example.com\nlina@example.com\nlina.backup@example.com")

        XCTAssertEqual(fields.email, "lina@example.com")
        XCTAssertEqual(fields.additionalEmails, ["lina.backup@example.com"], "与主邮箱重复的候选不重复收集")
    }

    func testAdditionalEmailsAreWrittenIntoNotes() {
        let fields = parser.parse(Self.duplicatedFieldCard)
        let card = fields.makeCard()

        XCTAssertEqual(card?.email, "lina@example.com")
        XCTAssertEqual(card?.notes, "其它邮箱：lina.backup@example.com", "其余邮箱写入 notes 保留")
    }

    func testSingleEmailCardKeepsNotesEmpty() {
        let fields = parser.parse(Self.chineseStandardCard)

        XCTAssertTrue(fields.additionalEmails.isEmpty)
        XCTAssertNil(fields.makeCard()?.notes, "只有一个邮箱时 notes 仍为 nil，不凭空造字段")
    }

    // MARK: - 归一化与标签

    func testFullWidthColonIsNormalized() {
        let fields = parser.parse("姓名：李娜\n公司：环宇国际贸易有限公司")

        XCTAssertEqual(fields.name, "李娜")
        XCTAssertEqual(fields.company, "环宇国际贸易有限公司")
    }

    func testFullWidthLabelCardIsClassifiedByLabel() {
        let fields = parser.parse(Self.fullWidthLabelCard)

        XCTAssertEqual(fields.company, "环宇国际贸易有限公司")
        XCTAssertEqual(fields.name, "李娜")
        XCTAssertEqual(fields.phone, "021-6000-1000")
        XCTAssertEqual(fields.postalCode, "200040")
    }

    func testLabeledWebsiteLineIsNotTreatedAsUrl() {
        let fields = parser.parse("网址:http://www.example.com")

        XCTAssertEqual(fields.website, "http://www.example.com")
    }

    // MARK: - 结果类型

    func testSubscriptReadsAndWritesFields() {
        var fields = ExtractedCardFields()

        XCTAssertTrue(fields.isEmpty)
        fields[.name] = "李娜"
        fields[.company] = "环宇国际贸易有限公司"

        XCTAssertEqual(fields.name, "李娜")
        XCTAssertEqual(fields[.name], "李娜")
        XCTAssertEqual(fields[.company], "环宇国际贸易有限公司")
        XCTAssertNil(fields[.fax])
        XCTAssertFalse(fields.isEmpty)
        XCTAssertEqual(CardFieldKey.allCases.count, 11)
    }

    func testMakeCardTrimsValuesAndDropsBlankFields() {
        let fields = ExtractedCardFields(name: "  李娜  ", company: "   ", fax: "")

        let card = fields.makeCard(originalImageName: "raw.jpg", processedImageName: "crop.jpg")

        XCTAssertEqual(card?.name, "李娜")
        XCTAssertEqual(card?.originalImageName, "raw.jpg")
        XCTAssertEqual(card?.processedImageName, "crop.jpg")
        XCTAssertNil(card?.company)
        XCTAssertNil(card?.fax)
    }

    func testMakeCardCarriesEveryExtractedField() {
        let fields = parser.parse(Self.multiplePhoneCard)

        let card = try? XCTUnwrap(fields.makeCard())

        XCTAssertEqual(card?.mobile, "139-0000-0005")
        XCTAssertEqual(card?.phone, "021-6000-3000")
        XCTAssertEqual(card?.fax, "021-6000-3001")
        XCTAssertEqual(card?.email, "liuyang@example.com")
        XCTAssertEqual(card?.company, "中远物流有限公司")
        XCTAssertEqual(card?.department, "销售部")
    }

    // MARK: - D1 公司 / 地址特征竞争（fix-field-classification-errors）

    func testCompanyNameWithSingleCharacterAddressMarkerIsNotStolen() {
        // `工作室` 整词命中公司后缀；若仍按子串判地址，`室` 会把公司名抢成地址。
        let fields = parser.parse("蓝海设计工作室")

        XCTAssertEqual(fields.company, "蓝海设计工作室")
        XCTAssertNil(fields.address)
    }

    func testAddressWithIndustryKeywordIsNotStolenByCompanySuffix() {
        // `科技` 在段中而非段尾，地址特征 `园区` 在段尾 → 地址。
        let fields = parser.parse("张江高科技园区")

        XCTAssertEqual(fields.address, "张江高科技园区")
        XCTAssertNil(fields.company)
    }

    func testLatinAddressMarkerInMiddleDoesNotBeatTailCompanySuffix() {
        // `Tower` 是地址特征但在段中；公司后缀 `Consulting` 在段尾 → 公司。
        let fields = parser.parse("Tower Consulting")

        XCTAssertEqual(fields.company, "Tower Consulting")
        XCTAssertNil(fields.address)
    }

    func testStreetNumberEvidenceBeatsCompanySuffix() {
        // 门牌号类数字是比公司后缀更强的地址证据。
        let fields = parser.parse("100 Tower Studios")

        XCTAssertEqual(fields.address, "100 Tower Studios")
        XCTAssertNil(fields.company)
    }

    func testAmbiguousWordWithoutEvidenceIsNotForcedIntoAddress() {
        let fields = parser.parse("Nebula")

        XCTAssertNil(fields.address, "既无地址也无公司证据的西文单词不下判，不默认塞进地址")
        XCTAssertNil(fields.company)
        XCTAssertTrue(fields.isEmpty)
    }

    // MARK: - D2 无标签号码（fix-field-classification-errors）

    func testUnlabeledInternationalNumberFillsFirstEmptySlot() {
        let fields = parser.parse("+1-555-0307")

        XCTAssertEqual(fields.mobile, "+1-555-0307", "形态分不出手机与固话时落首个空槽位")
        XCTAssertNil(fields.phone)
        XCTAssertNil(fields.fax)
    }

    func testUnlabeledElevenDigitNumberBecomesMobile() {
        let fields = parser.parse("13800000001")

        XCTAssertEqual(fields.mobile, "13800000001")
        XCTAssertNil(fields.phone)
    }

    func testSeveralUnlabeledNumbersFillDistinctSlots() {
        let fields = parser.parse("+1-555-0923\n+1-555-0924\n+1-555-0925")

        XCTAssertEqual(fields.mobile, "+1-555-0923")
        XCTAssertEqual(fields.phone, "+1-555-0924")
        XCTAssertEqual(fields.fax, "+1-555-0925")
    }

    func testShapePreferredSlotAlreadyTakenIsDropped() {
        let fields = parser.parse("13800000001\n13800000002")

        XCTAssertEqual(fields.mobile, "13800000001")
        XCTAssertNil(fields.phone, "形态判为手机但手机已占用时不改投固话，宁可留空")
        XCTAssertNil(fields.fax)
    }

    func testPhoneLabelTakesPrecedenceOverShape() {
        let fields = parser.parse("传真: 139-0000-0002")

        XCTAssertEqual(fields.fax, "139-0000-0002", "标签优先于号码形态")
        XCTAssertNil(fields.mobile)
        XCTAssertNil(fields.phone)
    }

    // MARK: - D3 职位判定（fix-field-classification-errors）

    func testJobTitleOutsideClosedListIsRecognized() {
        let fields = parser.parse("摄影师")

        XCTAssertEqual(fields.jobTitle, "摄影师", "词表外但以职务后缀结尾的整段应判为职位")
    }

    func testJobTitleSuffixOnlyNeedsThreeCharacters() {
        let fields = parser.parse("调度员")

        XCTAssertEqual(fields.jobTitle, "调度员")
    }

    func testSloganIsNotTreatedAsJobTitle() {
        let fields = parser.parse("张伟\n专业可靠")

        XCTAssertEqual(fields.name, "张伟")
        XCTAssertNil(fields.jobTitle, "标语既不命中词表也不以后缀结尾，不得判为职位")
    }

    func testJobTitleAndCompanyOnSameLineAreSeparated() {
        let fields = parser.parse("王强\n首席设计师  蓝海设计工作室")

        XCTAssertEqual(fields.name, "王强")
        XCTAssertEqual(fields.jobTitle, "首席设计师")
        XCTAssertEqual(fields.company, "蓝海设计工作室")
    }

    func testLatinWordFragmentIsNotTreatedAsJobTitle() {
        let fields = parser.parse("徐磊\nTechnical")

        XCTAssertEqual(fields.name, "徐磊")
        XCTAssertNil(fields.jobTitle, "`Technical` 只是碎片，末词不命中词表不得判职位")
    }

    // MARK: - D4 语料外构造样例（防过拟合）

    func testUnseenChineseJobTitlesGeneralize() {
        for title in ["摄影师", "调酒师", "咖啡师", "测绘员", "售票员", "快递员"] {
            XCTAssertEqual(parser.parse(title).jobTitle, title, "\(title) 应可由职务后缀外推")
        }
    }

    func testUnseenLatinJobTitlesGeneralize() {
        for title in ["Chief Technology Officer", "Cybersecurity Analyst", "Product Designer"] {
            XCTAssertEqual(parser.parse(title).jobTitle, title, "\(title) 应可由末词整词匹配外推")
        }
    }

    func testUnseenInternationalNumberFillsFirstEmptySlot() {
        let fields = parser.parse("+44-20-7946-0958")

        XCTAssertEqual(fields.mobile, "+44-20-7946-0958", "语料外的国际号码应按空槽位落位")
        XCTAssertNil(fields.phone)
    }

    func testUnseenAddressAndCompanyCompetitionGeneralizes() {
        let address = parser.parse("上海市徐汇区漕溪北路88号")
        XCTAssertEqual(address.address, "上海市徐汇区漕溪北路88号")
        XCTAssertNil(address.company)

        let company = parser.parse("远见医疗科技有限公司")
        XCTAssertEqual(company.company, "远见医疗科技有限公司")
        XCTAssertNil(company.address)
    }
}
