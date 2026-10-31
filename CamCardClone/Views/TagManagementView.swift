import SwiftUI

/// 标签管理页（P09）。
///
/// 三种状态：
/// 1. 标签列表——展示全部标签与使用张数，可左滑删除整个标签，可点进「按标签查看」；
/// 2. 按标签查看——展示该标签下的名片，可点进名片详情；
/// 3. 新建标签——输入名称并勾选要打上该标签的名片后保存。
struct TagManagementView: View {

    @StateObject private var viewModel: TagManagementViewModel
    @EnvironmentObject private var router: AppRouter

    init(repository: BusinessCardRepository) {
        _viewModel = StateObject(wrappedValue: TagManagementViewModel(repository: repository))
    }

    var body: some View {
        List {
            if viewModel.isCreating {
                creationSections
            } else if let tag = viewModel.viewingTag {
                viewingSections(tag: tag)
            } else {
                tagListSection
            }
        }
        .navigationTitle("标签管理")
        .accessibilityIdentifier("tagManagement")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if viewModel.isCreating {
                    Button("取消") { viewModel.cancelCreating() }
                        .accessibilityIdentifier("newTagCancelButton")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if !viewModel.isCreating && viewModel.viewingTag == nil {
                    Button("新建标签") { viewModel.beginCreating() }
                        .accessibilityIdentifier("newTagButton")
                }
            }
        }
        .onAppear { viewModel.load() }
    }

    // MARK: - 状态 1：标签列表

    private var tagListSection: some View {
        Section {
            if viewModel.tags.isEmpty {
                Text("还没有标签。可以在名片详情的编辑态添加，或点右上角「新建标签」。")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("tagListEmpty")
            } else {
                ForEach(viewModel.tags) { summary in
                    Button {
                        viewModel.beginViewing(tag: summary.name)
                    } label: {
                        HStack {
                            Text(summary.name)
                            Spacer()
                            Text("\(summary.cardCount) 张")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tagRow_\(summary.name)")
                    .swipeActions {
                        Button(role: .destructive) {
                            viewModel.deleteTag(summary.name)
                        } label: {
                            Text("删除标签")
                        }
                        .accessibilityIdentifier("deleteTag_\(summary.name)")
                    }
                }
            }
        }
    }

    // MARK: - 状态 2：按标签查看

    private func viewingSections(tag: String) -> some View {
        Group {
            Section {
                Button {
                    viewModel.endViewing()
                } label: {
                    Label("返回全部标签", systemImage: "chevron.left")
                }
                .accessibilityIdentifier("endViewingButton")
            }

            Section("「\(tag)」下的名片") {
                if viewModel.viewingCards.isEmpty {
                    Text("该标签下暂无名片")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.viewingCards) { card in
                        Button {
                            router.push(.cardDetail(cardID: card.id))
                        } label: {
                            CardRowView(card: card)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("taggedCardRow")
                    }
                }
            }
        }
    }

    // MARK: - 状态 3：新建标签

    private var creationSections: some View {
        Group {
            Section("新建标签") {
                TextField("标签名称", text: $viewModel.newTagName)
                    .accessibilityIdentifier("newTagNameField")
                if let error = viewModel.creationError {
                    Text(error)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("newTagError")
                }
                Button("保存") { viewModel.saveNewTag() }
                    .accessibilityIdentifier("newTagSaveButton")
            }

            Section("选择名片（至少一张）") {
                if viewModel.cards.isEmpty {
                    Text("名片夹还是空的，先扫描或导入一张名片。")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("newTagNoCards")
                } else {
                    ForEach(viewModel.cards) { card in
                        Button {
                            viewModel.toggleSelection(card.id)
                        } label: {
                            HStack {
                                Text(card.name)
                                Spacer()
                                if viewModel.selectedCardIDs.contains(card.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("newTagCard_\(card.id.uuidString)")
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        TagManagementView(
            repository: InMemoryBusinessCardRepository(cards: BusinessCardMockData.sampleCards)
        )
    }
    .environmentObject(AppRouter())
}
