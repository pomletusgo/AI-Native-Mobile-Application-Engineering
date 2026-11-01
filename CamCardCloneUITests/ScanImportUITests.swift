import XCTest

/// 「相册导入 → 检测识别 → 确认保存 → 详情核对」链路的端到端验收（M04 / M18 / M19 的相册导入分支）。
///
/// 为什么这条链路能无头自动化：2026-11-01 用诊断用例实测的元素树确认，`PhotosPicker`
/// 选择器的全部元素（导航栏「照片」、`photosView_content_scroll_view`、网格单元
/// `PXGGridLayout-Info`）都并入了 **App 自己的进程**——`com.apple.PhotosUIPrivate.PhotosPicker`
/// 与 `com.apple.mobileslideshow` 两个进程当时都未运行。因此可以直接用 `app` 寻址，
/// 不需要跨进程查询，也不需要 `Simulator.app` 窗口。若日后 iOS 改成独立进程承载选择器，
/// 用 `xcodebuild ... -resultBundlePath <x>.xcresult` 跑一次再从 `xcresulttool export attachments`
/// 里取元素树即可重新判读。
///
/// **前提：模拟器相册里必须有照片。** CI 的 `ui` 作业在跑测试前会 `xcrun simctl addmedia`
/// 喂入 `testcards/images/*.png`；本地手动跑之前也要先执行同一步，否则网格为空、用例会失败。
///
/// 网格单元**没有逐张标识**（一屏 30 个单元共用一个 `PXGGridLayout-Info`），只能按位置取
/// 「第一张」。这个位置在当前环境里是确定的：`addmedia` 写入的照片时间戳最新，图库按时间
/// 倒序排列，因此它们排在最前（2026-11-01 的元素树里首屏 15 个单元的标签全是我们那批照片
/// 的时间）。**这条假设写进了用例的失败信息里**——选到的照片若不是名片，用例会明确报出来。
final class ScanImportUITests: CamCardCloneUITestCase {

    /// 保存时改写的姓名。用 ASCII 是为了避开中文输入法的 `typeText` 兼容问题；
    /// 改写姓名这一步同时就是 M19 要求的「逐字段改正识别结果」。
    private let correctedName = "Imported Card"

    // MARK: - M04 相册导入取到照片后立即进入检测与识别

    func testM04_相册导入取到照片并进入检测识别() {
        let app = launchApp(reset: true)
        let firstCell = openPhotoPicker(in: app)
        firstCell.tap()

        XCTAssertTrue(waitForReviewPage(in: app),
                      "选照片后应进入检测与识别（P03/P04）：既没看到识别中反馈，也没看到确认表单或失败提示")
        XCTAssertFalse(app.staticTexts["当前没有可用的相机，请从相册导入名片照片。"].exists,
                       "取到照片后不应仍停留在取景占位页")
    }

    // MARK: - M18 / M19 识别结果确认与保存，保存后可查详情

    func testM18M19_相册导入的识别结果改正后保存并可在详情页核对() {
        let app = launchApp(reset: true)
        let firstCell = openPhotoPicker(in: app)
        firstCell.tap()

        XCTAssertTrue(waitForReviewPage(in: app),
                      "选照片后应进入检测与识别（P03/P04）：既没看到识别中反馈，也没看到确认表单或失败提示")

        let saveButton = app.buttons["scanReviewSaveButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 60),
                      "识别结束后应进入确认页。若日志里出现 scanReviewNotice，说明选框不可靠而退到了手动调整——"
                        + "多半是选到的照片不是名片（网格首位并非我们的语料），需先确认相册排序")

        // M19：逐字段改正识别结果。把姓名改成固定值，让保存后的断言不依赖 OCR 结果。
        let nameField = app.textFields["scanReviewField-name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10), "确认页应有姓名字段")
        clearText(in: nameField)
        nameField.typeText(correctedName)

        saveButton.tap()

        // 保存后回名片夹，应出现刚保存的这张名片。
        XCTAssertTrue(waitForCardHolder(in: app), "保存后应回到名片夹")
        XCTAssertTrue(app.staticTexts[correctedName].waitForExistence(timeout: 15),
                      "名片夹应出现刚保存的名片")
        XCTAssertEqual(cardRows(in: app).count, 1, "本次只保存了一张名片")

        // M19 后半段：点进详情，看到的是改正后的内容。
        cardRow(in: app, at: 0).tap()
        XCTAssertTrue(app.staticTexts[correctedName].waitForExistence(timeout: 15),
                      "详情页应显示改正后的姓名")
    }

    // MARK: - 公共步骤

    /// 从名片夹进到扫描页、打开相册选择器，返回网格里的第一个单元。
    private func openPhotoPicker(in app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(waitForCardHolder(in: app), "名片夹首屏未出现")

        let scanEntry = app.buttons["scanEntryButton"]
        XCTAssertTrue(scanEntry.waitForExistence(timeout: 10), "找不到扫描入口")
        scanEntry.tap()

        // 模拟器没有摄像头，扫描页会尝试准备相机，权限分支随系统版本而异；
        // 这里只兜底点掉可能出现的系统弹窗，不让它挡住相册导入按钮。
        dismissSystemAlertIfPresent(timeout: 5)

        let importButton = app.buttons["scannerImportButton"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 10), "找不到相册导入按钮")
        importButton.tap()

        // 选择器的导航栏标题跟随系统语言：本地 Mac 是 zh_CN（「照片」），CI runner 是 en_US（"Photos"）。
        // 2026-11-01 run #66 / #67 两次 UI 作业都在写死「照片」的断言上失败，根因就是这个语言差。
        // 与语言无关的定位在下面的网格单元标识符上，标题只用来确认选择器确实打开了。
        let pickerNavBar = app.navigationBars.matching(
            NSPredicate(format: "identifier IN %@", ["照片", "Photos"])
        ).firstMatch
        if !pickerNavBar.waitForExistence(timeout: 20) {
            dumpHierarchy(of: app)
        }
        XCTAssertTrue(pickerNavBar.exists, "相册选择器未打开：既没有「照片」也没有 \"Photos\" 导航栏")

        let firstCell = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(firstCell.waitForExistence(timeout: 20),
                      "相册网格里没有可选取的照片：跑之前需先 xcrun simctl addmedia <UDID> testcards/images/*.png")
        return firstCell
    }

    /// 选择器没打开时，把 App 进程内的元素树按行打上 `UIPROBE` 前缀输出。
    ///
    /// 日志与产物的下载端点实测需要仓库授权（返回 403），而 CI 的注解端点免登录可读，
    /// 因此 `ui` 作业会用 `grep "^UIPROBE"` 把这段提成注解，便于直接判读失败现场。
    private func dumpHierarchy(of app: XCUIApplication) {
        print("UIPROBE 相册选择器未出现，以下为 App 进程内的元素树")
        for line in app.debugDescription.split(separator: "\n", omittingEmptySubsequences: false) {
            print("UIPROBE \(line)")
        }
    }

    /// 等复核页出现。三种形态都算「已离开取景页、进入 P03/P04」：
    /// 识别中有反馈、检测失败有内联提示、或已出一字段预填的确认表单。
    private func waitForReviewPage(in app: XCUIApplication, timeout: TimeInterval = 60) -> Bool {
        let analyzing = app.staticTexts["正在检测名片区域并识别文字…"]
        let notice = app.staticTexts["scanReviewNotice"]
        let saveButton = app.buttons["scanReviewSaveButton"]

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if analyzing.exists || notice.exists || saveButton.exists { return true }
            _ = saveButton.waitForExistence(timeout: 1)
        }
        return false
    }
}
