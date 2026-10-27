import Foundation

/// 名片到 vCard 3.0 文本的导出器（Week5，对应 card-library 规格的 Contact export 需求与 T19）。
///
/// 约定：
/// - 输出为 vCard 3.0（`VERSION:3.0`），行分隔符固定为 `\r\n`，每个字段行均以 `\r\n` 结尾。
/// - 字段映射一一对应：名片上不存在的字段**绝不输出占位值**；空字符串等同于字段不存在。
/// - 值按 RFC 2426 转义：`\` → `\\`、`;` → `\;`、`,` → `\,`、换行 → `\n`。
///
/// 已知限制：本实现**不做 75 字节长行折行**（line folding）。名片字段通常较短，若后续需要与
/// 严格的 vCard 解析器互通，应在此处补上折行处理。
enum VCardExporter {

    /// 导出一张名片为单个 vCard 块（以 `\r\n` 结尾）。
    static func vCard(for card: BusinessCard) -> String {
        var lines: [String] = ["BEGIN:VCARD", "VERSION:3.0"]

        // 姓名：FN 为必填展示名，N 与 FN 同源，整名放在第一个分量（Family Name）位置。
        let name = escape(card.name)
        lines.append("FN:\(name)")
        lines.append("N:\(name);;;;")

        // 公司 / 部门：优先公司；公司为空但有部门时退化为部门。
        if let company = nonEmpty(card.company) {
            lines.append("ORG:\(escape(company))")
        } else if let department = nonEmpty(card.department) {
            lines.append("ORG:\(escape(department))")
        }

        // 职位。
        if let jobTitle = nonEmpty(card.jobTitle) {
            lines.append("TITLE:\(escape(jobTitle))")
        }

        // 电话：手机 / 固话 / 传真分别映射，缺失即不输出。
        if let mobile = nonEmpty(card.mobile) {
            lines.append("TEL;TYPE=CELL:\(escape(mobile))")
        }
        if let phone = nonEmpty(card.phone) {
            lines.append("TEL;TYPE=VOICE:\(escape(phone))")
        }
        if let fax = nonEmpty(card.fax) {
            lines.append("TEL;TYPE=FAX:\(escape(fax))")
        }

        // 邮箱 / 网站。
        if let email = nonEmpty(card.email) {
            lines.append("EMAIL;TYPE=INTERNET:\(escape(email))")
        }
        if let website = nonEmpty(card.website) {
            lines.append("URL:\(escape(website))")
        }

        // 地址：ADR 有 7 个分量（PO Box;Ext;Street;Locality;Region;PostalCode;Country）。
        // 地址原文整段放入 Street（第 3 分量），邮编放入第 6 分量，其余分量留空。
        // 地址与邮编都为空时不输出 ADR 行。
        let street = nonEmpty(card.address)
        let postalCode = nonEmpty(card.postalCode)
        if street != nil || postalCode != nil {
            let components = [
                "",                                   // PO Box
                "",                                   // Ext
                street.map(escape) ?? "",             // Street
                "",                                   // Locality
                "",                                   // Region
                postalCode.map(escape) ?? "",         // PostalCode
                ""                                    // Country
            ]
            lines.append("ADR;TYPE=WORK:" + components.joined(separator: ";"))
        }

        // 备注。
        if let notes = nonEmpty(card.notes) {
            lines.append("NOTE:\(escape(notes))")
        }

        // 标签：以逗号连接；为空则不输出。
        let tags = card.tags.filter { !$0.isEmpty }
        if !tags.isEmpty {
            lines.append("CATEGORIES:" + tags.map(escape).joined(separator: ","))
        }

        lines.append("END:VCARD")

        return lines.map { $0 + "\r\n" }.joined()
    }

    /// 导出多张名片：每张一个 `BEGIN:VCARD`…`END:VCARD` 块依次拼接。
    static func document(for cards: [BusinessCard]) -> String {
        cards.map(vCard(for:)).joined()
    }

    // MARK: - 辅助

    /// 把可选字符串归一化为「有值」或 `nil`；`nil` 与空字符串都视为缺失。
    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value, !value.isEmpty else { return nil }
        return value
    }

    /// RFC 2426 值转义。注意先转义反斜杠，再处理其余字符，避免二次转义。
    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
