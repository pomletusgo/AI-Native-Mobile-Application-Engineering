import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

/// 扫描名片入口（P02 拍摄取景）。
///
/// Week3 起本页不再是占位：相机权限由 `ScanAuthorization` 推进，取景与快门用
/// `CameraPreviewView` + `AVCapturePhotoCapturer`，相册导入用 `PhotosPicker`；
/// 拍摄或导入得到的图片收进 `ScanSession`，交给后续的检测与识别段落（P03–P05）。
///
/// 页面只做展示与转发意图，状态与异常处理都在 `ScannerEntryViewModel` 里，
/// 因此「权限被拒不触碰相机」「取消不留脏数据」等行为可以脱离真机单测。
struct ScannerEntryView: View {

    /// 保留 `repository` 以维持 `AppRoute.scanner` 的既有契约（design.md D6），
    /// 待「确认 → 保存」接线时在此落库。
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

    // MARK: - 已取得照片

    private var capturedContent: some View {
        VStack(spacing: 20) {
            if let image = capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("scannerCapturedImage")
            }

            Text("已获取名片照片，接下来进入检测与识别。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                model.discardCapture()
            } label: {
                Label("重拍", systemImage: "arrow.counterclockwise")
            }
            .accessibilityIdentifier("scannerRetakeButton")

            Button("取消") {
                leaveToCardHolder()
            }
            .accessibilityIdentifier("scannerCancelButton")
        }
        .padding(24)
    }

    private var capturedImage: UIImage? {
        model.session.capturedImageData.flatMap(UIImage.init(data:))
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
