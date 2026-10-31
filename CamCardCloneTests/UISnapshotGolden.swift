import SwiftUI
import UIKit

/// 视图层 Golden Test（截图对比）的录制与比对工具（任务 5.4）。
///
/// 做法：用 `ImageRenderer` 把 SwiftUI 视图按固定尺寸与缩放**离屏渲染**成位图，再与
/// `testcards/ui-baselines/<名字>.png` 里的基线逐像素比对，产出两个数字：**差异像素占比**
/// 与**最大通道差**。
///
/// 两种模式：
/// - **比对模式（默认）**：读基线比对，差异像素占比超过 `defaultTolerance` 即判「不一致」，
///   并把实际截图写到 `<名字>-actual.png` 便于对照；
/// - **录制模式**：环境变量 `RECORD_GOLDEN=1` 时把当前渲染结果写成基线（首次记录，或界面
///   改版后重录）。
///
/// 边界（如实声明）：
/// - 基线**绑定运行环境**——iOS 版本 / 机型 / 渲染缩放不同会产生细微差异，跨环境需重录；
/// - 首批只覆盖能离屏稳定渲染的纯 SwiftUI 视图。含 `List`（UIKit 集合视图支撑）的整页在
///   `ImageRenderer` 下可能渲染为空，故整页页面级截图（P01 列表态 / P02 详情 / P03 / P05 /
///   P09）留待 Mac + 模拟器的页面级 UI 测试，此处不假装已覆盖。
enum UISnapshotGolden {

    /// 允许的差异像素占比上限。iOS 版本或机型变化会带来极少量抗锯齿差异，这是
    /// 「同环境必须一致、跨环境允许极小漂移」的折中。
    static let defaultTolerance = 0.01

    /// 单通道差超过该值才算「这个像素变了」，用来吸收抗锯齿与色值抖动。
    static let channelThreshold = 4

    /// 渲染缩放固定为 2，使基线像素尺寸在不同设备上保持一致。
    static let renderScale: CGFloat = 2

    struct PixelDiff: Equatable {
        /// 判定为「变了」的像素占全部像素的比例（0…1）。
        let differingPixelRatio: Double
        /// 单通道最大差值（0…255）：判断差异是「肉眼可见」还是「几乎一样」。
        let maxChannelDelta: Int
    }

    enum Outcome: Equatable {
        /// 录制模式下已写出基线。
        case recorded
        /// 比对模式下基线文件不存在（需先录制）。
        case baselineMissing
        case matched(PixelDiff)
        case mismatched(PixelDiff)
        /// 基线与实际位图尺寸不同（一般是运行环境变了，需重录）。
        case sizeMismatch(expected: CGSize, actual: CGSize)
    }

    enum SnapshotError: Error {
        /// `UIImage.pngData()` 编码失败。
        case cannotEncodePNG
    }

    // MARK: - 渲染

    /// 把视图离屏渲染为位图。固定浅色外观，避免宿主深浅色设置影响基线。
    @MainActor
    static func render<V: View>(_ view: V, size: CGSize, scale: CGFloat = renderScale) -> UIImage? {
        let content = view
            .environment(\.colorScheme, .light)
            .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(size)
        return renderer.uiImage
    }

    // MARK: - 路径

    /// 基线目录：`<仓库根>/testcards/ui-baselines`。仓库根由测试源文件路径推出，
    /// 与 `FieldExtractionEvaluator.repositoryRoot(sourceFilePath:)` 同一套规则。
    static func baselineDirectory(sourceFilePath: String) -> URL {
        FieldExtractionEvaluator.repositoryRoot(sourceFilePath: sourceFilePath)
            .appendingPathComponent("testcards", isDirectory: true)
            .appendingPathComponent("ui-baselines", isDirectory: true)
    }

    static func baselineURL(named name: String, sourceFilePath: String) -> URL {
        baselineDirectory(sourceFilePath: sourceFilePath)
            .appendingPathComponent("\(name).png")
    }

    /// 比对不一致时落地的实际截图，便于人工定位差异。
    static func failureDumpURL(named name: String, sourceFilePath: String) -> URL {
        baselineDirectory(sourceFilePath: sourceFilePath)
            .appendingPathComponent("\(name)-actual.png")
    }

    // MARK: - 录制与比对

    static func record(_ image: UIImage, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let data = image.pngData() else { throw SnapshotError.cannotEncodePNG }
        try data.write(to: url)
    }

    @MainActor
    static func evaluate(
        actual: UIImage,
        baselineURL: URL,
        failureDumpURL: URL,
        recordMode: Bool
    ) throws -> Outcome {
        if recordMode {
            try record(actual, to: baselineURL)
            return .recorded
        }
        guard let data = try? Data(contentsOf: baselineURL), let baseline = UIImage(data: data) else {
            return .baselineMissing
        }
        guard let diff = pixelDiff(reference: baseline, actual: actual) else {
            return .sizeMismatch(expected: baseline.size, actual: actual.size)
        }
        guard diff.differingPixelRatio <= defaultTolerance else {
            // 落盘实际截图，便于与基线逐处对照
            try? record(actual, to: failureDumpURL)
            return .mismatched(diff)
        }
        return .matched(diff)
    }

    // MARK: - 逐像素比对

    /// 逐像素比对两张位图；取不到像素数据或尺寸不同时返回 `nil`（由调用方按「尺寸不一致」处理）。
    static func pixelDiff(reference: UIImage, actual: UIImage) -> PixelDiff? {
        guard let lhs = rgbaBytes(of: reference), let rhs = rgbaBytes(of: actual) else { return nil }
        guard !lhs.isEmpty, lhs.count == rhs.count else { return nil }

        var differing = 0
        var maxDelta = 0
        var index = 0
        while index + 3 < lhs.count {
            var pixelChanged = false
            for channel in 0..<3 {
                let delta = abs(Int(lhs[index + channel]) - Int(rhs[index + channel]))
                if delta > maxDelta { maxDelta = delta }
                if delta > channelThreshold { pixelChanged = true }
            }
            if pixelChanged { differing += 1 }
            index += 4
        }
        let totalPixels = lhs.count / 4
        return PixelDiff(
            differingPixelRatio: Double(differing) / Double(totalPixels),
            maxChannelDelta: maxDelta
        )
    }

    /// 把位图统一重画进 RGBA8 缓冲，避免直接读 `CGImage` 数据时受位深与字节序影响。
    private static func rgbaBytes(of image: UIImage) -> [UInt8]? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
