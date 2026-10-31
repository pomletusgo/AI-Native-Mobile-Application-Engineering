import Foundation

/// 名片图像种类：原始图与校正图分开存放，避免同名互相覆盖。
enum BusinessCardImageKind: String, CaseIterable {
    /// 拍摄或相册导入得到的原图（P06 详情页展示的就是它）。
    case original
    /// 透视校正后的裁剪图（识别用）。
    case processed
}

/// 名片图像存储协议。
///
/// 只负责「按名字读写图像字节」，不关心图像内容与名片字段：
/// 名字由实现生成并写入 `BusinessCard.originalImageName` / `processedImageName`，
/// 详情页再按名字取回字节交给 `UIImage` 渲染。
///
/// 读写失败一律返回 `nil` 而不抛错——图像缺失只影响详情页能否展示缩略图，
/// 不应阻断「保存名片」这条主流程。
protocol CardImageStore {

    /// 保存一张图像，返回可写入 `BusinessCard` 的名字；数据为空或写入失败时返回 `nil`。
    func save(_ data: Data, cardID: UUID, kind: BusinessCardImageKind) -> String?

    /// 按名字取回图像字节；名字为空、文件不存在或不可读时返回 `nil`。
    func load(named name: String?) -> Data?

    /// 删除某张名片的两张图像（名片被删除后清理，避免留下孤儿文件）。
    func deleteImages(for cardID: UUID)
}

/// 基于文件系统的名片图像存储。
///
/// 名字形如 `<uuid>-original.jpg`，**不含路径分隔符**，因此可以安全地写进
/// `BusinessCard.imageName` 并随名片的 JSON 一起持久化；同一张名片重复保存同名图像即覆盖，不会堆积。
struct FileCardImageStore: CardImageStore {

    private let directory: URL
    private let fileManager: FileManager

    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    func save(_ data: Data, cardID: UUID, kind: BusinessCardImageKind) -> String? {
        guard !data.isEmpty else { return nil }
        let name = Self.fileName(cardID: cardID, kind: kind)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    func load(named name: String?) -> Data? {
        guard let name, !name.isEmpty else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(name))
    }

    func deleteImages(for cardID: UUID) {
        for kind in BusinessCardImageKind.allCases {
            let url = directory.appendingPathComponent(Self.fileName(cardID: cardID, kind: kind))
            try? fileManager.removeItem(at: url)
        }
    }

    /// 生成稳定的文件名；名字里只有 UUID 与种类，不含目录分隔符。
    static func fileName(cardID: UUID, kind: BusinessCardImageKind) -> String {
        "\(cardID.uuidString.lowercased())-\(kind.rawValue).jpg"
    }
}
