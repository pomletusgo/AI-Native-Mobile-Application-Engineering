import PhotosUI
import SwiftUI
import XCTest
@testable import CamCardClone

/// `ScannerEntryViewModel` 单元测试。
///
/// 覆盖扫描入口页的 T02（进入页面推进权限）、T03 / E1（相机权限被拒只提示、不触碰相机）、
/// T04（拍摄后图片进入会话）、T05 / E2（相册导入与相册权限被拒）以及 E3（取消/重拍不留脏数据）。
///
/// 取景画面、快门、系统权限弹窗与「跳转设置」依赖真机，属人工验收（见 `docs/UI验收清单.md`）。
@MainActor
final class ScannerEntryViewModelTests: XCTestCase {

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

        var result: Result<Data, Error>
        private(set) var captureCount = 0

        init(result: Result<Data, Error>) {
            self.result = result
        }

        func capturePhotoData() async throws -> Data {
            captureCount += 1
            return try result.get()
        }
    }

    /// 可控的相册读取替身。
    private final class StubImporter: PhotoImporting {

        var result: Result<Data, Error>
        private(set) var importCount = 0

        init(result: Result<Data, Error>) {
            self.result = result
        }

        func importedImageData(from item: PhotosPickerItem) async throws -> Data {
            importCount += 1
            return try result.get()
        }
    }

    /// 预期之外的错误，用来验证兜底文案。
    private struct UnexpectedError: LocalizedError {
        var errorDescription: String? { "底层出错" }
    }

    // MARK: - 测试夹具

    private struct Harness {
        let model: ScannerEntryViewModel
        let provider: StubAuthorizationProvider
        let camera: StubCamera
        let importer: StubImporter
    }

    private let photoBytes = Data([0xFF, 0xD8, 0xFF, 0xE0])

    private func makeHarness(
        statuses: [ScanImageSource: ScanAuthorizationStatus],
        statusAfterRequest: [ScanImageSource: ScanAuthorizationStatus] = [:],
        cameraResult: Result<Data, Error>? = nil,
        importResult: Result<Data, Error>? = nil
    ) -> Harness {
        let provider = StubAuthorizationProvider(
            statuses: statuses,
            statusAfterRequest: statusAfterRequest
        )
        let camera = StubCamera(result: cameraResult ?? .success(photoBytes))
        let importer = StubImporter(result: importResult ?? .success(photoBytes))
        let model = ScannerEntryViewModel(
            authorizationProvider: provider,
            camera: camera,
            importer: importer
        )
        return Harness(model: model, provider: provider, camera: camera, importer: importer)
    }

    /// 测试用选择器条目；相册读取本身由替身承担，条目的内容无关紧要。
    private func makePickerItem() -> PhotosPickerItem {
        PhotosPickerItem(itemIdentifier: "unit-test-item")
    }

    // MARK: - T02 / T03：进入页面的相机权限推进

    func testPrepareCameraProceedsWhenAuthorized() async {
        let harness = makeHarness(statuses: [.camera: .authorized])

        let canShowPreview = await harness.model.prepareCamera()

        XCTAssertTrue(canShowPreview)
        XCTAssertNil(harness.model.accessPrompt)
        XCTAssertTrue(harness.provider.requestedSources.isEmpty, "已授权时不应再发起申请")
    }

    func testPrepareCameraRequestsAccessWhenUndetermined() async {
        let harness = makeHarness(
            statuses: [.camera: .notDetermined],
            statusAfterRequest: [.camera: .authorized]
        )

        let canShowPreview = await harness.model.prepareCamera()

        XCTAssertTrue(canShowPreview)
        XCTAssertEqual(harness.provider.requestedSources, [.camera])
        XCTAssertNil(harness.model.accessPrompt)
    }

    /// E1：已被拒绝时给出提示并引导到设置，同时不展示取景。
    func testPrepareCameraPromptsWhenDenied() async {
        let harness = makeHarness(statuses: [.camera: .denied])

        let canShowPreview = await harness.model.prepareCamera()

        XCTAssertFalse(canShowPreview)
        XCTAssertEqual(harness.model.accessPrompt?.source, .camera)
        XCTAssertEqual(harness.model.accessPrompt?.title, "无法访问相机")
        XCTAssertTrue(harness.model.accessPrompt?.message.contains("设置") == true)
        XCTAssertTrue(harness.provider.requestedSources.isEmpty)
    }

    /// 未决 → 申请 → 用户拒绝：仍然只能提示，不能展示取景。
    func testPrepareCameraPromptsWhenDeniedAfterRequest() async {
        let harness = makeHarness(
            statuses: [.camera: .notDetermined],
            statusAfterRequest: [.camera: .denied]
        )

        let canShowPreview = await harness.model.prepareCamera()

        XCTAssertFalse(canShowPreview)
        XCTAssertEqual(harness.provider.requestedSources, [.camera])
        XCTAssertEqual(harness.model.accessPrompt?.source, .camera)
    }

    /// 被系统限制（如家长控制）时同样只能提示，且不应浪费一次系统申请。
    func testPrepareCameraPromptsWhenRestrictedWithoutRequesting() async {
        let harness = makeHarness(statuses: [.camera: .restricted])

        let canShowPreview = await harness.model.prepareCamera()

        XCTAssertFalse(canShowPreview)
        XCTAssertEqual(harness.model.accessPrompt?.source, .camera)
        XCTAssertTrue(harness.provider.requestedSources.isEmpty)
    }

    // MARK: - E2：相册权限

    func testPrepareImportAllowsPickerWhenAuthorized() {
        let harness = makeHarness(statuses: [.photoLibrary: .authorized])

        XCTAssertTrue(harness.model.prepareImport())
        XCTAssertNil(harness.model.accessPrompt)
        XCTAssertTrue(harness.provider.requestedSources.isEmpty)
    }

    /// 未决时也直接打开选择器：`PhotosPicker` 不需要相册读写授权，不弹无关的系统弹窗。
    func testPrepareImportAllowsPickerWhenUndeterminedWithoutRequesting() {
        let harness = makeHarness(statuses: [.photoLibrary: .notDetermined])

        XCTAssertTrue(harness.model.prepareImport())
        XCTAssertNil(harness.model.accessPrompt)
        XCTAssertTrue(harness.provider.requestedSources.isEmpty)
    }

    func testPrepareImportPromptsWhenDenied() {
        let harness = makeHarness(statuses: [.photoLibrary: .denied])

        XCTAssertFalse(harness.model.prepareImport())
        XCTAssertEqual(harness.model.accessPrompt?.source, .photoLibrary)
        XCTAssertEqual(harness.model.accessPrompt?.title, "无法访问相册")
        XCTAssertTrue(harness.model.accessPrompt?.message.contains("设置") == true)
    }

    // MARK: - T04：拍摄

    func testCaptureStoresImageFromCamera() async {
        let harness = makeHarness(statuses: [.camera: .authorized])

        await harness.model.capturePhoto()

        XCTAssertEqual(harness.model.phase, .captured)
        XCTAssertEqual(harness.model.session.source, .camera)
        XCTAssertEqual(harness.model.session.capturedImageData, photoBytes)
        XCTAssertFalse(harness.model.session.hasCorrectedImage)
        XCTAssertEqual(harness.camera.captureCount, 1)
        XCTAssertNil(harness.model.failureMessage)
    }

    /// E1 / T20：无相机权限时点拍摄只提示，不启动采集会话。
    func testCaptureWhenDeniedPromptsAndNeverTouchesCamera() async {
        let harness = makeHarness(statuses: [.camera: .denied])

        await harness.model.capturePhoto()

        XCTAssertEqual(harness.model.accessPrompt?.source, .camera)
        XCTAssertEqual(harness.camera.captureCount, 0, "无权限时不应启动采集会话")
        XCTAssertEqual(harness.model.phase, .idle)
        XCTAssertNil(harness.model.session.capturedImageData)
        XCTAssertNil(harness.model.session.source)
    }

    /// 模拟器等没有摄像头的环境：如实报错，不留空白页。
    func testCaptureFailureSurfacesReason() async {
        let harness = makeHarness(
            statuses: [.camera: .authorized],
            cameraResult: .failure(CameraCaptureError.deviceUnavailable)
        )

        await harness.model.capturePhoto()

        XCTAssertEqual(harness.model.failureMessage, "无法打开相机，请改用相册导入名片照片。")
        XCTAssertEqual(harness.model.phase, .idle)
        XCTAssertNil(harness.model.session.capturedImageData)
    }

    /// 上一次失败后再拍成功，提示应被清掉。
    func testCaptureClearsEarlierFailure() async {
        let harness = makeHarness(
            statuses: [.camera: .authorized],
            cameraResult: .failure(CameraCaptureError.emptyPhotoData)
        )
        await harness.model.capturePhoto()
        XCTAssertNotNil(harness.model.failureMessage)

        harness.camera.result = .success(photoBytes)
        await harness.model.capturePhoto()

        XCTAssertNil(harness.model.failureMessage)
        XCTAssertEqual(harness.model.phase, .captured)
    }

    // MARK: - T05：相册导入

    func testImportStoresImageFromPhotoLibrary() async {
        let harness = makeHarness(statuses: [.photoLibrary: .authorized])

        await harness.model.importPhoto(from: makePickerItem())

        XCTAssertEqual(harness.model.phase, .captured)
        XCTAssertEqual(harness.model.session.source, .photoLibrary)
        XCTAssertEqual(harness.model.session.capturedImageData, photoBytes)
        XCTAssertEqual(harness.importer.importCount, 1)
        XCTAssertNil(harness.model.failureMessage)
    }

    func testImportFailureSurfacesMessageAndKeepsSessionEmpty() async {
        let harness = makeHarness(
            statuses: [.photoLibrary: .authorized],
            importResult: .failure(PhotoImportError.unreadableItem)
        )

        await harness.model.importPhoto(from: makePickerItem())

        XCTAssertEqual(harness.model.failureMessage, PhotoImportError.unreadableItem.errorDescription)
        XCTAssertEqual(harness.model.phase, .idle)
        XCTAssertNil(harness.model.session.capturedImageData)
        XCTAssertNil(harness.model.session.source)
    }

    /// 非预期错误也要有可读文案，不能留空白弹窗。
    func testImportUnexpectedErrorFallsBackToReadableMessage() async {
        let harness = makeHarness(
            statuses: [.photoLibrary: .authorized],
            importResult: .failure(UnexpectedError())
        )

        await harness.model.importPhoto(from: makePickerItem())

        XCTAssertEqual(harness.model.failureMessage, "底层出错")
    }

    // MARK: - E3：取消 / 重拍不留脏数据

    func testDiscardAfterCaptureLeavesNoResidue() async {
        let harness = makeHarness(statuses: [.camera: .authorized])
        await harness.model.capturePhoto()

        harness.model.discardCapture()

        XCTAssertEqual(harness.model.phase, .idle)
        XCTAssertNil(harness.model.session.source)
        XCTAssertNil(harness.model.session.capturedImageData)
        XCTAssertNil(harness.model.session.correctedImageData)
        XCTAssertFalse(harness.model.session.hasCorrectedImage)
    }

    func testDiscardAfterImportLeavesNoResidue() async {
        let harness = makeHarness(statuses: [.photoLibrary: .authorized])
        await harness.model.importPhoto(from: makePickerItem())

        harness.model.discardCapture()

        XCTAssertEqual(harness.model.phase, .idle)
        XCTAssertNil(harness.model.session.source)
        XCTAssertNil(harness.model.session.capturedImageData)
    }

    /// 取消时也可以顺手清掉权限提示，避免回到名片夹后残留弹窗状态。
    func testDiscardClearsAccessPrompt() async {
        let harness = makeHarness(statuses: [.camera: .denied])
        await harness.model.capturePhoto()
        XCTAssertNotNil(harness.model.accessPrompt)

        harness.model.discardCapture()

        XCTAssertNil(harness.model.accessPrompt)
    }

    // MARK: - 提示清理

    func testDismissAccessPromptClearsPrompt() async {
        let harness = makeHarness(statuses: [.camera: .denied])
        await harness.model.prepareCamera()

        harness.model.dismissAccessPrompt()

        XCTAssertNil(harness.model.accessPrompt)
    }

    func testDismissFailureClearsMessage() async {
        let harness = makeHarness(
            statuses: [.camera: .authorized],
            cameraResult: .failure(CameraCaptureError.emptyPhotoData)
        )
        await harness.model.capturePhoto()

        harness.model.dismissFailure()

        XCTAssertNil(harness.model.failureMessage)
    }
}
