import Foundation
import PhotosUI

/// 扫描入口页（P02 拍摄取景）的状态机。
///
/// 本层把已经实现的三段能力接到界面上：权限适配层（`ScanAuthorization`）、
/// 相机拍摄（`CameraCapture`）与相册导入（`PhotoImport`）。它只负责
/// 「推进权限 → 拿到一张图片 → 收进 `ScanSession`」，并把三条异常路径
/// （E1 相机权限拒绝、E2 相册权限拒绝、E3 取消/重拍）收敛成可断言的状态；
/// 区域检测、OCR、字段抽取与人工确认属于后续段落（P03–P05）。
///
/// 权限适配层、相机与相册读取都以协议注入，因此「权限被拒时不触碰相机」
/// 这类真机上难以复现的分支可以脱离系统弹窗单测。
@MainActor
final class ScannerEntryViewModel: ObservableObject {

    /// 权限被拒时展示给用户的提示。
    struct AccessPrompt: Equatable {
        /// 被拒的是相机还是相册，决定文案与后续引导。
        let source: ScanImageSource
        let title: String
        let message: String
    }

    /// 页面阶段。
    enum Phase: Equatable {
        /// 取景或选择来源。
        case idle
        /// 已拿到一张待识别的图片。
        case captured
    }

    @Published private(set) var phase: Phase = .idle
    /// 本次扫描的产物（图片来源、原始图与校正图）。取消时整体清空（规格 E3）。
    @Published private(set) var session = ScanSession()
    @Published private(set) var accessPrompt: AccessPrompt?
    @Published private(set) var failureMessage: String?
    /// 拍摄或读取照片期间为 true，供界面禁用重复点击。
    @Published private(set) var isWorking = false

    private let authorizationProvider: ScanAuthorizationProviding
    private let camera: CameraCapturing
    private let importer: PhotoImporting

    init(
        authorizationProvider: ScanAuthorizationProviding,
        camera: CameraCapturing,
        importer: PhotoImporting
    ) {
        self.authorizationProvider = authorizationProvider
        self.camera = camera
        self.importer = importer
    }

    // MARK: - 进入页面

    /// 查询相机权限，必要时发起一次申请。返回是否可以直接展示取景画面。
    ///
    /// 返回 false 时 `accessPrompt` 已被填好，界面应提示用户并允许返回名片夹（规格 E1）。
    @discardableResult
    func prepareCamera() async -> Bool {
        let decision = await ScanAccessCoordinator.prepare(for: .camera, using: authorizationProvider)
        guard decision == .proceed else {
            presentAccessPrompt(for: .camera)
            return false
        }
        return true
    }

    // MARK: - 拍摄

    /// 拍摄一张照片。权限未获批准时只给提示，**不触碰相机**（规格 E1）。
    func capturePhoto() async {
        isWorking = true
        defer { isWorking = false }

        switch await ScanCaptureCoordinator.capture(using: authorizationProvider, camera: camera) {
        case .captured(let imageData):
            accept(imageData: imageData, from: .camera)
        case .permissionDenied:
            presentAccessPrompt(for: .camera)
        case .failed(let error):
            failureMessage = error.errorDescription
        }
    }

    // MARK: - 相册导入

    /// 打开相册选择器之前确认权限。返回是否应当继续打开选择器（规格 E2）。
    ///
    /// 这里只查询状态、不主动申请：`PhotosPicker` 本身不需要相册读写授权，
    /// 若顺手发起申请，用户会看到一个与当前操作无关的系统弹窗。
    func prepareImport() -> Bool {
        guard authorizationProvider.status(for: .photoLibrary).requiresSettingsPrompt else {
            return true
        }
        presentAccessPrompt(for: .photoLibrary)
        return false
    }

    /// 选择器回调：读取选中照片并收进本次会话。
    func importPhoto(from item: PhotosPickerItem) async {
        isWorking = true
        defer { isWorking = false }

        do {
            let imageData = try await importer.importedImageData(from: item)
            accept(imageData: imageData, from: .photoLibrary)
        } catch {
            failureMessage = Self.readableMessage(for: error)
        }
    }

    // MARK: - 清理

    /// 重拍与取消共用：丢弃临时图片与来源，回到取景（规格 E3）。
    ///
    /// 是否关闭本页由界面决定——重拍留在本页，取消则返回名片夹。
    func discardCapture() {
        session.cancel()
        phase = .idle
        failureMessage = nil
        accessPrompt = nil
    }

    func dismissAccessPrompt() {
        accessPrompt = nil
    }

    func dismissFailure() {
        failureMessage = nil
    }

    // MARK: - 内部

    private func accept(imageData: Data, from source: ScanImageSource) {
        session.capture(imageData: imageData, from: source)
        failureMessage = nil
        phase = .captured
    }

    private func presentAccessPrompt(for source: ScanImageSource) {
        accessPrompt = AccessPrompt(
            source: source,
            title: source.permissionDeniedTitle,
            message: source.permissionDeniedMessage
        )
    }

    /// 导入失败时取错误自带的文案；非预期错误也要给出可读提示，不留空白弹窗。
    private static func readableMessage(for error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
            return localized
        }
        return "无法读取所选照片，请换一张或改用相机拍摄。"
    }
}
