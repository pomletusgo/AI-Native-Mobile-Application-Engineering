import Foundation
import PhotosUI
import SwiftUI

/// 相册导入过程中可预期的失败。
enum PhotoImportError: LocalizedError, Equatable {
    /// 选中的项目读不出图片数据：格式不受支持，或导出被中断。
    case unreadableItem
    /// 读出来的数据是空的。
    case emptyImageData

    var errorDescription: String? {
        switch self {
        case .unreadableItem:
            return "无法读取所选照片，请换一张或改用相机拍摄。"
        case .emptyImageData:
            return "所选照片没有内容，请换一张或改用相机拍摄。"
        }
    }
}

/// 把相册里选中的项目读成图片数据。
///
/// 抽成协议是为了让上层流程能脱离系统选择器单测；真实实现见 `PhotosPickerImageImporter`。
protocol PhotoImporting: AnyObject {
    /// 读取选中项目的图片数据。读不出内容时抛 `PhotoImportError`。
    func importedImageData(from item: PhotosPickerItem) async throws -> Data
}

/// 基于 SwiftUI `PhotosPicker` 的实现。
final class PhotosPickerImageImporter: PhotoImporting {

    func importedImageData(from item: PhotosPickerItem) async throws -> Data {
        let loaded: Data?
        do {
            loaded = try await item.loadTransferable(type: Data.self)
        } catch {
            throw PhotoImportError.unreadableItem
        }
        return try Self.imageData(from: loaded)
    }

    /// 把加载结果规范成图片数据：`nil`（读不出来）与空数据都算失败，不把空数据当成有效图片。
    ///
    /// 单独抽成静态函数，这样这段判定逻辑不需要真实的 `PhotosPickerItem` 也能验证。
    static func imageData(from loaded: Data?) throws -> Data {
        guard let loaded else { throw PhotoImportError.unreadableItem }
        guard !loaded.isEmpty else { throw PhotoImportError.emptyImageData }
        return loaded
    }
}
