import SwiftUI

/// 页面路由定义。
///
/// 新增页面时在此扩展，避免导航逻辑散落在各 View 中。
enum AppRoute: Hashable {
    /// 名片详情
    case cardDetail(cardID: UUID)
    /// 扫描名片入口（Week2 为占位页，Week3 接入相机）
    case scanner
    /// 标签管理（P09）
    case tagManagement
}

/// 全局导航状态。
///
/// 使用 `NavigationStack` 的 `path` 绑定，支持 push / pop / popToRoot。
@MainActor
final class AppRouter: ObservableObject {

    @Published var path: [AppRoute] = []

    func push(_ route: AppRoute) {
        path.append(route)
    }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func popToRoot() {
        path.removeAll()
    }
}
