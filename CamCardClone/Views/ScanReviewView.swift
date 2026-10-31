import SwiftUI
import UIKit

/// 扫描结果复核页（P03 检测与校正 → P04 识别中 → P05 结果确认与校正）。
///
/// 由 `ScannerEntryView` 在拿到照片后展示：本页自动跑一次「检测 → 校正 → 识别 → 抽取」，
/// 把结果放进取景页下方的可编辑表单，用户逐字段校正后「保存」才落库。
///
/// 页面只做展示与转发意图，状态与异常处理都在 `ScanReviewViewModel`；
/// 「重拍」与「取消/返回」通过闭包交回 `ScannerEntryView`，避免两页各自持有一份会话状态。
struct ScanReviewView: View {

    @StateObject private var model: ScanReviewViewModel

    /// 重拍：丢弃本次照片，留在扫描页重新取景。
    private let onRetake: () -> Void
    /// 取消或保存完成：丢弃本次会话产物并返回名片夹。
    private let onFinish: () -> Void

    init(
        imageData: Data,
        repository: BusinessCardRepository,
        imageStore: CardImageStore? = nil,
        onRetake: @escaping () -> Void,
        onFinish: @escaping () -> Void
    ) {
        // 检测与校正由同一个实现承担（见 `VisionCardBoundaryDetector`），这里复用一份实例。
        let boundary = VisionCardBoundaryDetector()
        _model = StateObject(wrappedValue: ScanReviewViewModel(
            originalImageData: imageData,
            repository: repository,
            detector: boundary,
            corrector: boundary,
            ocr: VisionOCRService(),
            parser: BusinessCardFieldParser(),
            imageStore: imageStore
        ))
        self.onRetake = onRetake
        self.onFinish = onFinish
    }

