import Foundation
import Combine

/// 名片详情 / 编辑 ViewModel（对应 P06、P07）。
@MainActor
final class CardDetailViewModel: ObservableObject {

    /// 已保存的名片（`nil` 表示名片不存在，例如被删除后返回）。
    @Published private(set) var card: BusinessCard?

    /// 编辑中的草稿。非 `nil` 表示处于编辑态（状态 D2）。
    @Published var draft: BusinessCard?

    private let repository: BusinessCardRepository
    private let cardID: UUID

    init(repository: BusinessCardRepository, cardID: UUID) {
        self.repository = repository
        self.cardID = cardID
        reload()
    }

    // MARK: - 派生状态

    var isEditing: Bool { draft != nil }

    var isMissing: Bool { card == nil }

    // MARK: - 操作

    func reload() {
        card = repository.card(withID: cardID)
    }

    /// 进入编辑态。
    func beginEditing() {
        guard let card else { return }
        draft = card
    }

    /// 取消编辑，丢弃草稿。
    func cancelEditing() {
        draft = nil
    }

    /// 保存编辑。
    ///
    /// - 返回 `true` 表示保存成功。
    /// - 姓名为空时拒绝保存并返回 `false`（对应 T20「字段为空」异常路径）。
    @discardableResult
    func saveEditing() -> Bool {
        guard var edited = draft else { return false }

        let trimmedName = edited.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        edited.name = trimmedName

        repository.update(edited)
        draft = nil
        reload()
        return true
    }

    /// 删除当前名片。
    func delete() {
        repository.delete(id: cardID)
        reload()
    }
}
