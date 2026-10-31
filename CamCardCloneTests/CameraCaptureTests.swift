import XCTest
@testable import CamCardClone

/// `CameraCapture` 相关单元测试。
///
/// 覆盖 card-scanner 的拍摄路径：权限获准后拍一张照片（T04）、权限被拒时不触碰相机
/// 而是提示并返回（E1 / T03 / T20），以及拍摄本身失败时的错误映射。
///
/// 真实的取景画面、快门与系统权限弹窗依赖真机，属人工验收（见 `docs/UI验收清单.md`）；
/// 这里穷举的是「权限 → 拍摄 → 结果」这段顺序逻辑与错误文案。
final class CameraCaptureTests: XCTestCase {

    // MARK: - 替身

    /// 可控的授权状态替身，用来驱动「先查询、再申请、申请后状态改变」的流程。
    private final class StubAuthorizationProvider: ScanAuthorizationProviding {

        private var statuses: [ScanImageSource: ScanAuthorizationStatus]
        private let statusAfterRequest: [ScanImageSource: ScanAuthorizationStatus]
        private(set) var requestedSources: [ScanImageSource] = []

        init(
            statuses: [ScanImageSource: ScanAuthorizationStatus],
            statusAfterRequest: [ScanImageSource: ScanAuthorizationStatus] = [:]
        ) {
            self.statuses = statuses
            self.statusAfterRequest = statusAfterRequest
        }

        func status(for source: ScanImageSource) -> ScanAuthorizationStatus {
            statuses[source] ?? .notDetermined
        }

        func requestAccess(for source: ScanImageSource) async -> ScanAuthorizationStatus {
            requestedSources.append(source)
            if let after = statusAfterRequest[source] {
                statuses[source] = after
            }
            return status(for: source)
        }
    }

    /// 可控的相机替身：返回预设结果，并记录被调用次数。
    private final class StubCamera: CameraCapturing {

        private let result: Result<Data, Error>
        private(set) var captureCount = 0

        init(result: Result<Data, Error>) {
            self.result = result
        }

        func capturePhotoData() async throws -> Data {
            captureCount += 1
            return try result.get()
        }
    }

    /// 相机之外的意外错误，用来验证兜底映射。
    private struct UnexpectedError: LocalizedError {
        var errorDescription: String? { "底层出错" }
    }

    private let photoBytes = Data([0xFF, 0xD8, 0xFF, 0xE0])

    // MARK: - 正常路径

    /// T04：已授权时拍摄一次，照片原样交回上层进入识别流程。
    func testAuthorizedCaptureReturnsPhotoBytes() async {
        let provider = StubAuthorizationProvider(statuses: [.camera: .authorized])
        let camera = StubCamera(result: .success(photoBytes))

        let outcome = await ScanCaptureCoordinator.capture(using: provider, camera: camera)

        XCTAssertEqual(outcome, .captured(photoBytes))
        XCTAssertEqual(camera.captureCount, 1)
    }

    /// 未决 → 申请 → 用户同意 → 拍摄；申请只针对相机。
    func testCaptureRequestsCameraPermissionWhenUndetermined() async {
        let provider = StubAuthorizationProvider(
            statuses: [.camera: .notDetermined],
            statusAfterRequest: [.camera: .authorized]
        )
        let camera = StubCamera(result: .success(photoBytes))

        let outcome = await ScanCaptureCoordinator.capture(using: provider, camera: camera)

        XCTAssertEqual(outcome, .captured(photoBytes))
        XCTAssertEqual(provider.requestedSources, [.camera])
        XCTAssertEqual(camera.captureCount, 1)
    }

    // MARK: - 权限被拒（E1 / T03 / T20）

    /// 已被拒绝时直接返回「权限被拒」，不申请、不拍摄。
    func testDeniedPermissionNeverTouchesCamera() async {
        let provider = StubAuthorizationProvider(statuses: [.camera: .denied])
        let camera = StubCamera(result: .success(photoBytes))

        let outcome = await ScanCaptureCoordinator.capture(using: provider, camera: camera)

        XCTAssertEqual(outcome, .permissionDenied)
        XCTAssertTrue(provider.requestedSources.isEmpty, "已被拒绝时系统不会再弹窗，不应发起申请")
        XCTAssertEqual(camera.captureCount, 0, "无权限时不应启动采集会话")
    }

