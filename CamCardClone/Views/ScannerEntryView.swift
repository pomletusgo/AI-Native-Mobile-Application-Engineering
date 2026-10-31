import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

/// 扫描名片入口（P02 拍摄取景）。
///
/// Week3 起本页不再是占位：相机权限由 `ScanAuthorization` 推进，取景与快门用
/// `CameraPreviewView` + `AVCapturePhotoCapturer`，相册导入用 `PhotosPicker`；
/// 拍摄或导入得到的图片收进 `ScanSession`。
///
/// Week4 起拿到图片后交给 `ScanReviewView`，由它完成检测校正、识别、人工逐字段
/// 校正与「确认 → 保存」落库（P03–P05）。
///
/// 页面只做展示与转发意图，状态与异常处理都在 `ScannerEntryViewModel` 里，
/// 因此「权限被拒不触碰相机」「取消不留脏数据」等行为可以脱离真机单测。
struct ScannerEntryView: View {

    /// 名片仓库。维持 `AppRoute.scanner` 的既有契约（design.md D6），
    /// 并由复核页 `ScanReviewView` 在「确认 → 保存」时落库。
    let repository: BusinessCardRepository

    @EnvironmentObject private var router: AppRouter
    @Environment(\.openURL) private var openURL

    @StateObject private var model: ScannerEntryViewModel
    @State private var isPreviewRunning = false
    @State private var isPickerPresented = false
    @State private var pickedItem: PhotosPickerItem?

    private let capturer: AVCapturePhotoCapturer

    init(repository: BusinessCardRepository) {
        self.repository = repository
        let capturer = AVCapturePhotoCapturer()
        self.capturer = capturer
        _model = StateObject(wrappedValue: ScannerEntryViewModel(
            authorizationProvider: SystemScanAuthorizationProvider(),
            camera: capturer,
            importer: PhotosPickerImageImporter()
        ))
    }

    var body: some View {
        // 用 ZStack 固定容器身份，避免阶段切换时 `.task` 被重复触发而重启取景。
        ZStack {
            switch model.phase {
            case .idle:
                idleContent
            case .captured:
                capturedContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("扫描名片")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("scannerEntry")
        .task { await startCameraIfPossible() }
        .onChange(of: model.phase) { _, newPhase in
            switch newPhase {
            case .captured:
                capturer.stopPreview()
                isPreviewRunning = false
            case .idle:
                Task { await startCameraIfPossible() }
            }
        }
        .onChange(of: pickedItem) { _, newItem in
            guard let newItem else { return }
            pickedItem = nil
            Task { await model.importPhoto(from: newItem) }
        }
        .onDisappear { capturer.stopPreview() }
        .photosPicker(isPresented: $isPickerPresented, selection: $pickedItem, matching: .images)
        .alert(alertTitle, isPresented: isAlertPresented) {
            if model.accessPrompt != nil {
                Button("去设置") { openSettings() }
                Button("返回名片夹", role: .cancel) { leaveToCardHolder() }
            } else {
                Button("好", role: .cancel) { model.dismissFailure() }
            }
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - 取景

    private var idleContent: some View {
        VStack(spacing: 0) {
            ZStack {
                if isPreviewRunning {
                    CameraPreviewView(session: capturer.previewSession)
                } else {
                    cameraUnavailablePlaceholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            HStack(spacing: 28) {
                Button {
                    openPicker()
                } label: {
                    Label("相册导入", systemImage: "photo.on.rectangle")
                }
                .disabled(model.isWorking)
                .accessibilityIdentifier("scannerImportButton")

                Button {
                    Task { await model.capturePhoto() }
                } label: {
                    Label("拍摄", systemImage: "camera.aperture")
                }
                .disabled(model.isWorking)
                .accessibilityIdentifier("scannerCaptureButton")

                Button("取消") {
                    leaveToCardHolder()
                }
                .accessibilityIdentifier("scannerCancelButton")
            }
            .font(.subheadline)
            .padding(.vertical, 20)
        }
    }

    private var cameraUnavailablePlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("当前没有可用的相机，请从相册导入名片照片。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    // MARK: - 已取得照片：交给复核页（P03–P05）

    @ViewBuilder
    private var capturedContent: some View {
        if let imageData = model.session.capturedImageData {
            ScanReviewView(
                imageData: imageData,
                repository: repository,
                // 重拍：只丢弃本次照片，留在本页重新取景。
                onRetake: { model.discardCapture() },
                // 取消或保存完成：清空会话产物后返回名片夹。
                onFinish: { leaveToCardHolder() }
            )
        }
    }

    // MARK: - 权限与异常提示

    private var alertTitle: String {
        model.accessPrompt?.title ?? "操作未完成"
    }

    private var alertMessage: String {
        if let prompt = model.accessPrompt {
            return prompt.message
        }
        return model.failureMessage ?? ""
    }

    private var isAlertPresented: Binding<Bool> {
        Binding(
            get: { model.accessPrompt != nil || model.failureMessage != nil },
            set: { isPresented in
                guard !isPresented else { return }
                model.dismissAccessPrompt()
                model.dismissFailure()
            }
        )
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    // MARK: - 动作

    private func startCameraIfPossible() async {
        guard await model.prepareCamera() else {
            isPreviewRunning = false
            return
        }
        do {
            try capturer.startPreview()
            isPreviewRunning = true
        } catch {
            // 模拟器等没有摄像头的环境：留在取景页并提示改用相册。
            isPreviewRunning = false
        }
    }

    private func openPicker() {
        guard model.prepareImport() else { return }
        isPickerPresented = true
    }

    /// 取消或返回：清空本次会话产物后回名片夹，不产生脏数据（规格 E3）。
    private func leaveToCardHolder() {
        model.discardCapture()
        router.pop()
    }
}

#Preview {
    NavigationStack {
        ScannerEntryView(repository: InMemoryBusinessCardRepository())
    }
    .environmentObject(AppRouter())
}
