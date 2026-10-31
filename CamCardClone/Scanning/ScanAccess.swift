import Foundation

/// 拍摄或从相册导入。
///
/// 两者在权限、提示文案与重试措辞上都不同，因此显式区分来源，而不是用布尔量传递。
enum ScanImageSource: Hashable {
    case camera
    case photoLibrary

    /// 中文名，用于提示文案。
    var displayName: String {
        switch self {
        case .camera: return "相机"
        case .photoLibrary: return "相册"
        }
    }
}

/// 访问相机或相册的授权状态。
///
/// 刻意不直接复用 `AVAuthorizationStatus` / `PHAuthorizationStatus`：它们来自
/// AVFoundation / Photos，在纯逻辑单测里无法构造。这里用等价的本地枚举，把
/// 「状态 → 下一步动作」做成可单测的纯函数；真实状态由适配层做一对一转换。
enum ScanAuthorizationStatus: Equatable {
    /// 尚未询问过用户。
    case notDetermined
    /// 已授权。相册的「仅选中项」（`PHAuthorizationStatus.limited`）也归入此档，因为访问可用。
    case authorized
    /// 用户已明确拒绝。
    case denied
    /// 被系统限制（如家长控制），用户无法在设置里自行放开。
    case restricted
}

/// 拿到授权状态后，扫描流程该做什么。
enum ScanAccessDecision: Equatable {
    /// 已授权，继续当前操作（打开取景器或进入相册选择）。
    case proceed
    /// 尚未决定，需要向系统发起一次授权请求。
    case requestAuthorization
    /// 被拒或被限制，需要提示用户并引导到系统设置，随后返回名片夹。
    case promptForSettings
}

extension ScanAuthorizationStatus {

    /// 状态到下一步动作的映射，覆盖 E1（相机权限拒绝）与 E2（相册权限拒绝）。
    var decision: ScanAccessDecision {
        switch self {
        case .authorized:
            return .proceed
        case .notDetermined:
            return .requestAuthorization
        case .denied, .restricted:
            return .promptForSettings
        }
    }

    /// 是否需要弹出「去设置」提示。
    var requiresSettingsPrompt: Bool {
        decision == .promptForSettings
    }
}

extension ScanImageSource {

    /// 权限被拒时的提示标题。
    var permissionDeniedTitle: String {
        "无法访问\(displayName)"
    }

    /// 权限被拒时的提示正文：说明用途并引导到系统设置。
    var permissionDeniedMessage: String {
        switch self {
        case .camera:
            return "请在「设置 → 隐私与安全性 → 相机」中允许本应用访问相机，然后返回重试；也可以改用相册导入名片照片。"
        case .photoLibrary:
            return "请在「设置 → 隐私与安全性 → 照片」中允许本应用访问相册，然后返回重试。"
        }
    }
}

/// 一次扫描会话的产物。
///
/// 规格 E3 要求「取消/返回不得产生脏数据」，因此把「图片来源」「已拍摄的原始图」
/// 与「已校正的图」收进一个值类型，取消时整体清空，避免零散状态残留到下一次进入。
struct ScanSession: Equatable {

    private(set) var source: ScanImageSource?
    private(set) var capturedImageData: Data?
    private(set) var correctedImageData: Data?

    init() {
        self.source = nil
        self.capturedImageData = nil
        self.correctedImageData = nil
    }

    /// 是否已经产出一张可进入识别流程的图。
    var hasCorrectedImage: Bool {
        correctedImageData != nil
    }

    /// 记录一次拍摄或导入。新图会让上一次的校正结果失效，避免新旧图混用。
    mutating func capture(imageData: Data, from source: ScanImageSource) {
        self.source = source
        self.capturedImageData = imageData
        self.correctedImageData = nil
    }

    /// 记录透视校正后的图。没有原始图时直接忽略，避免凭空产生结果。
    mutating func applyCorrection(imageData: Data) {
        guard capturedImageData != nil else { return }
        correctedImageData = imageData
    }

    /// 取消或重拍：清空全部产物。
    mutating func cancel() {
        source = nil
        capturedImageData = nil
        correctedImageData = nil
    }
}
