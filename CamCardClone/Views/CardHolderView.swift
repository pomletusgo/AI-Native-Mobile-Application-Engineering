import SwiftUI

/// 名片夹首页（P01）。
///
/// 覆盖状态：S1 空名片夹 / S2 有名片 / S3 搜索中 / S4 标签筛选。
struct CardHolderView: View {

    @StateObject private var viewModel: CardHolderViewModel
    @EnvironmentObject private var router: AppRouter

    init(repository: BusinessCardRepository) {
        _viewModel = StateObject(wrappedValue: CardHolderViewModel(repository: repository))
    }

    var body: some View {
        Group {
            if viewModel.isEmpty {
                EmptyCardHolderView { router.push(.scanner) }
            } else {
                cardList
            }
        }
        .navigationTitle("名片夹")
        .searchable(text: $viewModel.searchText, prompt: "搜索姓名、公司、职位、电话、Email")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    router.push(.tagManagement)
                } label: {
                    Image(systemName: "tag")
                }
                .accessibilityLabel("标签管理")
                .accessibilityIdentifier("tagManagementEntry")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    router.push(.scanner)
                } label: {
                    Image(systemName: "plus.viewfinder")
                }
                .accessibilityLabel("扫描名片")
                .accessibilityIdentifier("scanEntryButton")
            }
        }
        .onAppear { viewModel.load() }
        .onChange(of: router.path) { _ in viewModel.load() }
    }

    // MARK: - 子视图

    private var cardList: some View {
        List {
            if !viewModel.allTags.isEmpty {
                Section {
                    tagFilterBar
                }
            }

            Section {
                if viewModel.hasNoResults {
                    Text("未找到匹配的名片")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("noSearchResult")
                } else {
                    ForEach(viewModel.visibleCards) { card in
                        Button {
                            router.push(.cardDetail(cardID: card.id))
                        } label: {
                            CardRowView(card: card)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("cardRow")
                    }
                    .onDelete { viewModel.delete(at: $0) }
                }
            }
        }
    }

    private var tagFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.allTags, id: \.self) { tag in
                    Button {
                        viewModel.toggleTagFilter(tag)
                    } label: {
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(viewModel.selectedTag == tag
                                          ? Color.accentColor.opacity(0.2)
                                          : Color.secondary.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tagChip_\(tag)")
                }
            }
            .padding(.vertical, 4)
        }
    }
}

#Preview("有名片") {
    NavigationStack {
        CardHolderView(repository: InMemoryBusinessCardRepository(cards: BusinessCardMockData.sampleCards))
    }
    .environmentObject(AppRouter())
}

#Preview("空名片夹") {
    NavigationStack {
        CardHolderView(repository: InMemoryBusinessCardRepository())
    }
    .environmentObject(AppRouter())
}
