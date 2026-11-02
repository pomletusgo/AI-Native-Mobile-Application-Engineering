import Foundation

/// 名片字段的键。用于抽取结果的下标访问，以及按字段分级统计正确率与误报率。
enum CardFieldKey: String, CaseIterable {
    case name
    case company
    case jobTitle
    case mobile
    case phone
    case fax
    case email
    case website
    case address
    case postalCode
    case department

    /// 中文名，用于错误分析与报告。
    var displayName: String {
        switch self {
        case .name: return "姓名"
        case .company: return "公司"
        case .jobTitle: return "职位"
        case .mobile: return "手机"
        case .phone: return "固话"
        case .fax: return "传真"
        case .email: return "邮箱"
        case .website: return "网站"
        case .address: return "地址"
        case .postalCode: return "邮编"
        case .department: return "部门"
        }
    }
}

/// OCR 原始文本结构化后的名片字段（对应 card-scanner 规格的字段结构化需求）。
///
/// 硬约束：**未在文本中确认的字段一律为 `nil`**，不允许依据语义推测或补全（对应 T09）。
struct ExtractedCardFields: Equatable {

    var name: String?
    var company: String?
    var jobTitle: String?
    var mobile: String?
    var phone: String?
    var fax: String?
    var email: String?
    /// 主邮箱之外的其余邮箱，按出现顺序保留（规格 4.3：其余进入 `notes` 或保留列表）。
    ///
    /// 不属于 `CardFieldKey`，因此不参与评价脚本的逐字段统计，也不改变确认页的字段数。
    var additionalEmails: [String]
    var website: String?
    var address: String?
    var postalCode: String?
    var department: String?

    init(
        name: String? = nil,
        company: String? = nil,
        jobTitle: String? = nil,
        mobile: String? = nil,
        phone: String? = nil,
        fax: String? = nil,
        email: String? = nil,
        additionalEmails: [String] = [],
        website: String? = nil,
        address: String? = nil,
        postalCode: String? = nil,
        department: String? = nil
    ) {
        self.name = name
        self.company = company
        self.jobTitle = jobTitle
        self.mobile = mobile
        self.phone = phone
        self.fax = fax
        self.email = email
        self.additionalEmails = additionalEmails
        self.website = website
        self.address = address
        self.postalCode = postalCode
        self.department = department
    }

    /// 按字段键读写，便于评价脚本逐字段比对。
    subscript(key: CardFieldKey) -> String? {
        get {
            switch key {
            case .name: return name
            case .company: return company
            case .jobTitle: return jobTitle
            case .mobile: return mobile
            case .phone: return phone
            case .fax: return fax
            case .email: return email
            case .website: return website
            case .address: return address
            case .postalCode: return postalCode
            case .department: return department
            }
        }
        set {
            switch key {
            case .name: name = newValue
            case .company: company = newValue
            case .jobTitle: jobTitle = newValue
            case .mobile: mobile = newValue
            case .phone: phone = newValue
            case .fax: fax = newValue
            case .email: email = newValue
            case .website: website = newValue
            case .address: address = newValue
            case .postalCode: postalCode = newValue
            case .department: department = newValue
            }
        }
    }

    /// 所有字段均为空。
    var isEmpty: Bool {
        CardFieldKey.allCases.allSatisfy { self[$0] == nil }
    }
}

extension ExtractedCardFields {

    /// 用抽取结果构造名片。
    ///
    /// 姓名为空或全空白时返回 `nil`；**不用公司名或其它字段顶替姓名**（对应「姓名为空不得保存」）。
    func makeCard(originalImageName: String? = nil, processedImageName: String? = nil) -> BusinessCard? {
        let trimmedName = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        let clean: (String?) -> String? = { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (trimmed?.isEmpty ?? true) ? nil : trimmed
        }
        // 主邮箱之外的其余邮箱写入 `notes` 保留（规格 4.3）；没有额外邮箱时 `notes` 仍为 nil。
        let otherEmails = additionalEmails
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let notes = otherEmails.isEmpty ? nil : "其它邮箱：" + otherEmails.joined(separator: "、")
        return BusinessCard(
            originalImageName: originalImageName,
            processedImageName: processedImageName,
            name: trimmedName,
            company: clean(company),
            jobTitle: clean(jobTitle),
            mobile: clean(mobile),
            phone: clean(phone),
            fax: clean(fax),
            email: clean(email),
            website: clean(website),
            address: clean(address),
            postalCode: clean(postalCode),
            department: clean(department),
            notes: notes
        )
    }
}

