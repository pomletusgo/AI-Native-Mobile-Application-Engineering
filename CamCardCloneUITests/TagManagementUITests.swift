import XCTest

/// 标签编辑与标签管理页的人工验收项的自动化对应（M23–M25、M27–M29）。
///
/// 不在此文件内的相关条目：M26（详情页展示拍摄/导入的原始图，需要先有真实图像数据）
/// 与 M30–M33（导出到系统联系人 / 分享 VCF，涉及系统权限与分享面板），仍在
/// `docs/验证报告.md 附录 A` 里保持「待执行」。
final class TagManagementUITests: CamCardCloneUITestCase {

    // MARK: - 详情编辑态：加标签

    func testM23_详情编辑态添加标签并保存后可按该标签筛出() {
        let app = launchApp(reset: true, seed: true)
        XCTAssertTrue(waitForCardHolder(in: app))
        cardRow(in: app, at: 0).tap()

        XCTAssertTrue(app.buttons["editButton"].waitForExistence(timeout: 15))
        app.buttons["editButton"].tap()

        let tagField = app.textFields["newTagField"]
        XCTAssertTrue(tagField.waitForExistence(timeout: 10))
        tagField.tap()
        // 回车触发 onSubmit，避免键盘遮挡底部「添加」按钮带来的不确定性。
        tagField.typeText("VIP\n")
        XCTAssertTrue(app.staticTexts["VIP"].waitForExistence(timeout: 10), "编辑态应出现新标签")

        app.buttons["saveEditButton"].tap()
        XCTAssertTrue(app.staticTexts["VIP"].waitForExistence(timeout: 10), "详情页应出现新标签")

        tapNavigationBack(in: app)
        let chip = app.buttons["tagChip_VIP"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "名片夹的标签筛选栏应出现该标签")
        chip.tap()

        XCTAssertTrue(app.staticTexts[UITestSupport.zhuName].waitForExistence(timeout: 10))
        XCTAssertEqual(cardRows(in: app).count, 1, "点该标签应筛出这张名片")
    }

    // MARK: - 详情编辑态：删标签

    func testM24_删除已无使用者标签后筛选栏也移除() {
        let app = launchApp(reset: true, seed: true)
        XCTAssertTrue(waitForCardHolder(in: app))
        // 朱宏明是「Professor」标签的唯一使用者，删掉它就应连筛选栏一起消失。
        cardRow(in: app, at: 0).tap()

        XCTAssertTrue(app.buttons["editButton"].waitForExistence(timeout: 15))
        app.buttons["editButton"].tap()

        let removeButton = app.buttons["removeTagButton_Professor"]
        XCTAssertTrue(removeButton.waitForExistence(timeout: 10), "编辑态应能删除已有标签")
        scrollToAndTap(removeButton, in: app)

        app.buttons["saveEditButton"].tap()
        XCTAssertFalse(app.staticTexts["Professor"].waitForExistence(timeout: 3), "详情页该标签应消失")

        tapNavigationBack(in: app)
        XCTAssertFalse(app.buttons["tagChip_Professor"].waitForExistence(timeout: 3),
                       "该标签已无任何名片使用，筛选栏应随之消失")
    }

    // MARK: - 详情编辑态：取消丢弃标签改动

    func testM25_添加标签后取消不写入() {
        let app = launchApp(reset: true, seed: true)
        XCTAssertTrue(waitForCardHolder(in: app))
        cardRow(in: app, at: 0).tap()

        XCTAssertTrue(app.buttons["editButton"].waitForExistence(timeout: 15))
        app.buttons["editButton"].tap()

        let tagField = app.textFields["newTagField"]
        XCTAssertTrue(tagField.waitForExistence(timeout: 10))
        tagField.tap()
        tagField.typeText("Temp\n")
        XCTAssertTrue(app.staticTexts["Temp"].waitForExistence(timeout: 10))

        app.buttons["cancelEditButton"].tap()
        XCTAssertTrue(app.staticTexts[UITestSupport.zhuName].waitForExistence(timeout: 10),
                      "取消后应回到修改前的详情页")
        XCTAssertFalse(app.staticTexts["Temp"].exists, "取消应连同标签改动一起丢弃")

        tapNavigationBack(in: app)
        XCTAssertFalse(app.buttons["tagChip_Temp"].waitForExistence(timeout: 3),
                       "取消后该标签不应出现在筛选栏")
    }

