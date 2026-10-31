import AVFoundation
import Foundation
import Photos

/// 系统授权状态到 `ScanAuthorizationStatus` 的映射。
///
/// 这一层把 AVFoundation / Photos 的类型挡在业务逻辑之外，映射写成纯函数，
/// 因此「各种系统状态分别意味着什么」可以在没有真机、没有权限弹窗的环境里断言。
enum ScanAuthorizationMapping {

    /// `AVAuthorizationStatus` → `ScanAuthorizationStatus`。
    static func map(camera status: AVAuthorizationStatus) -> ScanAuthorizationStatus {
        switch status {
        case .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .restricted
        }
    }

    /// `PHAuthorizationStatus` → `ScanAuthorizationStatus`。
    ///
    /// - `.limited`（仅选中项）算已授权：选择器可用，本次导入的行为与全量授权一致。
    /// - `.addOnly` 只能写入、不能读取，对「从相册读取图片」这个用途而言等同于不可用，
    ///   因此归入 `.denied`。本应用申请的是 `.readWrite`，正常不会拿到该状态。
    static func map(photoLibrary status: PHAuthorizationStatus) -> ScanAuthorizationStatus {
        switch status {
        case .authorized, .limited:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied, .addOnly:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .restricted
        }
    }
}

/// 查询与申请相机 / 相册授权。
///
/// 抽成协议是为了让上层流程（以及「未决 → 申请 → 被拒」这类分支）能脱离系统弹窗单测。
/// 真实实现见 `SystemScanAuthorizationProvider`。
protocol ScanAuthorizationProviding: AnyObject {
    /// 当前授权状态。只查询，不触发系统弹窗。
    func status(for source: ScanImageSource) -> ScanAuthorizationStatus
    /// 申请授权。只有在状态为「未决」时系统才会弹窗；其它状态直接返回当前状态。
    func requestAccess(for source: ScanImageSource) async -> ScanAuthorizationStatus
}

/// 真实实现：相机走 AVFoundation，相册走 Photos。
final class SystemScanAuthorizationProvider: ScanAuthorizationProviding {

    func status(for source: ScanImageSource) -> ScanAuthorizationStatus {
        switch source {
        case .camera:
            return ScanAuthorizationMapping.map(camera: AVCaptureDevice.authorizationStatus(for: .video))
        case .photoLibrary:
            return ScanAuthorizationMapping.map(photoLibrary: PHPhotoLibrary.authorizationStatus(for: .readWrite))
        }
    }

    func requestAccess(for source: ScanImageSource) async -> ScanAuthorizationStatus {
        switch source {
        case .camera:
            _ = await AVCaptureDevice.requestAccess(for: .video)
        case .photoLibrary:
            _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        // 申请后重新查询，而不是用返回值推断：`.limited` 之类的状态只能从查询里拿到。
        return status(for: source)
    }
}

/// 按授权状态决定是否继续，并在需要时向系统发起申请。
///
/// 把「查询 → 判断 → 按需申请 → 再判断」这段顺序逻辑收成一个可单测的函数：
/// 输入输出都是 `ScanAccessDecision`，不涉及任何 UI 或系统 API。
enum ScanAccessCoordinator {

    /// 推进到下一步。
    ///
    /// 返回 `.promptForSettings` 时调用方应提示用户并返回名片夹；返回 `.proceed` 时才能继续。
    static func prepare(
        for source: ScanImageSource,
        using provider: ScanAuthorizationProviding
    ) async -> ScanAccessDecision {
        switch provider.status(for: source).decision {
        case .proceed:
            return .proceed
        case .promptForSettings:
            return .promptForSettings
        case .requestAuthorization:
            let requested = await provider.requestAccess(for: source)
            return requested.decision
        }
    }
}
