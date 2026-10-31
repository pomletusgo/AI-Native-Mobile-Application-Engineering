import SwiftUI

/// 应用入口。
///
/// 设计约束（见 docs/规格说明书.md 第 8 节）：
/// - 依赖通过初始化注入，App 层不直接持有业务逻辑。
/// - Week5 起使用持久化实现 `PersistentBusinessCardRepository`；`BusinessCardRepository`
///   协议未改动，调用方无需改动。
@main
struct CamCardCloneApp: App {

    @StateObject private var router = AppRouter()

    /// 全局唯一的名片仓库实例，数据落在 Application Support 目录下的 JSON 文件。
    /// T01 要求首次启动显示空名片夹，因此这里不注入 Mock 数据。
    private let repository: BusinessCardRepository = CamCardCloneApp.makeRepository()

    /// 全局唯一的名片图像存储实例，与仓库共用同一个存储目录。
    private let imageStore: CardImageStore = CamCardCloneApp.makeImageStore()

    /// 应用存储目录；取不到 Application Support 时退回临时目录，不崩溃。
    private static func makeStorageDirectory() -> URL {
        let fileManager = FileManager.default
        let baseDirectory = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        return baseDirectory.appendingPathComponent("CamCardClone", isDirectory: true)
    }

    /// 构建持久化仓库。
    private static func makeRepository() -> BusinessCardRepository {
        PersistentBusinessCardRepository(directory: makeStorageDirectory())
    }

    /// 构建图像存储；图像放在存储目录下的 `images` 子目录。
    private static func makeImageStore() -> CardImageStore {
        FileCardImageStore(directory: makeStorageDirectory().appendingPathComponent("images", isDirectory: true))
    }

    var body: some Scene {
        WindowGroup {
            RootView(repository: repository, imageStore: imageStore)
                .environmentObject(router)
        }
    }
}
