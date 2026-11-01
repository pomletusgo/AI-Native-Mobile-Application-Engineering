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

    /// 系统联系人导出器（P10）；详情页的「存入系统联系人」用它写入通讯录。
    private let contactExporter: ContactExporting = SystemContactExporter()

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

    /// UI 测试（`CamCardCloneUITests`）用的启动参数名。
    ///
    /// UI 测试进程不链接 App 模块，因此这两个字面量在 `CamCardCloneUITests` 里另有一份；
    /// 改动其一时必须同步另一处。
    static let resetStoreArgument = "-uiTestResetStore"
    static let seedStoreArgument = "-uiTestSeedStore"

    /// 构建持久化仓库。
    ///
    /// 为让 UI 测试拿到可复现的初始状态，这里支持两个启动参数：
    /// - `-uiTestResetStore`：启动前清空存储目录，回到「首次启动」的空名片夹（M01）；
    /// - `-uiTestSeedStore`：空库时写入 `BusinessCardMockData.sampleCards`，供列表 / 搜索 / 标签类验收使用。
    ///
    /// 正常运行不会带这两个参数，生产路径与既有行为不受影响。
    private static func makeRepository() -> BusinessCardRepository {
        let directory = makeStorageDirectory()
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(Self.resetStoreArgument) {
            try? FileManager.default.removeItem(at: directory)
        }
        let repository = PersistentBusinessCardRepository(directory: directory)
        if arguments.contains(Self.seedStoreArgument), repository.fetchAll().isEmpty {
            for card in BusinessCardMockData.sampleCards {
                repository.add(card)
            }
        }
        return repository
    }

    /// 构建图像存储；图像放在存储目录下的 `images` 子目录。
    private static func makeImageStore() -> CardImageStore {
        FileCardImageStore(directory: makeStorageDirectory().appendingPathComponent("images", isDirectory: true))
    }

    var body: some Scene {
        WindowGroup {
            RootView(repository: repository, imageStore: imageStore, contactExporter: contactExporter)
                .environmentObject(router)
        }
    }
}