    var body: some View {
        Group {
            switch model.phase {
            case .analyzing:
                analyzingContent
            case .adjustingBoundary:
                adjustingBoundaryContent
            case .review:
                reviewContent
            case .saved:
                savedContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("scanReview")
        .task { await model.analyze() }
        .alert("无法保存", isPresented: isSaveFailurePresented) {
            Button("好", role: .cancel) { model.dismissFailure() }
        } message: {
            Text(model.failureMessage ?? "")
        }
    }

    // MARK: - P03 / P04：检测与识别中

    private var analyzingContent: some View {
        VStack(spacing: 20) {
            imagePreview

            if let message = model.failureMessage {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("scanReviewNotice")

                Button {
                    Task { await model.analyze() }
                } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("scanReviewRetryButton")

                if model.canAdjustBoundary {
                    Button {
                        model.beginManualAdjustment()
                    } label: {
                        Label("手动调整边界", systemImage: "crop")
                    }
                    .accessibilityIdentifier("scanReviewManualAdjustButton")
                }

                retakeButton
                cancelButton
            } else {
                // P04：识别进行中要有明确反馈（规格 Optical character recognition）。
                ProgressView()
                    .accessibilityIdentifier("scanReviewProgress")
                Text("正在检测名片区域并识别文字…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
    }

    // MARK: - P03：手动调整边界

    /// 自动检测不可靠或未找到时的手动调整态。
    ///
    /// 编辑语义（起点选取、命中测试、拖拽夹紧、凸性 / 面积合法性判定）由
    /// `CardBoundaryAdjustment` 承担并有单测覆盖；本页只负责把归一化坐标映射到屏幕、
    /// 画出手柄，并把拖拽意图转发给 `ScanReviewViewModel`。
    /// 「使用此区域」走的是与自动检测**同一条**校正 → 识别链路，没有第二套识别路径。
    private var adjustingBoundaryContent: some View {
        VStack(spacing: 16) {
            if let adjustment = model.adjustment {
                BoundaryAdjustmentCanvas(
                    imageData: model.originalImageData,
                    adjustment: adjustment,
                    onMove: { corner, point in
                        model.moveBoundaryCorner(corner, to: point)
                    }
                )
                .frame(maxHeight: 360)
            } else {
                imagePreview
            }

            Text("拖动四个角上的圆点，把框对齐到名片边缘。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("scanReviewAdjustHint")

            HStack(spacing: 16) {
                Button {
                    Task { await model.applyBoundaryAdjustment() }
                } label: {
                    Label("使用此区域", systemImage: "checkmark.circle")
                }
                .accessibilityIdentifier("scanReviewApplyAdjustmentButton")

                Button("重置区域") { model.resetBoundaryAdjustment() }
                    .accessibilityIdentifier("scanReviewResetAdjustmentButton")

                Button("取消调整") { model.cancelBoundaryAdjustment() }
                    .accessibilityIdentifier("scanReviewCancelAdjustmentButton")
            }

            retakeButton
        }
        .padding(24)
    }

    // MARK: - P05：结果确认与校正

    private var reviewContent: some View {
        Form {
            Section {
                ForEach(ScanReviewViewModel.editableKeys, id: \.self) { key in
                    HStack {
                        Text(key.displayName)
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .leading)
                        TextField(key.displayName, text: binding(for: key))
                            .accessibilityIdentifier("scanReviewField-\(key.rawValue)")
                    }
                }
            } header: {
                Text("请核对并修正识别结果")
            } footer: {
                Text("未确认前不会写入名片夹；姓名为空无法保存。")
            }
        }
        .safeAreaInset(edge: .bottom) { confirmationBar }
    }

    private var confirmationBar: some View {
        HStack(spacing: 16) {
            Text("识别结果仅供参考，请逐字段核对。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Button("取消") { onFinish() }
                .accessibilityIdentifier("scanReviewCancelButton")

            Button {
                if model.confirmSave() { onFinish() }
            } label: {
                Label("保存", systemImage: "tray.and.arrow.down")
            }
            .accessibilityIdentifier("scanReviewSaveButton")
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: - 已保存

    private var savedContent: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("已保存到名片夹…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }

    // MARK: - 公共片段

    @ViewBuilder
    private var imagePreview: some View {
        if let image = UIImage(data: model.correctedImageData ?? model.originalImageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("scanReviewImage")
        }
    }

    private var retakeButton: some View {
        Button {
            onRetake()
        } label: {
            Label("重拍", systemImage: "arrow.counterclockwise")
        }
        .accessibilityIdentifier("scanReviewRetakeButton")
    }

    private var cancelButton: some View {
        Button("取消") { onFinish() }
            .accessibilityIdentifier("scanReviewCancelButton")
    }

    private func binding(for key: CardFieldKey) -> Binding<String> {
        Binding(
            get: { model.field(key) },
            set: { model.setField($0, for: key) }
        )
    }

    /// 保存被拒（姓名为空）时弹提示；识别阶段的失败改为页面内联提示，不弹窗打断。
    private var isSaveFailurePresented: Binding<Bool> {
        Binding(
            get: { model.phase == .review && model.failureMessage != nil },
            set: { isPresented in
                guard !isPresented else { return }
                model.dismissFailure()
            }
        )
    }
}

// MARK: - P03：手动调整边界的画布

/// 手动调整边界的画布：底图 + 四边形描边 + 四个可拖拽的角手柄。
///
/// `CardQuad` 用的是**相对整张原始图**的归一化坐标，且 y 轴向上；SwiftUI 的 y 轴向下，
/// 因此这里统一换算。画布自身的宽高比锁定为图片宽高比，使「画布矩形 == 图片矩形」，
/// 叠框才不会随留白漂移。
///
/// 已知假设：归一化坐标相对**原始像素**，而 `UIImage` 渲染时会应用 EXIF 方向标记；
/// 带方向标记的照片上叠框可能与画面有偏差，需在真机上用真实照片确认（见 `docs/UI验收清单.md`）。
private struct BoundaryAdjustmentCanvas: View {

    let imageData: Data
    let adjustment: CardBoundaryAdjustment
    /// 拖拽把手柄移到归一化坐标（裁剪与合法性判定由 `CardBoundaryAdjustment` 负责）。
    let onMove: (CardQuadCorner, CGPoint) -> Void

    /// 选中的角与它在拖拽开始时的位置：命中某个角时才建立，手势结束清空。
    @State private var activeCorner: CardQuadCorner?
    @State private var dragAnchor: CGPoint?

    private static let cornerOrder: [CardQuadCorner] = [.topLeft, .topRight, .bottomRight, .bottomLeft]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                baseImage(in: size)
                quadOverlay(in: size)
                handles(in: size)
            }
            .contentShape(Rectangle())
            // 手势挂在画布自身，默认的 local 坐标系即画布坐标（原点左上）。
            .gesture(dragGesture(in: size))
        }
        .aspectRatio(displayAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("scanReviewAdjustCanvas")
    }

    // MARK: - 片段

    @ViewBuilder
    private func baseImage(in size: CGSize) -> some View {
        if let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
        }
    }

    /// 四边形的半透明填充与描边。
    @ViewBuilder
    private func quadOverlay(in size: CGSize) -> some View {
        let points = Self.cornerOrder.map { screenPoint(adjustment.position(of: $0), in: size) }

        Path { path in
            path.addLines(points)
            path.closeSubpath()
        }
        .fill(Color.accentColor.opacity(0.12))

        Path { path in
            path.addLines(points)
            path.closeSubpath()
        }
        .stroke(Color.accentColor, lineWidth: 2)
    }

    /// 四个角手柄。手势挂在整块画布上，这里只负责画出来并给出可访问标识。
    private func handles(in size: CGSize) -> some View {
        ForEach(Self.cornerOrder, id: \.self) { corner in
            Circle()
                .fill(Color.white)
                .overlay(Circle().stroke(Color.accentColor, lineWidth: 3))
                .frame(width: 26, height: 26)
                .shadow(radius: 2)
                .position(screenPoint(adjustment.position(of: corner), in: size))
                .accessibilityIdentifier("scanReviewHandle-\(corner.rawValue)")
        }
    }

    // MARK: - 手势

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard size.width > 0, size.height > 0 else { return }

                if activeCorner == nil {
                    // 只有从某个角附近起拖才开始编辑；点在四边形中间或画布别处不做任何改动。
                    let start = normalized(from: value.startLocation, in: size)
                    guard let corner = adjustment.hitTest(start) else { return }
                    activeCorner = corner
                    // 基准取该角的当前位置而非手指落点：轻点一下不会让角跳到手指下。
                    dragAnchor = adjustment.position(of: corner)
                }

                guard let corner = activeCorner, let anchor = dragAnchor else { return }
                // 以起点为基准叠加位移，手指按下点与角心不重合时手柄不会先跳一下。
                let target = CGPoint(
                    x: anchor.x + value.translation.width / size.width,
                    y: anchor.y - value.translation.height / size.height
                )
                onMove(corner, target)
            }
            .onEnded { _ in
                activeCorner = nil
                dragAnchor = nil
            }
    }

    // MARK: - 坐标换算

    /// 归一化（原点左下、y 轴向上）→ 屏幕点（原点左上、y 轴向下）。
    private func screenPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: (1 - point.y) * size.height)
    }

    /// 屏幕点 → 归一化（原点左下、y 轴向上）。
    private func normalized(from point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x / size.width, y: 1 - point.y / size.height)
    }

    /// 画布宽高比锁定为图片宽高比；图片无法解码时退化为常见名片的横向比例。
    private var displayAspectRatio: CGFloat {
        guard let image = UIImage(data: imageData), image.size.height > 0 else { return 9.0 / 5.0 }
        return image.size.width / image.size.height
    }
}