    // MARK: - M27 标签管理页

    func testM27_标签管理页列出标签与张数且无标签时显示空态() {
        // 空库：显示空态提示（M27 后半句）。
        let emptyApp = launchApp(reset: true)
        XCTAssertTrue(waitForCardHolder(in: emptyApp))
        emptyApp.buttons["tagManagementEntry"].tap()

        let emptyHint = emptyApp.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "还没有标签")
        ).firstMatch
        XCTAssertTrue(emptyHint.waitForExistence(timeout: 15), "没有任何标签时应显示空态提示")
        emptyApp.terminate()

        // 有种子数据：列出全部标签与各自张数（M27 前半句）。
        let app = launchApp(reset: true, seed: true)
        XCTAssertTrue(waitForCardHolder(in: app))
        app.buttons["tagManagementEntry"].tap()

        XCTAssertTrue(app.buttons["tagRow_Conference"].waitForExistence(timeout: 15), "应列出全部标签")
        XCTAssertTrue(app.buttons["tagRow_Customer"].exists)
        XCTAssertTrue(app.buttons["tagRow_Professor"].exists)
        XCTAssertTrue(app.staticTexts["1 张"].exists, "每个标签应显示各自的名片张数")
    }

    // MARK: - M28 左滑删除标签

    func testM28_标签管理页左滑删除标签后筛选项同步消失() {
        let app = launchApp(reset: true, seed: true)
        XCTAssertTrue(waitForCardHolder(in: app))
        app.buttons["tagManagementEntry"].tap()

        let row = app.buttons["tagRow_Professor"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.swipeLeft()

        let deleteAction = app.buttons["deleteTag_Professor"]
        if deleteAction.waitForExistence(timeout: 3) {
            deleteAction.tap()
        } else {
            app.buttons["删除标签"].tap()
        }

        XCTAssertFalse(app.buttons["tagRow_Professor"].waitForExistence(timeout: 3),
                       "该标签应从标签列表消失")

        tapNavigationBack(in: app)
        XCTAssertFalse(app.buttons["tagChip_Professor"].waitForExistence(timeout: 3),
                       "回到名片夹后该标签也应从筛选栏消失")
    }

    // MARK: - M29 新建标签

    func testM29_新建标签的三步校验与成功保存() {
        let app = launchApp(reset: true, seed: true)
        XCTAssertTrue(waitForCardHolder(in: app))
        app.buttons["tagManagementEntry"].tap()

        XCTAssertTrue(app.buttons["newTagButton"].waitForExistence(timeout: 15))
        app.buttons["newTagButton"].tap()

        let nameField = app.textFields["newTagNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))

        // ① 输入为空 → 拒绝并提示。
        app.buttons["newTagSaveButton"].tap()
        XCTAssertTrue(app.staticTexts["请输入标签名称。"].waitForExistence(timeout: 10),
                      "名称为空应拒绝保存并提示")

        // ② 与已有标签重名（忽略大小写）→ 拒绝并提示。
        nameField.tap()
        nameField.typeText("conference")
        app.buttons["newTagSaveButton"].tap()
        XCTAssertTrue(app.staticTexts["标签「conference」已存在，请直接使用。"].waitForExistence(timeout: 10),
                      "重名标签应被拒绝并提示")

        // ③ 名称合法但未勾选任何名片 → 拒绝并提示。
        clearText(in: nameField)
        nameField.typeText("VIP")
        app.buttons["newTagSaveButton"].tap()
        XCTAssertTrue(app.staticTexts["请至少选择一张要打上该标签的名片。"].waitForExistence(timeout: 10),
                      "未勾选名片应拒绝保存并提示")

        // ④ 勾选李娜后保存 → 成功，标签列表新增该项且张数正确。
        let cardSelection = app.buttons.matching(
            NSPredicate(format: "label == %@", UITestSupport.liName)
        ).firstMatch
        XCTAssertTrue(cardSelection.waitForExistence(timeout: 10), "新建标签应能勾选名片")
        scrollToAndTap(cardSelection, in: app)
        app.buttons["newTagSaveButton"].tap()

        XCTAssertTrue(app.buttons["tagRow_VIP"].waitForExistence(timeout: 15), "标签列表应新增该项")
        XCTAssertTrue(app.staticTexts["1 张"].exists, "新标签应显示正确张数")
    }
}
