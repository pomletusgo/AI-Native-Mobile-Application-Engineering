import SwiftUI

/// 应用入口。
///
/// 设计约束（见 docs/规格说明书.md 第 8 节）：
/// - 依赖通过初始化注入，App 层不直接持有业务逻辑。
/// - Week2 使用 `InMemoryBusinessCardRepository`；Week5 替换为持久化实现时，`BusinessCardRepository`
///   协议保持不变，调用方无需改动。
@main
struct CamCardCloneApp: App {

    @StateObject private var router = AppRouter()

    /// 全局唯一的名片仓库实例。
    /// T01 要求首次启动显示空名片夹，因此这里不注入 Mock 数据。
    private let repository: BusinessCardRepository = InMemoryBusinessCardRepository()

    var body: some Scene {
        WindowGroup {
            RootView(repository: repository)
                .environmentObject(router)
        }
    }
}
