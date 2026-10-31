import SwiftUI

/// 名片详情页（P06），同时承载编辑态（P07）。
///
/// 覆盖状态：D1 查看 / D2 编辑 / D3 字段可点击（电话、邮箱、网站调用系统原生组件）；
/// 标签的增删在编辑态完成（P09），查看态展示已保存的标签。
struct CardDetailView: View {

    @StateObject private var viewModel: CardDetailViewModel
    @EnvironmentObject private var router: AppRouter
    @Environment(\.openURL) private var openURL

    /// 编辑态里「添加标签」输入框的内容。
    @State private var newTagText: String = ""

    init(repository: BusinessCardRepository, cardID: UUID) {
        _viewModel = StateObject(wrappedValue: CardDetailViewModel(repository: repository, cardID: cardID))
    }

    var body: some View {
        Group {
            if viewModel.isMissing {
                Text("名片不存在")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("cardMissing")
            } else if viewModel.isEditing {
                editForm
            } else if let card = viewModel.card {
                detailList(card: card)
            }
        }
        .navigationTitle(viewModel.card?.name ?? "名片详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if viewModel.isEditing {
                    Button("取消") { cancelEditing() }
                        .accessibilityIdentifier("cancelEditButton")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if viewModel.isEditing {
                    Button("保存") { saveEditing() }
                        .accessibilityIdentifier("saveEditButton")
                } else if !viewModel.isMissing {
                    Button("编辑") { viewModel.beginEditing() }
                        .accessibilityIdentifier("editButton")
                }
            }
        }
    }

    // MARK: - 查看态

    private func detailList(card: BusinessCard) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(card.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    if let subtitle = card.subtitle {
                        Text(subtitle)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                if let department = card.department {
                    valueRow("部门", department)
                }
            }

            if !card.tags.isEmpty {
                Section("标签") {
                    TagChipsView(tags: card.tags)
                }
            }

            Section("联系方式") {
                if let mobile = card.mobile { phoneRow("手机", mobile) }
                if let phone = card.phone { phoneRow("电话", phone) }
                if let fax = card.fax { phoneRow("传真", fax) }
                if let email = card.email {
                    linkRow("邮箱", email, url: URL(string: "mailto:\(email)"))
                }
                if let website = card.website {
                    linkRow("网站", website, url: URL(string: normalizedURL(website)))
                }
                if let address = card.address { valueRow("地址", address) }
                if let postalCode = card.postalCode { valueRow("邮编", postalCode) }
            }

            if let notes = card.notes, !notes.isEmpty {
                Section("备注") {
                    Text(notes)
                }
            }

            Section {
                Button("删除名片", role: .destructive) {
                    viewModel.delete()
                    router.pop()
                }
                .accessibilityIdentifier("deleteCardButton")
            }
        }
    }

    // MARK: - 编辑态

    private var editForm: some View {
        Form {
            Section("基本信息") {
                TextField("姓名（必填）", text: stringBinding(\.name))
                    .accessibilityIdentifier("editNameField")
                TextField("公司", text: optionalStringBinding(\.company))
                TextField("职位", text: optionalStringBinding(\.jobTitle))
                TextField("部门", text: optionalStringBinding(\.department))
            }

            Section("联系方式") {
                TextField("手机", text: optionalStringBinding(\.mobile))
                    .keyboardType(.phonePad)
                TextField("电话", text: optionalStringBinding(\.phone))
                    .keyboardType(.phonePad)
                TextField("传真", text: optionalStringBinding(\.fax))
                    .keyboardType(.phonePad)
                TextField("邮箱", text: optionalStringBinding(\.email))
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("网站", text: optionalStringBinding(\.website))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("地址", text: optionalStringBinding(\.address))
                TextField("邮编", text: optionalStringBinding(\.postalCode))
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
            }

            tagEditor

            Section("备注") {
                TextField("备注", text: optionalStringBinding(\.notes), axis: .vertical)
                    .lineLimit(2...5)
            }
        }
    }

    // MARK: - 标签编辑（P09）

    private var tagEditor: some View {
        Section("标签") {
            if viewModel.editableTags.isEmpty {
                Text("暂无标签")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("noTagsHint")
            } else {
                ForEach(viewModel.editableTags, id: \.self) { tag in
                    HStack {
                        Text(tag)
                        Spacer()
                        Button {
                            viewModel.removeTag(tag)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("删除标签 \(tag)")
                        .accessibilityIdentifier("removeTagButton_\(tag)")
                    }
                }
                .onDelete { offsets in
                    let tags = viewModel.editableTags
                    offsets.forEach { viewModel.removeTag(tags[$0]) }
                }
            }

            HStack {
                TextField("添加标签", text: $newTagText)
                    .accessibilityIdentifier("newTagField")
                    .onSubmit { addTag() }
                Button("添加") { addTag() }
                    .buttonStyle(.borderless)
                    .disabled(newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("addTagButton")
            }
        }
    }

    // MARK: - 编辑动作

    private func addTag() {
        // 仅在真正写入草稿后才清空输入框：重复标签或空输入会保留原文，便于用户看到未被接受。
        if viewModel.addTag(newTagText) {
            newTagText = ""
        }
    }

    private func cancelEditing() {
        newTagText = ""
        viewModel.cancelEditing()
    }

    private func saveEditing() {
        if viewModel.saveEditing() {
            newTagText = ""
        }
    }

    // MARK: - 行组件

    private func valueRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func phoneRow(_ label: String, _ value: String) -> some View {
        Button {
            let sanitized = value.filter { $0.isNumber || $0 == "+" }
            if let url = URL(string: "tel://\(sanitized)") {
                openURL(url)
            }
        } label: {
            HStack {
                Text(label)
                    .foregroundStyle(.primary)
                Spacer()
                Text(value)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .accessibilityIdentifier("phoneRow_\(label)")
    }

    private func linkRow(_ label: String, _ value: String, url: URL?) -> some View {
        Button {
            if let url { openURL(url) }
        } label: {
            HStack {
                Text(label)
                    .foregroundStyle(.primary)
                Spacer()
                Text(value)
                    .foregroundStyle(Color.accentColor)
                    .multilineTextAlignment(.trailing)
            }
        }
        .accessibilityIdentifier("linkRow_\(label)")
    }

    // MARK: - 工具

    private func normalizedURL(_ raw: String) -> String {
        if raw.lowercased().hasPrefix("http://") || raw.lowercased().hasPrefix("https://") {
            return raw
        }
        return "https://\(raw)"
    }

    /// 绑定到草稿的非可选字段。
    private func stringBinding(_ keyPath: WritableKeyPath<BusinessCard, String>) -> Binding<String> {
        Binding(
            get: { viewModel.draft?[keyPath: keyPath] ?? "" },
            set: { newValue in
                guard viewModel.draft != nil else { return }
                viewModel.draft?[keyPath: keyPath] = newValue
            }
        )
    }

    /// 绑定到草稿的可选字段；输入为空时写回 `nil`（保证「空字段即不存在」的规格）。
    private func optionalStringBinding(_ keyPath: WritableKeyPath<BusinessCard, String?>) -> Binding<String> {
        Binding(
            get: { viewModel.draft?[keyPath: keyPath] ?? "" },
            set: { newValue in
                guard viewModel.draft != nil else { return }
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                viewModel.draft?[keyPath: keyPath] = trimmed.isEmpty ? nil : newValue
            }
        )
    }
}

#Preview {
    NavigationStack {
        CardDetailView(
            repository: InMemoryBusinessCardRepository(cards: BusinessCardMockData.sampleCards),
            cardID: BusinessCardMockData.sampleCards[0].id
        )
    }
    .environmentObject(AppRouter())
}
