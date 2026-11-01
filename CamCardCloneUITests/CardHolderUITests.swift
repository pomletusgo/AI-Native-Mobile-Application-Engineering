import XCTest

/// 名片夹与名片详情的人工验收项的自动化对应（M01–M17）。
///
/// 覆盖范围说明：
/// - 能被 XCUITest 无头驱动的条目在这里断言，`xcodebuild test` 不需要 `Simulator.app` 窗口；
/// - M04（真实拍摄 / 相册导入）、M10（拨号 / 邮件 / 浏览器）、M15（外观）、M16（VoiceOver 需人耳）
///   不在此文件内，仍在 `docs/UI验收清单.md` 里保持「待执行」。
///
/// 每个用例都通过启动参数把存储置为确定状态（`-uiTestResetStore` / `-uiTestSeedStore`），
/// 因此不依赖上一个用例留下的数据，也不依赖执行顺序。
final class CardHolderUITests: CamCardCloneUITestCase {

    // MARK: - M01 首次启动

    func testM01_首次启动进入空名片夹且无弹窗() {
        let app = launchApp(reset: true)
        XCTAssertTrue(waitForCardHolder(in: app), "首次启动应直接进入名片夹")

        XCTAssertTrue(app.staticTexts["还没有名片"].exists, "应显示空状态插图")
        XCTAssertTrue(app.buttons["emptyStateScanButton"].exists, "空状态应有「扫描第一张名片」入口")
        XCTAssertEqual(app.alerts.count, 0, "首次启动不应出现权限弹窗或登录页")
    }

    // MARK: - M02 空状态进入扫描页

    func testM02_空状态点击扫描入口进入取景页() {
        let app = launchApp(reset: true)
        XCTAssertTrue(waitForCardHolder(in: app))
        app.buttons["emptyStateScanButton"].tap()
        dismissSystemAlertIfPresent()

        XCTAssertTrue(app.buttons["scannerCancelButton"].waitForExistence(timeout: 15), "应进入扫描页")
        XCTAssertTrue(app.buttons["scannerImportButton"].exists, "取景页应有「相册导入」入口")
        XCTAssertTrue(app.buttons["scannerCaptureButton"].exists, "取景页应有「拍摄」入口")

        // 有相机时是取景画面、无相机（模拟器）时是提示改用相册的同一页；
        // 两种形态都属 M02 预期，这里不断言具体形态，避免把环境差异当成缺陷。
    }

    // MARK: - M03 扫描页取消

    func testM03_扫描页取消返回名片夹且不留脏数据() {
        let app = launchApp(reset: true)
        XCTAssertTrue(waitForCardHolder(in: app))
        app.buttons["emptyStateScanButton"].tap()
        dismissSystemAlertIfPresent()

        let cancelButton = app.buttons["scannerCancelButton"]
        if cancelButton.waitForExistence(timeout: 15), cancelButton.isHittable {
            cancelButton.tap()
        } else if app.buttons["返回名片夹"].exists {
            // 相机权限被拒时 App 会先给自己的提示，其「返回名片夹」与取消同效。
            app.buttons["返回名片夹"].tap()
        }

        XCTAssertTrue(app.staticTexts["还没有名片"].waitForExistence(timeout: 15), "取消后应回到名片夹")
        XCTAssertEqual(cardRows(in: app).count, 0, "取消不应产生任何名片")
    }

    // MARK: - M05 搜索命中

