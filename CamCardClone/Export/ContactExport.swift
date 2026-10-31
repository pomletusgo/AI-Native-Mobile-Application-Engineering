import Contacts
import Foundation

/// 名片到系统联系人条目的字段映射（P10 / T19）。
///
/// 与 `VCardExporter` 保持同一约定：名片上不存在的字段**绝不写入占位值**，
/// 不存在即留空（系统联系人条目里就是空串，而不是「无」之类的假值）。
///
/// 映射与写入分开：`contact(from:)` 是纯函数，因此「导出后联系人是哪样」
/// 可以在没有权限弹窗、没有真机的环境里断言。
///
/// 已知取舍：标签（`BusinessCard.tags`）在系统联系人里没有对应字段，
/// 因此不写入联系人条目，只出现在 VCF 的 `CATEGORIES` 行。
enum ContactExportMapping {

    /// 把一张名片映射为待写入的系统联系人。
    static func contact(from card: BusinessCard) -> CNMutableContact {
        let contact = CNMutableContact()
        contact.givenName = card.name

        // 公司优先；公司为空但有部门时，机构名退化为部门（与 vCard 的 ORG 行一致）。
        contact.organizationName = nonEmpty(card.company) ?? nonEmpty(card.department) ?? ""
        contact.departmentName = nonEmpty(card.department) ?? ""
        contact.jobTitle = nonEmpty(card.jobTitle) ?? ""

        contact.phoneNumbers = phoneEntries(for: card)
        contact.emailAddresses = emailEntries(for: card)

        if let website = nonEmpty(card.website) {
            contact.urlAddresses = [CNLabeledValue(label: CNLabelURLAddressHomePage, value: website as NSString)]
        }

        if let address = postalAddress(for: card) {
            contact.postalAddresses = [address]
        }

        contact.note = nonEmpty(card.notes) ?? ""

        return contact
    }

    // MARK: - 分字段映射

    /// 电话：手机 / 固话 / 传真分别映射，缺失即不产出条目（顺序与 vCard 一致）。
    private static func phoneEntries(for card: BusinessCard) -> [CNLabeledValue<CNPhoneNumber>] {
        var entries: [CNLabeledValue<CNPhoneNumber>] = []
        if let mobile = nonEmpty(card.mobile) {
            entries.append(CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: mobile)))
        }
        if let phone = nonEmpty(card.phone) {
            entries.append(CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: phone)))
        }
        if let fax = nonEmpty(card.fax) {
            entries.append(CNLabeledValue(label: CNLabelFax, value: CNPhoneNumber(stringValue: fax)))
        }
        return entries
    }

    /// 邮箱：缺失即不产出条目。
    private static func emailEntries(for card: BusinessCard) -> [CNLabeledValue<NSString>] {
        guard let email = nonEmpty(card.email) else { return [] }
        return [CNLabeledValue(label: CNLabelWork, value: email as NSString)]
    }

    /// 地址：原文整段放入街道，邮编单独放入邮编；两者都缺失时不产出条目。
    private static func postalAddress(for card: BusinessCard) -> CNLabeledValue<CNPostalAddress>? {
        let street = nonEmpty(card.address)
        let postalCode = nonEmpty(card.postalCode)
        guard street != nil || postalCode != nil else { return nil }

        let address = CNMutablePostalAddress()
        address.street = street ?? ""
        address.postalCode = postalCode ?? ""
        return CNLabeledValue(label: CNLabelWork, value: address as CNPostalAddress)
    }

    /// 把可选字符串归一化为「有值」或 `nil`；`nil` 与空字符串都视为缺失。
    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value, !value.isEmpty else { return nil }
        return value
    }
}

/// 写入系统联系人前对授权状态的判断结果。
enum ContactExportAccessDecision: Equatable {
    /// 已授权，可以直接写入。
    case proceed
    /// 尚未询问，需要先向系统申请。
    case requestAccess
    /// 被拒或受限，只能提示用户去系统设置；本次不写入。
    case promptForSettings
}