/// 把 OCR 原始文本映射为名片字段的规则抽取器。
///
/// 逐段（行内可能有多段）判定，**先命中者先占位，已有值的字段不被覆盖**。判定顺序：
///
/// 1. Email 子串；
/// 2. 网址（必须带 `http(s)://` / `www.` 前缀，或整段就是一个含已知顶级域的域名）；
/// 3. 以首个 `:` 切出的「标签: 值」——标签在词表内则按标签归属，否则标签与值各自再判定；
/// 4. 邮编（整段为 6 位数字）；
/// 5. 电话（整段只由数字与 `+ - ( ) . /` 组成，7–15 位数字；无标签号码按形态或空槽位落位）；
/// 6. 职位（后缀形态 + 通用职务词，段尾整词匹配。**必须排在地址之前**，否则「市场经理」
///    会被弱地址特征「市」抢走）；
/// 7. 地址 / 公司（**特征竞争**：门牌号类数字或行政区划词 → 地址；公司后缀在**段尾** →
///    公司；两者都无证据则不下判，继续下渗）；
/// 8. 部门；
/// 9. 姓名（中文 2–4 个汉字，或 2–4 个首字母大写的西文词）。
///
/// 明确不作推测的边界：
/// - 单个西文单词不判为姓名（`Apple` 既不判姓名也不判公司，避免把产品名塞进姓名字段）；
/// - 没有姓名候选时 `name` 保持 `nil`，不用公司名顶替；
/// - 同一字段出现多个候选（如两个 Email）时只取第一个，其余留给人工校正；
/// - 识别不了的内容直接丢弃，不生成任何推测值。
struct BusinessCardFieldParser {

    // MARK: - 词表

    private static let companySuffixes: [String] = [
        "有限公司", "股份", "集团", "公司", "科技", "研究所", "研究院", "事务所", "工作室",
        "大学", "学院", "学校", "银行", "医院",
        // 行业词：判定顺序里公司排在职位与姓名之前，因此这里刻意不收与职称重叠的字
        // （如「设计师」「网络工程师」里的 `设计` / `网络`），避免把职称误判成机构。
        "贸易", "物流", "教育", "传媒", "广告", "零售", "制造", "文化", "旅游", "医疗",
        "器械", "实业", "投资", "咨询", "医药", "生物", "汽车", "能源", "环保", "置业", "建设",
    ]

    private static let latinCompanySuffixes: [String] = [
        // 刻意不收 "co" / "tech" 这类过短片段：本表按子串匹配，"co" 会命中 `Consulting`、
        // "tech" 会命中 `Technical Director`，把职位误判成公司。
        "inc", "ltd", "llc", "corp", "corporation", "company",
        "technologies", "technology", "solutions", "systems", "software", "robotics", "analytics",
        // "studios" 单列：公司后缀要在段尾命中（D1），而 `studios` 并不以 `studio` 结尾。
        "studio", "studios", "group", "holdings", "university", "college", "school", "institute",
        "laboratory", "labs", "consulting", "partners", "agency", "media",
    ]

    /// 中文职务词（D3）。既用于「整段以职务词结尾」的形态判定，也用于整词命中。
    /// 单字条目（师 / 员 / 长 / 监 / 理 / 士）用来兜住「市场经理」这类没有专门词条的组合，
    /// 但只在整段 ≥ 3 字时才生效，避免把两字人名（如「王理」）判成职务。
    private static let jobTitleKeywords: [String] = [
        "总经理", "副总经理", "副教授", "总监", "经理", "主管", "专员", "代表", "助理", "顾问",
        "总裁", "董事长", "董事", "主任", "合伙人", "创始人", "架构师", "设计师", "工程师",
        "分析师", "规划师", "会计师", "审计师", "教师", "医师", "律师", "技师", "讲师", "教授",
        "研究员", "导演", "编导", "店长", "校长", "院长", "部长", "组长", "队长", "教练",
        "司机", "导游", "师", "员", "长", "监", "理", "士",
    ]

