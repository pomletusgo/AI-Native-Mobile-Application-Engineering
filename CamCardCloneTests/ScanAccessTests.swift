import XCTest
@testable import CamCardClone

/// `ScanAccess` 相关单元测试。
///
/// 覆盖 card-scanner 的相机/相册访问与取消语义：授权状态到下一步动作的映射（E1 相机权限拒绝、
/// E2 相册权限拒绝）、提示文案，以及「取消/返回不产生脏数据」（E3）。
///
/// 这些都是在真机上无法稳定复现的分支，所以把「状态 → 决策」抽成纯函数在此穷举验证；
/// 真实的权限弹窗与系统设置跳转属人工验收（见 `docs/UI验收清单.md`）。
final class ScanAccessTests: XCTestCase {

    // MARK: - 授权状态 → 决策

    func testAuthorizedProceeds() {
        XCTAssertEqual(ScanAuthorizationStatus.authorized.decision, .proceed)
    }

    func testNotDeterminedRequestsAuthorization() {
        XCTAssertEqual(ScanAuthorizationStatus.notDetermined.decision, .requestAuthorization)
    }

    func testDeniedPromptsForSettings() {
        XCTAssertEqual(ScanAuthorizationStatus.denied.decision, .promptForSettings)
    }

    func testRestrictedPromptsForSettings() {
        XCTAssertEqual(ScanAuthorizationStatus.restricted.decision, .promptForSettings)
    }

    /// 穷举四种状态，确保没有状态漏掉映射、也没有状态被映射成「继续」以外的意外值。
    func testEveryStatusMapsToExactlyOneDecision() {
        let statuses: [ScanAuthorizationStatus] = [
            .notDetermined, .authorized, .denied, .restricted
        ]
        let decisions = statuses.map(\.decision)

        XCTAssertEqual(decisions.count, 4)
        XCTAssertEqual(decisions.filter { $0 == .proceed }.count, 1)
        XCTAssertEqual(decisions.filter { $0 == .requestAuthorization }.count, 1)
        XCTAssertEqual(decisions.filter { $0 == .promptForSettings }.count, 2)
    }

    func testOnlyDeniedAndRestrictedRequireSettingsPrompt() {
        XCTAssertFalse(ScanAuthorizationStatus.authorized.requiresSettingsPrompt)
        XCTAssertFalse(ScanAuthorizationStatus.notDetermined.requiresSettingsPrompt)
        XCTAssertTrue(ScanAuthorizationStatus.denied.requiresSettingsPrompt)
        XCTAssertTrue(ScanAuthorizationStatus.restricted.requiresSettingsPrompt)
    }

    // MARK: - 提示文案

    func testPermissionPromptNamesTheSource() {
        XCTAssertEqual(ScanImageSource.camera.displayName, "相机")
        XCTAssertEqual(ScanImageSource.photoLibrary.displayName, "相册")
        XCTAssertEqual(ScanImageSource.camera.permissionDeniedTitle, "无法访问相机")
        XCTAssertEqual(ScanImageSource.photoLibrary.permissionDeniedTitle, "无法访问相册")
    }

    func testPermissionPromptGuidesToSystemSettings() {
        for source in [ScanImageSource.camera, .photoLibrary] {
            XCTAssertTrue(
                source.permissionDeniedMessage.contains("设置"),
                "\(source) 的提示应引导用户到系统设置"
            )
        }
        XCTAssertTrue(ScanImageSource.camera.permissionDeniedMessage.contains("相册"))
    }

    func testPermissionPromptsDifferBetweenSources() {
        XCTAssertNotEqual(
            ScanImageSource.camera.permissionDeniedMessage,
            ScanImageSource.photoLibrary.permissionDeniedMessage
        )
    }

    // MARK: - 会话与取消（E3）

    func testNewSessionHasNothingCaptured() {
        let session = ScanSession()
        XCTAssertNil(session.source)
        XCTAssertNil(session.capturedImageData)
        XCTAssertNil(session.correctedImageData)
        XCTAssertFalse(session.hasCorrectedImage)
    }

    func testCaptureRecordsImageAndSource() {
        var session = ScanSession()
        session.capture(imageData: Data([1, 2, 3]), from: .camera)

        XCTAssertEqual(session.source, .camera)
        XCTAssertEqual(session.capturedImageData, Data([1, 2, 3]))
        XCTAssertFalse(session.hasCorrectedImage)
    }

    func testCorrectionKeepsOriginalImageAndAddsProcessedImage() {
        var session = ScanSession()
        session.capture(imageData: Data([1, 2, 3]), from: .photoLibrary)
        session.applyCorrection(imageData: Data([4, 5]))

        XCTAssertEqual(session.capturedImageData, Data([1, 2, 3]))
        XCTAssertEqual(session.correctedImageData, Data([4, 5]))
        XCTAssertTrue(session.hasCorrectedImage)
    }

    func testCorrectionIsIgnoredWithoutCapturedImage() {
        var session = ScanSession()
        session.applyCorrection(imageData: Data([4, 5]))

        XCTAssertNil(session.correctedImageData)
        XCTAssertFalse(session.hasCorrectedImage)
    }

    /// 重拍要丢弃上一张图的校正结果，否则会把旧图的校正产物带进新的一次流程。
    func testRecaptureInvalidatesPreviousCorrection() {
        var session = ScanSession()
        session.capture(imageData: Data([1]), from: .camera)
        session.applyCorrection(imageData: Data([2]))
        session.capture(imageData: Data([3]), from: .camera)

        XCTAssertEqual(session.capturedImageData, Data([3]))
        XCTAssertNil(session.correctedImageData)
        XCTAssertFalse(session.hasCorrectedImage)
    }

    /// E3：中途取消不得留下任何脏数据。
    func testCancelDiscardsEverything() {
        var session = ScanSession()
        session.capture(imageData: Data([1]), from: .camera)
        session.applyCorrection(imageData: Data([2]))
        session.cancel()

        XCTAssertEqual(session, ScanSession())
        XCTAssertNil(session.source)
        XCTAssertNil(session.capturedImageData)
        XCTAssertNil(session.correctedImageData)
        XCTAssertFalse(session.hasCorrectedImage)
    }

    func testCancelThenCaptureStartsClean() {
        var session = ScanSession()
        session.capture(imageData: Data([1]), from: .camera)
        session.applyCorrection(imageData: Data([2]))
        session.cancel()
        session.capture(imageData: Data([9]), from: .photoLibrary)

        XCTAssertEqual(session.source, .photoLibrary)
        XCTAssertEqual(session.capturedImageData, Data([9]))
        XCTAssertNil(session.correctedImageData)
    }
}
