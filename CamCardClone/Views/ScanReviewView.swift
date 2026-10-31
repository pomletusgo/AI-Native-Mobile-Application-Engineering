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
    /// 拖拽、命中测试与合法性判定已由 `CardBoundaryAdjustment` 与
    /// `ScanReviewViewModel` 落地并有单测覆盖；本页当前只接线「进入 / 确认 / 放弃」，
    /// 四个角的拖拽手柄属手势 UI，待有 Mac 真机时补充（见 `docs/UI验收清单.md`）。
    private var adjustingBoundaryContent: some View {
        VStack(spacing: 20) {
            imagePreview

            Text("请框出名片所在的区域。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("scanReviewAdjustHint")

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