    /// 单字职务后缀：只在整段 ≥ 3 字时才算证据（见 `jobTitleKeywords` 的说明）。
    private static let singleCharacterJobTitleSuffixes: Set<String> = ["师", "员", "长", "监", "理", "士"]

    private static let latinJobTitleKeywords: [String] = [
        "ceo", "cto", "cfo", "coo", "cio", "director", "manager", "engineer", "designer",
        "professor", "doctor", "president", "founder", "consultant", "specialist", "lead",
        "head", "architect", "analyst", "assistant", "officer", "chairman", "partner", "intern",
        // D3 补入的通用西文职务：语料里的 Producer（TC17）、Data Scientist（TC21）等原本漏抽。
        "producer", "scientist", "editor", "chef", "nurse", "writer", "accountant", "lawyer",
        "teacher", "photographer", "technician", "coordinator", "planner",
    ]

    private static let departmentKeywords: [String] = [
        "事业部", "部门", "研发部", "市场部", "销售部", "人事部", "财务部", "技术部", "部", "处", "科", "系",
    ]

    private static let latinDepartmentKeywords: [String] = [
        "department", "dept", "faculty", "division", "school of", "institute of",
    ]

    private static let strongAddressMarkers: [String] = [
        "路", "街", "号", "楼", "室", "层", "巷", "弄", "大厦", "广场", "园区", "工业园", "大道",
    ]

    private static let latinStrongAddressMarkers: [String] = [
        "street", "st.", "road", "rd.", "avenue", "ave.", "boulevard", "lane", "drive",
        "suite", "floor", "fl.", "building", "tower", "plaza",
    ]

    private static let weakAddressMarkers: [String] = ["省", "市", "区", "县", "镇", "乡"]

    private static let latinWeakAddressMarkers: [String] = ["district", "city", "province", "park", "room"]

    /// 标签词表：OCR 文本里「标签: 值」形式的字段标签。
    private static let labels: [String: CardFieldKey] = [
        "姓名": .name, "名字": .name, "name": .name,
        "公司": .company, "单位": .company, "公司名称": .company,
        "company": .company, "organization": .company, "org": .company,
        "职位": .jobTitle, "职务": .jobTitle, "title": .jobTitle, "position": .jobTitle,
        "部门": .department, "department": .department, "dept": .department,
        "地址": .address, "address": .address, "addr": .address,
        "邮编": .postalCode, "邮政编码": .postalCode, "postal": .postalCode, "zip": .postalCode, "zipcode": .postalCode,
        "网站": .website, "网址": .website, "官网": .website,
        "website": .website, "web": .website, "url": .website, "homepage": .website,
        "邮箱": .email, "电子邮箱": .email, "邮件": .email,
        "email": .email, "e-mail": .email, "mail": .email,
        "手机": .mobile, "手机号": .mobile, "移动电话": .mobile,
        "mobile": .mobile, "cell": .mobile, "cellphone": .mobile,
        "电话": .phone, "座机": .phone, "固话": .phone, "联系电话": .phone,
        "tel": .phone, "telephone": .phone, "phone": .phone, "office": .phone,
        "传真": .fax, "fax": .fax,
    ]

    private static let emailPattern = "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"

    private static let knownTopLevelDomains: Set<String> = [
        "com", "cn", "net", "org", "edu", "gov", "io", "me", "ai", "co", "hk", "uk", "jp",
    ]

    /// 电话段允许出现的非数字字符。
    private static let phoneSeparators: Set<Character> = ["+", "-", "(", ")", ".", " ", "/", "·"]

    // MARK: - 入口

    /// 把 OCR 原始文本抽取为名片字段。
    func parse(_ rawText: String) -> ExtractedCardFields {
        var fields = ExtractedCardFields()
        for segment in segments(in: rawText) {
            classify(segment, into: &fields)
        }
        return fields
    }

    // MARK: - 切分

