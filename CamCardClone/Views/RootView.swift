import SwiftUI

/// 应用根视图：承载 `NavigationStack` 与全部路由目的页。
///
/// 页面注册集中在此，便于对照 docs/规格说明书.md 第 5 节「页面清单」核对覆盖度。
struct RootView: View {

    let repository: BusinessCardRepository

    @EnvironmentObject private var router: AppRouter

    var body: some View {
        NavigationStack(path: $router.path) {
            CardHolderView(repository: repository)
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .cardDetail(let cardID):
                        CardDetailView(repository: repository, cardID: cardID)
                    case .scanner:
                        ScannerEntryView(repository: repository)
                    }
                }
        }
    }
}

#Preview {
    RootView(repository: InMemoryBusinessCardRepository(cards: BusinessCardMockData.sampleCards))
        .environmentObject(AppRouter())
}
