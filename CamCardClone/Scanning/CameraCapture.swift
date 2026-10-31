import AVFoundation
import Foundation

/// 拍摄阶段可预期的失败。
enum CameraCaptureError: LocalizedError, Equatable {
    /// 设备上没有可用的后置摄像头（例如模拟器），或采集会话无法建立。
    case deviceUnavailable
    /// 拍照过程本身报错。
    case captureFailed(reason: String)
    /// 拍照完成但没有拿到图像数据。
    case emptyPhotoData

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable:
            return "无法打开相机，请改用相册导入名片照片。"
        case .captureFailed(let reason):
            return "拍摄失败：\(reason)"
        case .emptyPhotoData:
            return "拍摄没有产出照片，请重拍一次。"
        }
    }
}

/// 拍摄一张照片的能力。
///
/// 抽成协议是为了让「查权限 → 按需申请 → 拍摄」这段编排能脱离真实相机单测；
/// 真实实现见 `AVCapturePhotoCapturer`。
protocol CameraCapturing: AnyObject {
    /// 拍摄一张照片，返回图像数据（JPEG）。失败时抛 `CameraCaptureError`。
    func capturePhotoData() async throws -> Data
}

/// 一次拍摄动作的结果。
enum ScanCaptureOutcome: Equatable {
    /// 已拍到照片，可进入名片区域检测。
    case captured(Data)
    /// 没有相机权限，调用方应提示用户并引导到系统设置，随后返回名片夹（规格 E1）。
    case permissionDenied
    /// 拍摄失败，调用方应给出重试入口，且不得进入识别流程。
    case failed(CameraCaptureError)
}

/// 把「查权限 → 按需申请 → 拍摄」串成一次可单测的调用。
///
/// 与 `ScanAccessCoordinator` 的分工：后者只判断「能不能访问」，这里在获准之后真正拍一张。
enum ScanCaptureCoordinator {

    /// 拍摄一张照片。
    ///
    /// 权限未获批准时直接返回 `.permissionDenied`，**不触碰相机**——在无权限的情况下
    /// 启动采集会话不会成功，还会额外触发一次系统层访问。
    static func capture(
        using provider: ScanAuthorizationProviding,
        camera: CameraCapturing
    ) async -> ScanCaptureOutcome {
        let decision = await ScanAccessCoordinator.prepare(for: .camera, using: provider)
        guard decision == .proceed else {
            return .permissionDenied
        }

        do {
            return .captured(try await camera.capturePhotoData())
        } catch let error as CameraCaptureError {
            return .failed(error)
        } catch {
            return .failed(.captureFailed(reason: error.localizedDescription))
        }
    }
}

/// 基于 AVFoundation 的取景与拍摄实现。
///
/// 取景（预览层）与拍摄共用同一个采集会话：预览层挂载 `previewSession`，
/// 拍摄走 `capturePhotoData()`。会话在进入取景页面时启动、离开时停止，
/// 避免摄像头被长期占用。
///
/// 采集会话的配置与启停都放在私有串行队列上执行：`AVCaptureSession` 的操作是阻塞的，
/// 在主线程序列上做会卡住界面。
final class AVCapturePhotoCapturer: NSObject, CameraCapturing {

    /// 供预览层挂载的采集会话。
    let previewSession = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.example.camcardclone.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private var isConfigured = false
    private var pendingCapture: CheckedContinuation<Data, Error>?

    /// 配置并启动取景。没有可用摄像头（例如模拟器）时抛 `.deviceUnavailable`。
    func startPreview() throws {
        try sessionQueue.sync {
            try configureIfNeeded()
            if !previewSession.isRunning {
                previewSession.startRunning()
            }
        }
    }

    /// 停止取景，释放摄像头。
    func stopPreview() {
        sessionQueue.async {
            guard self.previewSession.isRunning else { return }
            self.previewSession.stopRunning()
        }
    }

    func capturePhotoData() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    try self.configureIfNeeded()
                    if !self.previewSession.isRunning {
                        self.previewSession.startRunning()
                    }
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                self.pendingCapture = continuation
                self.photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    /// 首次使用时按需配置：没有摄像头就不建会话，直接把失败上报给调用方。
    private func configureIfNeeded() throws {
        guard !isConfigured else { return }
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        else {
            throw CameraCaptureError.deviceUnavailable
        }

        previewSession.beginConfiguration()
        defer { previewSession.commitConfiguration() }
        previewSession.sessionPreset = .photo

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw CameraCaptureError.captureFailed(reason: error.localizedDescription)
        }
        guard previewSession.canAddInput(input), previewSession.canAddOutput(photoOutput) else {
            throw CameraCaptureError.deviceUnavailable
        }

        previewSession.addInput(input)
        previewSession.addOutput(photoOutput)
        isConfigured = true
    }
}

extension AVCapturePhotoCapturer: AVCapturePhotoCaptureDelegate {

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let continuation = pendingCapture
        pendingCapture = nil

        if let error {
            continuation?.resume(
                throwing: CameraCaptureError.captureFailed(reason: error.localizedDescription)
            )
        } else if let data = photo.fileDataRepresentation(), !data.isEmpty {
            continuation?.resume(returning: data)
        } else {
            continuation?.resume(throwing: CameraCaptureError.emptyPhotoData)
        }

        stopPreview()
    }
}