    /// 归一化：全角数字/字母转半角，全角冒号与斜杠转半角，统一换行。
    private func normalized(_ rawText: String) -> String {
        var result = ""
        result.reserveCapacity(rawText.count)
        for scalar in rawText.unicodeScalars {
            switch scalar.value {
            case 0xFF10...0xFF19:
                result.append(Character(UnicodeScalar(scalar.value - 0xFF10 + 0x30)!))
            case 0xFF21...0xFF3A:
                result.append(Character(UnicodeScalar(scalar.value - 0xFF21 + 0x41)!))
            case 0xFF41...0xFF5A:
                result.append(Character(UnicodeScalar(scalar.value - 0xFF41 + 0x61)!))
            case 0xFF1A:
                result.append(":")
            case 0xFF0F:
                result.append("/")
            case 0xFF0E:
                result.append(".")
            case 0x0D:
                continue
            default:
                result.append(Character(scalar))
            }
        }
        return result
    }

    /// 把文本切成待判定的段：先按行，再按 2 个以上空白，再按中英文书写系统边界，最后拆出内嵌的职位词。
    private func segments(in rawText: String) -> [String] {
        var result: [String] = []
        for line in normalized(rawText).split(separator: "\n", omittingEmptySubsequences: true) {
            let spaced = String(line)
                .replacingOccurrences(of: "\\s{2,}", with: "\u{0001}", options: .regularExpression)
            for piece in spaced.split(separator: "\u{0001}") {
                for boundarySplit in splitScriptBoundaries(String(piece)) {
                    for finalPiece in splitEmbeddedJobTitle(boundarySplit) {
                        let trimmed = finalPiece.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            result.append(trimmed)
                        }
                    }
                }
            }
        }
        return result
    }

    /// 在中文字符与西文字母的交界处切开，使「朱宏明 Professor」变成两段。
    private func splitScriptBoundaries(_ text: String) -> [String] {
        var marked = ""
        var previousCategory: ScriptCategory?
        for character in text {
            let category = scriptCategory(of: character)
            if let previous = previousCategory,
               previous != .other, category != .other, previous != category {
                marked.append("\u{0001}")
            }
            if category != .other {
                previousCategory = category
            }
            marked.append(character)
        }
        return marked
            .split(separator: "\u{0001}")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// 拆出与其它词粘在一行的职位词：`Professor Tongji University` → `Professor` + `Tongji University`。
    private func splitEmbeddedJobTitle(_ text: String) -> [String] {
        if text.contains(where: isCJK) {
            return splitCJKJobTitle(text)
        }
        return splitLatinJobTitle(text)
    }

    /// 只在职位词位于**段首**时拆开：`Professor Tongji University` → `Professor` + `Tongji University`。
    ///
    /// 职位词在段尾的多词短语（如 `Technical Lead`）整体保留，交给第 10 步按关键词整段入选，
    /// 否则会把 `Technical` 这半个词丢成无名段。
    private func splitLatinJobTitle(_ text: String) -> [String] {
        let words = text.split(separator: " ").map(String.init)
        guard words.count > 1 else { return [text] }
        let first = words[0].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,:"))
        guard Self.latinJobTitleKeywords.contains(first) else { return [text] }
        let rest = words.dropFirst().joined(separator: " ")
        return rest.isEmpty ? [text] : [words[0], rest]
    }

    /// 只在整段较长（> 6 字）时才拆「前缀 + 职务后缀」。
    ///
    /// 阈值与职位形态判定的 2–6 字窗口对齐：`首席设计师` / `高级合伙人` / `软件工程师` 这类
    /// 「定语 + 职务」本身就是完整职位，整段保留；再长才可能是「职位 + 机构」粘在一行。
    private func splitCJKJobTitle(_ text: String) -> [String] {
        guard text.count > 6 else { return [text] }
        let keywords = Self.jobTitleKeywords.sorted { $0.count > $1.count }
        for keyword in keywords {
            guard let range = text.range(of: keyword), range.upperBound == text.endIndex else { continue }
            let prefix = String(text[text.startIndex..<range.lowerBound])
            if prefix.count >= 2 && prefix.count <= 4 && prefix.allSatisfy(isCJK) {
                return [prefix, keyword]
            }
        }
        return [text]
    }

    // MARK: - 判定

    private func classify(_ segment: String, into fields: inout ExtractedCardFields) {
        // 1. Email 子串
        if let value = substring(in: segment, pattern: Self.emailPattern) {
            assign(.email, value: value, into: &fields)
            return
        }
        // 2. 网址
        if let value = websiteCandidate(in: segment) {
            assign(.website, value: value, into: &fields)
            return
        }
        // 3. 「标签: 值」
        if let colonIndex = segment.firstIndex(of: ":") {
            let label = String(segment[segment.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(segment[segment.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            if let key = Self.labels[label.lowercased()] {
                assign(key, value: value, into: &fields)
                return
            }
            if !label.isEmpty { classifyValue(label, into: &fields) }
            if !value.isEmpty { classifyValue(value, into: &fields) }
            return
        }
        classifyValue(segment, into: &fields)
    }

    /// 无标签内容的判定（第 4–9 步）。
    private func classifyValue(_ text: String, into fields: inout ExtractedCardFields) {
        guard !text.isEmpty else { return }
        if let value = postalCodeCandidate(in: text) {
            assign(.postalCode, value: value, into: &fields)
            return
        }
        if let target = phoneTarget(in: text, fields: fields) {
            assign(target.key, value: target.value, into: &fields)
            return
        }
        // 职位必须排在地址之前：「市场经理」含弱地址特征「市」，先判地址就会把职位抢走。
        if isJobTitleLike(text) {
            assign(.jobTitle, value: text, into: &fields)
            return
        }
        // 地址与公司由「命中顺序」改为「特征竞争」：两者都有证据时按形态裁决；都没有证据时
        // 返回 nil 继续下渗，避免把 `Apple` 这类无后缀的单个西文词塞进地址。
        if let key = addressOrCompanyKey(for: text) {
            assign(key, value: text, into: &fields)
            return
        }
        if containsAny(text, Self.departmentKeywords) || containsAny(text, Self.latinDepartmentKeywords) {
            assign(.department, value: text, into: &fields)
            return
        }
        if let value = nameCandidate(in: text) {
            assign(.name, value: value, into: &fields)
        }
        // 识别不了的段落直接丢弃，不产出推测值。
    }

    // MARK: - 地址 / 公司的特征竞争

    /// 地址与公司特征竞争后的归属；两者都无证据时返回 `nil`，交给后续的部门 / 姓名判定。
    private func addressOrCompanyKey(for text: String) -> CardFieldKey? {
        let addressLike = containsAny(text, Self.strongAddressMarkers)
            || containsAny(text, Self.latinStrongAddressMarkers)
            || hasAdministrativeDivision(text)
        let companyLike = hasCompanySuffixAtTail(text)
        guard addressLike || companyLike else { return nil }
        // 门牌号类数字与行政区划词是比公司后缀更强的地址证据。
        if hasStreetNumberEvidence(text) || hasAdministrativeDivision(text) {
            return .address
        }
        return companyLike ? .company : .address
    }

    /// 段内含门牌号类数字：`\d+号 / \d+楼 / \d+层 / \d+室 / \d+F`，或「数字 + 地址特征词」
    /// （如 `100 Market Street`）。
    private func hasStreetNumberEvidence(_ text: String) -> Bool {
        if text.range(of: "\\d+\\s*(号|楼|层|室|F|f)", options: .regularExpression) != nil {
            return true
        }
        guard text.contains(where: { $0.isNumber }) else { return false }
        return containsAny(text, Self.strongAddressMarkers)
            || containsAny(text, Self.latinStrongAddressMarkers)
    }

    /// 段内含行政区划词（省 / 市 / 区 / 县 / 镇 / 乡，或 District / City…）。
    private func hasAdministrativeDivision(_ text: String) -> Bool {
        containsAny(text, Self.weakAddressMarkers) || containsAny(text, Self.latinWeakAddressMarkers)
    }

    /// 公司后缀出现在**段尾**才算公司证据（`…有限公司` / `…工作室` / `…Studios`）。
    ///
    /// 改成段尾判定，是为了让「张江高科技园区」这类**地址里含行业词**的段不被判成公司：
    /// `科技` 在其中但不在段尾，而地址特征 `园区` 在段尾。
    private func hasCompanySuffixAtTail(_ text: String) -> Bool {
        let lowered = text
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n.,:;、。"))
            .lowercased()
        guard !lowered.isEmpty else { return false }
        if Self.companySuffixes.contains(where: { lowered.hasSuffix($0.lowercased()) }) { return true }
        return Self.latinCompanySuffixes.contains { lowered.hasSuffix($0) }
    }

    // MARK: - 职位判定

    /// 职位判定：形态路（职务后缀）与词表路（通用职务词），都按**段尾整词**匹配。
    private func isJobTitleLike(_ text: String) -> Bool {
        if text.contains(where: isCJK) {
            return isCJKJobTitleLike(text)
        }
        return isLatinJobTitleLike(text)
    }

    /// 中文职位：整段 2–6 个汉字、不含数字与强地址特征，且整词命中词表或以职务后缀结尾。
    private func isCJKJobTitleLike(_ text: String) -> Bool {
        guard text.allSatisfy(isCJK) else { return false }
        guard text.count >= 2 && text.count <= 6 else { return false }
        guard !text.contains(where: { $0.isNumber }) else { return false }
        // 含强地址特征或省 / 区 / 县等行政区划词的是地址，不是职位。这里刻意不含「市」，
        // 否则「市场经理」会被挡掉。
        if containsAny(text, Self.strongAddressMarkers)
            || containsAny(text, ["省", "区", "县", "镇", "乡"]) {
            return false
        }
        if Self.jobTitleKeywords.contains(text) { return true }
        for suffix in Self.jobTitleKeywords where text.count > suffix.count && text.hasSuffix(suffix) {
            // 单字后缀（师 / 员 / 长…）只在整段 ≥ 3 字时才算证据，避免把两字人名判成职位。
            if Self.singleCharacterJobTitleSuffixes.contains(suffix) {
                if text.count >= 3 { return true }
            } else {
                return true
            }
        }
        return false
    }

    /// 西文职位：末词（去尾标点、忽略大小写）命中职务词表才算。
    ///
    /// 按末词整词匹配而不是子串匹配，避免 `Technical` 这类碎片命中。
    private func isLatinJobTitleLike(_ text: String) -> Bool {
        guard let last = text.split(separator: " ").last else { return false }
        let word = last.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,:;"))
        return Self.latinJobTitleKeywords.contains(word)
    }

    // MARK: - 各字段判定

    /// 整段就是一个网址时返回它。
    ///
    /// 带 `http(s)://` / `www.` 前缀的直接认定；没有前缀的必须是**整段就是域名**：
    /// 不含空格、冒号、斜杠，且顶级域在已知表内。这样 `网址:http://a.com`、`a@b.com`
    /// 这类带标签或邮箱的整行不会被当成网址。
    private func websiteCandidate(in segment: String) -> String? {
        guard !segment.contains("@") else { return nil }
        if hasExplicitScheme(segment) {
            return segment.hasSuffix("/") ? String(segment.dropLast()) : segment
        }
        guard !segment.contains(" "), !segment.contains(":"), !segment.contains("/") else { return nil }
        let components = segment.split(separator: ".")
        guard components.count >= 2, let last = components.last,
              Self.knownTopLevelDomains.contains(last.lowercased()) else {
            return nil
        }
        return segment
    }

    private func hasExplicitScheme(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.hasPrefix("http://") || lowered.hasPrefix("https://") || lowered.hasPrefix("www.")
    }

    private func postalCodeCandidate(in segment: String) -> String? {
        let trimmed = segment.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 6, trimmed.allSatisfy({ $0.isNumber }) else { return nil }
        return trimmed
    }

    private func phoneTarget(in segment: String, fields: ExtractedCardFields) -> (key: CardFieldKey, value: String)? {
        if let direct = phoneTargetWithoutLabel(in: segment, fields: fields) {
            return direct
        }
        // 去掉行首的电话标签再试，如「手机13912345678」
        for (label, key) in Self.labels where isPhoneKey(key) {
            guard segment.lowercased().hasPrefix(label) else { continue }
            let rest = String(segment.dropFirst(label.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: " :："))
            if let value = phoneNumberValue(in: rest) {
                return (key, value)
            }
        }
        return nil
    }

    /// 无标签号码的归属：先看形态（`+86` / 首位 `0` / 位数），形态给不出结论时按
    /// 「手机 → 固话 → 传真」的第一个空槽位落位，使同一张卡上的多个无标签号码各占一个槽位。
    private func phoneTargetWithoutLabel(in segment: String, fields: ExtractedCardFields) -> (key: CardFieldKey, value: String)? {
        guard let value = phoneNumberValue(in: segment) else { return nil }
        let compact = value.filter { $0.isNumber || $0 == "+" }
        let digitCount = value.filter { $0.isNumber }.count
        let preferred: CardFieldKey?
        if compact.hasPrefix("+86") && digitCount >= 13 {
            preferred = .mobile
        } else if value.hasPrefix("0") {
            preferred = .phone
        } else if digitCount >= 11 {
            preferred = .mobile
        } else {
            // 形态判不出手机还是固话（如 `+1-555-0923`）：交给空槽位顺序。
            preferred = nil
        }
        if let preferred {
            // 形态给出的槽位已被占用时不改投别的槽位：宁可留空，也不把手机号写进固话。
            return fields[preferred] == nil ? (preferred, value) : nil
        }
        for key in [CardFieldKey.mobile, .phone, .fax] where fields[key] == nil {
            return (key, value)
        }
        return nil
    }

    /// 值必须是「只由数字与电话分隔符组成、7–15 位数字」的号码。
    private func phoneNumberValue(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var digitCount = 0
        for character in trimmed {
            if character.isNumber {
                digitCount += 1
            } else if Self.phoneSeparators.contains(character) {
                continue
            } else {
                return nil
            }
        }
        guard digitCount >= 7 && digitCount <= 15 else { return nil }
        return trimmed
    }

    private func nameCandidate(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: { $0.isNumber }) else { return nil }

        // 中文姓名：2–4 个汉字。
        if trimmed.count >= 2 && trimmed.count <= 4 && trimmed.allSatisfy(isCJK) {
            return trimmed
        }
        // 西文姓名：2–4 个词，每词首字母大写且不含连续大写（排除全大写缩写）。
        let words = trimmed.split(separator: " ").map(String.init)
        guard words.count >= 2 && words.count <= 4 else { return nil }
        for word in words {
            guard let first = word.first, first.isUppercase else { return nil }
            guard !word.dropFirst().contains(where: { $0.isUppercase }) else { return nil }
        }
        return trimmed
    }

    // MARK: - 写入

    private func assign(_ key: CardFieldKey, value: String, into fields: inout ExtractedCardFields) {
        // 邮箱是唯一允许累积的字段：第一个占用 `email`，其余按出现顺序进入 `additionalEmails`
        // （规格 4.3「多 Email：主邮箱入 email，其余进入 notes 或保留列表」）。其余字段仍是先命中先占位。
        if key == .email {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            guard trimmed.range(of: Self.emailPattern, options: .regularExpression) != nil else { return }
            if fields.email == nil {
                fields.email = trimmed
            } else if fields.email != trimmed && !fields.additionalEmails.contains(trimmed) {
                fields.additionalEmails.append(trimmed)
            }
            return
        }

        guard fields[key] == nil else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch key {
        case .mobile, .phone, .fax:
            guard phoneNumberValue(in: trimmed) != nil else { return }
        case .website:
            guard hasExplicitScheme(trimmed) || websiteCandidate(in: trimmed) != nil else { return }
        case .postalCode:
            guard trimmed.contains(where: { $0.isNumber }) else { return }
        default:
            break
        }
        fields[key] = trimmed
    }

    // MARK: - 小工具

    private func substring(in text: String, pattern: String) -> String? {
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[range])
    }

    private func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        let lowered = text.lowercased()
        return keywords.contains { lowered.contains($0.lowercased()) }
    }

    private func isPhoneKey(_ key: CardFieldKey) -> Bool {
        key == .mobile || key == .phone || key == .fax
    }

    private func isCJK(_ character: Character) -> Bool {
        scriptCategory(of: character) == .cjk
    }

    private func scriptCategory(of character: Character) -> ScriptCategory {
        let scalars = character.unicodeScalars
        guard scalars.count == 1, let scalar = scalars.first else { return .other }
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x3000...0x303F:
            return .cjk
        case 0x41...0x5A, 0x61...0x7A:
            return .latin
        default:
            return .other
        }
    }

    private enum ScriptCategory {
        case cjk
        case latin
        case other
    }
}
