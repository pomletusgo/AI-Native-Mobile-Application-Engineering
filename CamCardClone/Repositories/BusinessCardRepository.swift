import Foundation

/// 名片仓库抽象。
///
/// 稳定性约束（见 docs/规格说明书.md 第 8 节）：本协议一旦确定，Week3–Week5 新增 OCR / 持久化 / 导出
/// 能力时**不得修改**，只能新增方法或提供新的实现类型，以保证既有测试不被破坏。
protocol BusinessCardRepository: AnyObject {

    /// 返回全部名片（按创建时间倒序）。
    func fetchAll() -> [BusinessCard]

    /// 按主键查询单张名片。
    func card(withID id: UUID) -> BusinessCard?

    /// 新增一张名片。
    func add(_ card: BusinessCard)

    /// 更新已存在的名片（按 `id` 匹配）；不存在时忽略。
    func update(_ card: BusinessCard)

    /// 按主键删除名片。
    func delete(id: UUID)

    /// 按关键字搜索（姓名 / 公司 / 职位 / 电话 / 邮箱等，大小写不敏感）。
    /// 关键字为空时返回全部。
    func search(_ query: String) -> [BusinessCard]

    /// 返回带有指定标签的名片（标签比较大小写不敏感）。
    func cards(taggedWith tag: String) -> [BusinessCard]

    /// 全部标签（去重，大小写不敏感）。
    var allTags: [String] { get }
}