    func testM05_搜索片段只剩匹配的名片() {
        let app = launchApp(reset: true, seed: true)
        XCTAssertTrue(waitForCardHolder(in: app))

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15), "名片夹应有搜索框")
        search.tap()
        search.typeText("David")

        XCTAssertTrue(app.staticTexts[UITestSupport.davidName].waitForExistence(timeout: 10))
        XCTAssertEqual(cardRows(in: app).count, 1, "搜索命中的应只剩一张名片")
    }

    // MARK: - M06 搜索无结果

    func testM06_搜索无结果显示提示而非空状态() {
        let app = launchApp(reset: true, seed: true)
        XCTAssertTrue(waitForCardHolder(in: app))

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.tap()
        search.typeText("zzzzzz")

        XCTAssertTrue(app.staticTexts["未找到匹配的名片"].waitForExistence(timeout: 10),
                      "无结果时应显示无结果提示")
        XCTAssertFalse(app.staticTexts["还没有名片"].exists, "无结果时不应显示空状态插图")
    }

    // MARK: - M07 清空搜索

    func testM07_清空搜索恢复全部名片() {
        let app = launchApp(reset: true, seed: true)
        XCTAssertTrue(waitForCardHolder(in: app))

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.tap()
        search.typeText("David")
        XCTAssertEqual(cardRows(in: app).count, 1)

        clearText(in: search, characters: 8)

        XCTAssertTrue(cardRow(in: app, at: 2).waitForExistence(timeout: 10), "清空后应恢复完整列表")
        XCTAssertEqual(cardRows(in: app).count, 3, "清空搜索框后应恢复显示全部名片")
    }

    // MARK: - M08 标签筛选

    func testM08_点击标签筛选再次点击恢复() {
        let app = launchApp(reset: true, seed: true)
        XCTAssertTrue(waitForCardHolder(in: app))

        let chip = app.buttons["tagChip_Conference"]
        XCTAssertTrue(chip.waitForExistence(timeout: 15), "名片夹应有标签筛选栏")
        chip.tap()

        XCTAssertTrue(app.staticTexts[UITestSupport.davidName].waitForExistence(timeout: 10))
        XCTAssertEqual(cardRows(in: app).count, 1, "筛选后应只剩该标签下的名片")

        chip.tap()
        XCTAssertTrue(cardRow(in: app, at: 2).waitForExistence(timeout: 10))
        XCTAssertEqual(cardRows(in: app).count, 3, "再次点击同一标签应恢复完整列表")
    }

    // MARK: - M09 详情页字段展示

    func testM09_详情页显示已保存字段且不出现空字段行() {
        let app = launchApp(reset: true, seed: true)
        XCTAssertTrue(waitForCardHolder(in: app))

        // 列表按创建时间倒序，首行是有电话 / 邮箱 / 地址、无传真 / 网站 / 邮编的朱宏明。
        cardRow(in: app, at: 0).tap()

        XCTAssertTrue(app.staticTexts["地址"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["上海市杨浦区四平路1239号"].exists, "已保存的地址应显示")
        XCTAssertTrue(app.staticTexts["邮箱"].exists, "已保存的邮箱应显示")
        XCTAssertFalse(app.staticTexts["传真"].exists, "未保存的字段不应出现空行")
        XCTAssertFalse(app.staticTexts["网站"].exists, "未保存的字段不应出现空行")
        XCTAssertFalse(app.staticTexts["邮编"].exists, "未保存的字段不应出现空行")

        // 补上部门与邮编后应能看到这两行（M09 明确要求「含部门、邮编」）。
        app.buttons["editButton"].tap()
        let departmentField = app.textFields["部门"]
        XCTAssertTrue(departmentField.waitForExistence(timeout: 10))
        departmentField.tap()
        departmentField.typeText("Engineering")

        let postalField = app.textFields["邮编"]
        XCTAssertTrue(postalField.waitForExistence(timeout: 10))
        scrollToAndTap(postalField, in: app)
        postalField.typeText("200092")

        app.buttons["saveEditButton"].tap()

        XCTAssertTrue(app.staticTexts["部门"].waitForExistence(timeout: 10), "已保存的部门应显示成一行")
        XCTAssertTrue(app.staticTexts["Engineering"].exists)
        XCTAssertTrue(app.staticTexts["邮编"].exists, "已保存的邮编应显示成一行")
        XCTAssertTrue(app.staticTexts["200092"].exists)
        XCTAssertFalse(app.staticTexts["传真"].exists, "未保存的字段仍不应出现空行")
    }

    // MARK: - M11 编辑姓名并保存

    func testM11_编辑姓名保存后详情页与列表都更新() {
        let app = launchApp(reset: true, seed: true)
        XCTAssertTrue(waitForCardHolder(in: app))
        cardRow(in: app, at: 0).tap()

        XCTAssertTrue(app.buttons["editButton"].waitForExistence(timeout: 15))
        app.buttons["editButton"].tap()

        let nameField = app.textFields["editNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        clearText(in: nameField)
        nameField.typeText("Zhu Hongming")
        app.buttons["saveEditButton"].tap()

        XCTAssertTrue(app.staticTexts["Zhu Hongming"].waitForExistence(timeout: 10),
                      "详情页应立即显示修改后的姓名")

        tapNavigationBack(in: app)
        XCTAssertTrue(app.staticTexts["Zhu Hongming"].waitForExistence(timeout: 10),
                      "名片夹列表也应显示修改后的姓名")
        XCTAssertFalse(app.staticTexts[UITestSupport.zhuName].exists, "修改前的姓名不应再出现")
    }

    // MARK: - M12 编辑后取消

    func testM12_编辑后取消恢复修改前内容() {
        let app = launchApp(reset: true, seed: true)
        XCTAssertTrue(waitForCardHolder(in: app))
        cardRow(in: app, at: 0).tap()

        XCTAssertTrue(app.buttons["editButton"].waitForExistence(timeout: 15))
        app.buttons["editButton"].tap()

        let nameField = app.textFields["editNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        clearText(in: nameField)
        nameField.typeText("Temp Name")
        app.buttons["cancelEditButton"].tap()

        XCTAssertTrue(app.staticTexts[UITestSupport.zhuName].waitForExistence(timeout: 10),
                      "取消后应恢复为修改前内容")
        XCTAssertFalse(app.staticTexts["Temp Name"].exists, "取消不应写入草稿")
    }

    // MARK: - M13 姓名为空拒绝保存

    func testM13_姓名清空后保存被拒并停留在编辑态() {
        let app = launchApp(reset: true, seed: true)
        XCTAssertTrue(waitForCardHolder(in: app))
        cardRow(in: app, at: 0).tap()

        XCTAssertTrue(app.buttons["editButton"].waitForExistence(timeout: 15))
        app.buttons["editButton"].tap()

        let nameField = app.textFields["editNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        clearText(in: nameField)
        nameField.typeText("   ")
        app.buttons["saveEditButton"].tap()

        XCTAssertTrue(app.textFields["editNameField"].exists, "姓名不可为空：应拒绝保存并停留在编辑态")
        XCTAssertTrue(app.buttons["cancelEditButton"].exists, "仍应处于编辑态（有「取消」按钮）")
    }

    // MARK: - M14 删除名片

    func testM14_逐张删除名片直到回到空状态() {
        let app = launchApp(reset: true, seed: true)
        XCTAssertTrue(waitForCardHolder(in: app))
        XCTAssertTrue(cardRow(in: app, at: 2).waitForExistence(timeout: 15), "列表应有三张名片")
        XCTAssertEqual(cardRows(in: app).count, 3)

        for remaining in stride(from: 3, through: 1, by: -1) {
            let row = cardRow(in: app, at: 0)
            XCTAssertTrue(row.waitForExistence(timeout: 15))
            row.tap()

            let deleteButton = app.buttons["deleteCardButton"]
            XCTAssertTrue(deleteButton.waitForExistence(timeout: 15))
            scrollToAndTap(deleteButton, in: app)

            if remaining > 1 {
                XCTAssertTrue(cardRow(in: app, at: remaining - 2).waitForExistence(timeout: 15),
                              "删除后列表应只剩 \(remaining - 1) 张名片")
                XCTAssertEqual(cardRows(in: app).count, remaining - 1, "该名片应从列表消失")
            }
        }

        XCTAssertTrue(app.staticTexts["还没有名片"].waitForExistence(timeout: 15),
                      "删除唯一一张名片后应回到空状态")
    }

    // MARK: - M17 持久化

    func testM17_保存后完全退出重启名片与修改仍在() {
        let app = launchApp(reset: true, seed: true)
        XCTAssertTrue(waitForCardHolder(in: app))
        cardRow(in: app, at: 0).tap()

        XCTAssertTrue(app.buttons["editButton"].waitForExistence(timeout: 15))
        app.buttons["editButton"].tap()

        let nameField = app.textFields["editNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        clearText(in: nameField)
        nameField.typeText("Persisted Name")
        app.buttons["saveEditButton"].tap()
        XCTAssertTrue(app.staticTexts["Persisted Name"].waitForExistence(timeout: 10))

        app.terminate()

        // 重启不带任何测试参数：走生产路径读取同一份存储，验证「完全退出并重启」后数据仍在。
        let relaunched = launchApp(reset: false, seed: false)
        XCTAssertTrue(relaunched.staticTexts["Persisted Name"].waitForExistence(timeout: 20),
                      "重启后修改仍在")
        XCTAssertEqual(cardRows(in: relaunched).count, 3, "重启后三张名片都应在")
    }
}