/// 授权状态到「能否写入」的映射（纯函数）。
enum ContactExportAccess {

    /// 注意这里用 `default` 而不是 `@unknown default`：iOS 18 给
    /// `CNAuthorizationStatus` 新增了 `.limited`（仅选中联系人），
    /// 用 `default` 兜底可以让这份代码在 iOS 17 与 iOS 18 两套 SDK 下都能编译，
    /// 且新状态一律按「未完全授权」处理是安全的一侧。
    static func decision(for status: CNAuthorizationStatus) -> ContactExportAccessDecision {
        switch status {
        case .authorized:
            return .proceed
        case .notDetermined:
            return .requestAccess
        default:
            return .promptForSettings
        }
    }
}

/// 一次导出的结果，同时也是给用户的提示文案。
///
/// 文案集中在导出模块，界面只负责展示，避免同一句话在多处各写一遍。
enum ContactExportNotice: Equatable {
    /// 已写入系统联系人。
    case saved
    /// 用户未授权（或被拒 / 受限），本次没有写入。
    case permissionDenied
    /// 已授权但写入失败（例如通讯录不可写）。
    case failed

    var message: String {
        switch self {
        case .saved:
            return "已保存到系统联系人。"
        case .permissionDenied:
            return "未获得通讯录权限，请在「设置」中允许访问后重试。"
        case .failed:
            return "保存到系统联系人失败，请稍后重试。"
        }
    }

    /// 是否应引导用户去系统设置（只有「未授权」这一种情况值得跳转设置）。
    var needsSettings: Bool {
        self == .permissionDenied
    }
}

/// 写入系统联系人。抽成协议是为了让「申请 → 被拒」「写入失败」这些分支
/// 能脱离系统权限弹窗单测；真实实现见 `SystemContactExporter`。
protocol ContactExporting: AnyObject {
    /// 当前授权状态。只查询，不触发系统弹窗。
    func authorizationStatus() -> CNAuthorizationStatus
    /// 申请授权。只有状态为「未决」时系统才会弹窗。
    func requestAccess() async -> CNAuthorizationStatus
    /// 把名片作为一条新联系人写入系统联系人。
    func save(_ card: BusinessCard) throws
}

/// 真实实现：Contacts 框架。
final class SystemContactExporter: ContactExporting {

    private let store: CNContactStore

    init(store: CNContactStore = CNContactStore()) {
        self.store = store
    }

    func authorizationStatus() -> CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    func requestAccess() async -> CNAuthorizationStatus {
        _ = try? await store.requestAccess(for: .contacts)
        // 申请后重新查询，而不是用返回值推断。
        return authorizationStatus()
    }

    func save(_ card: BusinessCard) throws {
        let request = CNSaveRequest()
        request.add(ContactExportMapping.contact(from: card), toContainerWithIdentifier: nil)
        try store.execute(request)
    }
}

/// 按授权状态决定是否写入，并在需要时先向系统申请。
///
/// 把「查询 → 判断 → 按需申请 → 再判断 → 写入」这段顺序逻辑收成一个纯函数式的入口：
/// 输入输出都是 `ContactExportNotice`，不涉及任何 UI。
enum ContactExportCoordinator {

    /// 导出名片到系统联系人。
    ///
    /// 返回 `.permissionDenied` 时调用方应提示用户去系统设置开启通讯录权限；
    /// 只有返回 `.saved` 才算真正写入成功。
    static func export(_ card: BusinessCard, using exporter: ContactExporting) async -> ContactExportNotice {
        switch ContactExportAccess.decision(for: exporter.authorizationStatus()) {
        case .promptForSettings:
            return .permissionDenied
        case .requestAccess:
            switch ContactExportAccess.decision(for: await exporter.requestAccess()) {
            case .proceed:
                break
            case .requestAccess, .promptForSettings:
                return .permissionDenied
            }
        case .proceed:
            break
        }

        do {
            try exporter.save(card)
            return .saved
        } catch {
            return .failed
        }
    }
}