    /// 未决 → 申请 → 用户拒绝：仍不得触碰相机。
    func testDeniedAfterRequestNeverTouchesCamera() async {
        let provider = StubAuthorizationProvider(
            statuses: [.camera: .notDetermined],
            statusAfterRequest: [.camera: .denied]
        )
        let camera = StubCamera(result: .success(photoBytes))

        let outcome = await ScanCaptureCoordinator.capture(using: provider, camera: camera)

        XCTAssertEqual(outcome, .permissionDenied)
        XCTAssertEqual(provider.requestedSources, [.camera])
        XCTAssertEqual(camera.captureCount, 0)
    }

    /// 被系统限制（如家长控制）时同样只能提示，无法在设置里自行放开。
    func testRestrictedPermissionNeverTouchesCamera() async {
        let provider = StubAuthorizationProvider(statuses: [.camera: .restricted])
        let camera = StubCamera(result: .success(photoBytes))

        let outcome = await ScanCaptureCoordinator.capture(using: provider, camera: camera)

        XCTAssertEqual(outcome, .permissionDenied)
        XCTAssertEqual(camera.captureCount, 0)
    }

    // MARK: - 拍摄失败

    /// 模拟器等没有摄像头的环境：上报「设备不可用」，而不是静默失败。
    func testDeviceUnavailableBecomesFailure() async {
        let provider = StubAuthorizationProvider(statuses: [.camera: .authorized])
        let camera = StubCamera(result: .failure(CameraCaptureError.deviceUnavailable))

        let outcome = await ScanCaptureCoordinator.capture(using: provider, camera: camera)

        XCTAssertEqual(outcome, .failed(.deviceUnavailable))
        XCTAssertEqual(camera.captureCount, 1)
    }

    /// 拍照过程报错时保留原因，便于在界面上如实说明。
    func testCaptureFailureKeepsReason() async {
        let provider = StubAuthorizationProvider(statuses: [.camera: .authorized])
        let camera = StubCamera(result: .failure(CameraCaptureError.captureFailed(reason: "传感器超时")))

        let outcome = await ScanCaptureCoordinator.capture(using: provider, camera: camera)

        XCTAssertEqual(outcome, .failed(.captureFailed(reason: "传感器超时")))
    }

    func testEmptyPhotoBecomesFailure() async {
        let provider = StubAuthorizationProvider(statuses: [.camera: .authorized])
        let camera = StubCamera(result: .failure(CameraCaptureError.emptyPhotoData))

        let outcome = await ScanCaptureCoordinator.capture(using: provider, camera: camera)

        XCTAssertEqual(outcome, .failed(.emptyPhotoData))
    }

    /// 相机实现抛出的非预期错误要兜底成「拍摄失败」，不能漏出去中断流程。
    func testUnexpectedErrorIsWrappedAsCaptureFailure() async {
        let provider = StubAuthorizationProvider(statuses: [.camera: .authorized])
        let camera = StubCamera(result: .failure(UnexpectedError()))

        let outcome = await ScanCaptureCoordinator.capture(using: provider, camera: camera)

        guard case .failed(.captureFailed(let reason)) = outcome else {
            return XCTFail("非预期错误应兜底为拍摄失败，实际为 \(outcome)")
        }
        XCTAssertTrue(reason.contains("底层出错"), "应保留底层描述，便于排查，实际为 \(reason)")
    }

    // MARK: - 错误文案

    /// 没有摄像头时提示改用相册，给出可执行的下一步。
    func testDeviceUnavailableSuggestsAlbumFallback() {
        let description = CameraCaptureError.deviceUnavailable.errorDescription
        XCTAssertEqual(description, "无法打开相机，请改用相册导入名片照片。")
        XCTAssertTrue(description?.contains("相册") == true)
    }

    func testCaptureFailureDescriptionIncludesReason() {
        XCTAssertEqual(
            CameraCaptureError.captureFailed(reason: "传感器超时").errorDescription,
            "拍摄失败：传感器超时"
        )
    }

    /// 拍完没拿到图时提示重拍，而不是把空图当成有效照片。
    func testEmptyPhotoSuggestsRetake() {
        let description = CameraCaptureError.emptyPhotoData.errorDescription
        XCTAssertEqual(description, "拍摄没有产出照片，请重拍一次。")
        XCTAssertTrue(description?.contains("重拍") == true)
    }

    /// 三种失败都要有可读文案，界面上不得出现空白提示。
    func testEveryCaptureErrorHasDescription() {
        let errors: [CameraCaptureError] = [
            .deviceUnavailable,
            .captureFailed(reason: "传感器超时"),
            .emptyPhotoData
        ]
        for error in errors {
            XCTAssertFalse(
                error.errorDescription?.isEmpty ?? true,
                "\(error) 缺少可见的错误描述"
            )
        }
    }
}
