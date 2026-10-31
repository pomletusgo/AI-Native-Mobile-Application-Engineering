import XCTest
import SwiftUI
@testable import CamCardClone

/// 视图层 Golden Test（任务 5.4）。
///
/// 用 `UISnapshotGolden` 把纯 SwiftUI 视图离屏渲染后与 `testcards/ui-baselines/<名字>.png`
/// 逐像素比对。首批只覆盖能离屏稳定渲染的**组件级**视图；含 `List` 的整页留待 Mac + 模拟器
/// 的页面级 UI 测试（见 `UISnapshotGolden` 文件头的边界声明）。
///
/// 基线**绑定运行环境**（iOS 版本 / 渲染缩放），首次运行或在 Mac 上重录时用
/// `RECORD_GOLDEN=1` 生成基线；基线缺失时本组用例 `XCTSkip`，如实标注「待录制」而不是假装通过。
@MainActor
final class UISnapshotGoldenTests: XCTestCase {

    /// 录制模式：`RECORD_GOLDEN=1 <测试> ` 时把当前渲染结果写成基线。
    private var isRecordMode: Bool {
        ProcessInfo.processInfo.environment["RECORD_GOLDEN"] == "1"
    }

    // MARK: - 首批基线断言

    /// 名片列表行：缩略图 + 姓名/公司/电话 + 标签。
    func testCardRowViewMatchesBaseline() throws {
        try assertSnapshot(
            CardRowView(card: BusinessCardMockData.sampleCards[0]),
            named: "card-row",
            size: CGSize(width: 320, height: 96)
        )
    }

    /// 标签小标签组（名片行与详情页共用）。
    func testTagChipsViewMatchesBaseline() throws {
        try assertSnapshot(
            TagChipsView(tags: ["客户", "重点", "北京"]),
            named: "tag-chips",
            size: CGSize(width: 240, height: 40)
        )
    }

    /// 名片夹空状态（S1）：图标 + 两行文案 + 扫描按钮。
    func testEmptyCardHolderViewMatchesBaseline() throws {
        try assertSnapshot(
            EmptyCardHolderView {},
            named: "empty-card-holder",
            size: CGSize(width: 320, height: 320)
        )
    }

    // MARK: - 工具

    /// 渲染 →（录制或）比对 → 断言；基线缺失时 `XCTSkip` 并说明如何生成。
    private func assertSnapshot<V: View>(
        _ view: V,
        named name: String,
        size: CGSize,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard let image = UISnapshotGolden.render(view, size: size) else {
            XCTFail("离屏渲染失败（\(name)）：ImageRenderer 未产出位图，请检查视图是否依赖窗口环境",
                    file: file, line: line)
            return
        }

        let outcome = try UISnapshotGolden.evaluate(
            actual: image,
            baselineURL: UISnapshotGolden.baselineURL(named: name, sourceFilePath: #filePath),
            failureDumpURL: UISnapshotGolden.failureDumpURL(named: name, sourceFilePath: #filePath),
            recordMode: isRecordMode
        )

        switch outcome {
        case .recorded:
            XCTFail("已录制基线 \(name).png，重跑一次以执行比对（录制模式不应作为最终结论）", file: file, line: line)

        case .baselineMissing:
            throw XCTSkip("""
                缺少基线 testcards/ui-baselines/\(name).png：\
                需在 Mac 模拟器上执行 RECORD_GOLDEN=1 先录制，截图对比本体待执行
                """)

        case let .mismatched(diff):
            XCTFail("""
                截图与基线不一致（\(name)）：差异像素占比 \
                \(String(format: "%.4f", diff.differingPixelRatio)) > \
                \(UISnapshotGolden.defaultTolerance)，最大通道差 \(diff.maxChannelDelta)；\
                实际截图已写到 \(name)-actual.png
                """, file: file, line: line)

        case let .sizeMismatch(expected, actual):
            XCTFail("""
                基线与实际位图尺寸不同（\(name)）：基线 \(expected) / 实际 \(actual)，\
                一般是运行环境（机型 / 缩放）变化，需在目标环境重录
                """, file: file, line: line)

        case let .matched(diff):
            XCTAssertLessThanOrEqual(diff.differingPixelRatio, UISnapshotGolden.defaultTolerance,
                                     "\(name) 差异像素占比应在容差内", file: file, line: line)
        }
    }
}
