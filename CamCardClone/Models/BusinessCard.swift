import Foundation

/// 名片记录（对应 docs/规格说明书.md 第 4 节 BusinessCard Schema）。
///
/// 字段规则：
/// - `name` 为唯一必填字段，空姓名不允许保存。
/// - 其余字段缺失时必须为 `nil`，**不得凭空补全**（对应 T09 规格）。
struct BusinessCard: Identifiable, Codable, Equatable, Hashable {

    // MARK: - 身份

    let id: UUID

    // MARK: - 图像

    /// 原始名片图像标识（Week3 接入实际文件后写入）。
    var originalImageName: String?
    /// 校正/裁剪后的图像标识。
    var processedImageName: String?

    // MARK: - 结构化字段

    /// 姓名（必填）。
    var name: String
    var company: String?
    var jobTitle: String?
    var mobile: String?
    var phone: String?
    var fax: String?
    var email: String?
    var website: String?
    var address: String?
    /// 邮编（可选）。
    var postalCode: String?
    /// 部门（可选）。
    var department: String?

    // MARK: - 管理与元数据

    var tags: [String]
    var notes: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        originalImageName: String? = nil,
        processedImageName: String? = nil,
        name: String,
        company: String? = nil,
        jobTitle: String? = nil,
        mobile: String? = nil,
        phone: String? = nil,
        fax: String? = nil,
        email: String? = nil,
        website: String? = nil,
        address: String? = nil,
        tags: [String] = [],
        notes: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.originalImageName = originalImageName
        self.processedImageName = processedImageName
        self.name = name
        self.company = company
        self.jobTitle = jobTitle
        self.mobile = mobile
        self.phone = phone
        self.fax = fax
        self.email = email
        self.website = website
        self.address = address
        self.postalCode = postalCode
        self.department = department
        self.tags = tags
        self.notes = notes
        self.createdAt = createdAt
    }
}

// MARK: - 派生属性（面向 UI 与检索，不参与持久化）

extension BusinessCard {

    /// 列表行副标题：`公司 · 职位`，两者皆空时返回 `nil`。
    var subtitle: String? {
        let parts = [company, jobTitle]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 首选联系电话，优先级：手机 > 固话 > 传真。
    var primaryPhone: String? {
        [mobile, phone, fax].compactMap { $0 }.first { !$0.isEmpty }
    }

    /// 是否存在可点击的外部动作（电话 / 邮箱 / 网站）。
    var hasContactActions: Bool {
        primaryPhone != nil || !(email ?? "").isEmpty || !(website ?? "").isEmpty
    }

    /// 用于搜索的小写文本（姓名 / 公司 / 职位 / 电话 / 邮箱等）。
    var searchableText: String {
        [name, company, jobTitle, mobile, phone, fax, email, website, address]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
    }
}
