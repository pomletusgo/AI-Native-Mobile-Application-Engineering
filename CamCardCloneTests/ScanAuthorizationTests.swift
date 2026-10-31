import AVFoundation
import Photos
import XCTest
@testable import CamCardClone

/// `ScanAuthorization` 与 `PhotoImport` 相关单元测试。
///
/// 覆盖 card-scanner 的权限与导入异常路径：系统授权状态到本应用状态的映射、
/// 「未决 → 申请 → 授权 / 被拒」的推进顺序（E1 相机权限拒绝、E2 相册权限拒绝），
/// 以及相册导入读不出内容时的失败。
///
/// 这些分支在真机上依赖系统弹窗与用户操作，无法稳定复现，因此把顺序逻辑收进
/// `ScanAccessCoordinator` 并用替身驱动，在此穷举验证。真实的系统弹窗、设置跳转
/// 与相册选择器行为属人工验收（见 `docs/UI验收清单.md`）。
final class ScanAuthorizationTests: XCTestCase {

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

    // MARK: - 系统状态映射

    func testCameraMappingCoversEverySystemStatus() {
        XCTAssertEqual(ScanAuthorizationMapping.map(camera: .authorized), .authorized)
        XCTAssertEqual(ScanAuthorizationMapping.map(camera: .notDetermined), .notDetermined)
        XCTAssertEqual(ScanAuthorizationMapping.map(camera: .denied), .denied)
        XCTAssertEqual(ScanAuthorizationMapping.map(camera: .restricted), .restricted)
    }

    /// 相机被拒时必须落到「提示并跳设置」，否则会卡在取景页上无所反馈（E1）。
    func testDeniedCameraLeadsToSettingsPrompt() {
        XCTAssertEqual(ScanAuthorizationMapping.map(camera: .denied).decision, .promptForSettings)
        XCTAssertEqual(ScanAuthorizationMapping.map(camera: .restricted).decision, .promptForSettings)
    }

    func testPhotoLibraryMappingCoversEverySystemStatus() {
        XCTAssertEqual(ScanAuthorizationMapping.map(photoLibrary: .authorized), .authorized)
        XCTAssertEqual(ScanAuthorizationMapping.map(photoLibrary: .notDetermined), .notDetermined)
        XCTAssertEqual(ScanAuthorizationMapping.map(photoLibrary: .denied), .denied)
        XCTAssertEqual(ScanAuthorizationMapping.map(photoLibrary: .restricted), .restricted)
    }

    /// 「仅选中项」够用：本次导入读得到图，不该拦下来去跳设置。
    func testLimitedLibraryAccessCountsAsAuthorized() {
        XCTAssertEqual(ScanAuthorizationMapping.map(photoLibrary: .limited), .authorized)
        XCTAssertEqual(ScanAuthorizationMapping.map(photoLibrary: .limited).decision, .proceed)
    }

    /// 相册被拒时必须落到「提示并跳设置」而不是静默失败（E2）。
    func testDeniedLibraryAccessLeadsToSettingsPrompt() {
        XCTAssertEqual(ScanAuthorizationMapping.map(photoLibrary: .denied), .denied)
        XCTAssertEqual(ScanAuthorizationMapping.map(photoLibrary: .denied).decision, .promptForSettings)
    }

    // MARK: - 推进顺序

    func testPrepareProceedsWhenAlreadyAuthorized() async {
        let provider = StubAuthorizationProvider(statuses: [.photoLibrary: .authorized])
        let decision = await ScanAccessCoordinator.prepare(for: .photoLibrary, using: provider)

        XCTAssertEqual(decision, .proceed)
        XCTAssertTrue(provider.requestedSources.isEmpty, "已授权时不应再发起申请")
    }

    func testPreparePromptsForSettingsWithoutRequestingWhenAlreadyDenied() async {
        let provider = StubAuthorizationProvider(statuses: [.camera: .denied])
        let decision = await ScanAccessCoordinator.prepare(for: .camera, using: provider)

        XCTAssertEqual(decision, .promptForSettings)
        XCTAssertTrue(provider.requestedSources.isEmpty, "已被拒绝时系统不会再弹窗，不应发起申请")
    }

    func testPreparePromptsForSettingsWhenRestricted() async {
        let provider = StubAuthorizationProvider(statuses: [.camera: .restricted])
        let decision = await ScanAccessCoordinator.prepare(for: .camera, using: provider)

        XCTAssertEqual(decision, .promptForSettings)
    }

    /// T03 的正常路径：未决 → 申请 → 用户同意 → 继续。
    func testPrepareProceedsAfterUserGrantsPermission() async {
        let provider = StubAuthorizationProvider(
            statuses: [.camera: .notDetermined],
            statusAfterRequest: [.camera: .authorized]
        )
        let decision = await ScanAccessCoordinator.prepare(for: .camera, using: provider)

        XCTAssertEqual(decision, .proceed)
        XCTAssertEqual(provider.requestedSources, [.camera])
    }

    /// E1 / E2 的拒绝路径：未决 → 申请 → 用户拒绝 → 提示并跳设置。
    func testPreparePromptsForSettingsAfterUserDeniesPermission() async {
        let provider = StubAuthorizationProvider(
            statuses: [.photoLibrary: .notDetermined],
            statusAfterRequest: [.photoLibrary: .denied]
        )
        let decision = await ScanAccessCoordinator.prepare(for: .photoLibrary, using: provider)

        XCTAssertEqual(decision, .promptForSettings)
        XCTAssertEqual(provider.requestedSources, [.photoLibrary])
    }

    /// 只查当前来源的状态：申请相机时不应顺带动到相册。
    func testPrepareOnlyTouchesTheRequestedSource() async {
        let provider = StubAuthorizationProvider(
            statuses: [.camera: .notDetermined, .photoLibrary: .notDetermined],
            statusAfterRequest: [.camera: .authorized, .photoLibrary: .authorized]
        )
        let decision = await ScanAccessCoordinator.prepare(for: .camera, using: provider)

        XCTAssertEqual(decision, .proceed)
        XCTAssertEqual(provider.requestedSources, [.camera])
        XCTAssertEqual(provider.status(for: .photoLibrary), .notDetermined)
    }

    // MARK: - 相册导入的失败

    func testImageDataRejectsNothingLoaded() {
        XCTAssertThrowsError(try PhotosPickerImageImporter.imageData(from: nil)) { error in
            XCTAssertEqual(error as? PhotoImportError, .unreadableItem)
        }
    }

    func testImageDataRejectsEmptyData() {
        XCTAssertThrowsError(try PhotosPickerImageImporter.imageData(from: Data())) { error in
            XCTAssertEqual(error as? PhotoImportError, .emptyImageData)
        }
    }

    func testImageDataPassesThroughValidData() throws {
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        XCTAssertEqual(try PhotosPickerImageImporter.imageData(from: data), data)
    }

    func testPhotoImportErrorDescriptionsAreReadable() {
        XCTAssertEqual(PhotoImportError.unreadableItem.errorDescription, "无法读取所选照片，请换一张或改用相机拍摄。")
        XCTAssertEqual(PhotoImportError.emptyImageData.errorDescription, "所选照片没有内容，请换一张或改用相机拍摄。")
    }

    /// E4：导入读不出内容时提示里要给出下一步动作（换一张或改用相机）。
    func testPhotoImportErrorSuggestsNextStep() {
        XCTAssertTrue(PhotoImportError.unreadableItem.errorDescription?.contains("相机") == true)
    }
}
