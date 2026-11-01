import XCTest

/// UI 测试共享常量。
///
/// 本文件不含业务断言，只提供三件事：
/// 1. 与 App 侧一致的启动参数常量（`CamCardCloneApp` 里另有一份，改动其一时必须同步另一处）；
/// 2. 启动 App、等待元素、兜底系统弹窗的工具方法；
/// 3. 种子名片姓名常量，避免断言里到处硬编码字符串。
enum UITestSupport {

    /// 清空存储目录，回到「首次启动」的空名片夹（对应 M01）。
    /// 必须与 `CamCardCloneApp.resetStoreArgument` 保持一致。
    static let resetStoreArgument = "-uiTestResetStore"

    /// 空库时写入 `BusinessCardMockData.sampleCards`（对应列表 / 搜索 / 标签类验收）。
    /// 必须与 `CamCardCloneApp.seedStoreArgument` 保持一致。
    static let seedStoreArgument = "-uiTestSeedStore"

    /// 种子名片姓名。列表按 `createdAt` 倒序，索引 0 / 1 / 2 依次为下面三者。
    static let zhuName = "朱宏明"
    static let liName = "李娜"
    static let davidName = "David Chen"
}

/// UI 测试基类：统一启动参数与常用查询。
///
/// 只做「驱动界面 + 等待」，不断言业务规则——业务规则仍由 `CamCardCloneTests` 覆盖。
class CamCardCloneUITestCase: XCTestCase {

    private static let launchTimeout: TimeInterval = 15

    override func setUp() {
        super.setUp()
        // 首个断言失败后立即停止：UI 测试的后续步骤强依赖前面的界面状态，继续跑只会产生级联噪声。
        continueAfterFailure = false
    }

    /// 启动 App。
    ///
    /// - Parameters:
    ///   - reset: 是否传 `-uiTestResetStore`（先清空存储）。
    ///   - seed: 是否传 `-uiTestSeedStore`（空库时写入三张种子名片）。
    /// - Returns: 已启动的 App 代理。
    @discardableResult
    func launchApp(reset: Bool = true, seed: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments: [String] = []
        if reset { arguments.append(UITestSupport.resetStoreArgument) }
        if seed { arguments.append(UITestSupport.seedStoreArgument) }
        app.launchArguments = arguments
        app.launch()
        return app
    }

    /// 等名片夹首屏出现：空状态或至少一张名片行。
    ///
    /// 首次启动与种子写入都发生在 App 启动路径上，直接断言列表元素会偶发抢跑，故统一先等首屏。
    @discardableResult
    func waitForCardHolder(in app: XCUIApplication) -> Bool {
        let emptyState = app.staticTexts["还没有名片"]
        let firstRow = app.buttons.matching(identifier: "cardRow").firstMatch
        let deadline = Date().addingTimeInterval(Self.launchTimeout)
        while Date() < deadline {
            if emptyState.exists || firstRow.exists { return true }
            _ = emptyState.waitForExistence(timeout: 1)
        }
        return false
    }

    /// 名片夹列表里的名片行（按可见顺序）。
    func cardRows(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(identifier: "cardRow")
    }

    /// 第 `index` 张名片行（未等可见，调用方自行 `waitForExistence`）。
    func cardRow(in app: XCUIApplication, at index: Int) -> XCUIElement {
        cardRows(in: app).element(boundBy: index)
    }

    /// 点导航栏返回按钮（详情页 / 标签管理页 → 名片夹）。
    func tapNavigationBack(in app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    /// 清空输入框：先聚焦再连续退格。
    ///
    /// 输入框宽度远大于文本宽度，`tap()` 落在文本右侧，插入点因此在末尾，退格即可清空全部内容。
    func clearText(in field: XCUIElement, characters: Int = 24) {
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: characters))
    }

    /// 元素不可点时先向上滑动列表，直到可点或达到次数上限。
    func scrollToAndTap(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 6) {
        var swipes = 0
        while !element.isHittable && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        element.tap()
    }

    /// 兜底点掉可能出现的系统权限弹窗（相机 / 相册 / 通讯录）。
    ///
    /// 模拟器没有摄像头，相机授权分支随系统版本而异；这里只做客串处理，
    /// 不把弹窗本身当作断言对象，也不据此推断权限行为（那属 M34 / M35 的人工验收）。
    ///
    /// - Returns: 是否点掉了弹窗。
    @discardableResult
    func dismissSystemAlertIfPresent(timeout: TimeInterval = 3) -> Bool {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: timeout) else { return false }

        for title in ["允许", "好", "OK", "Allow", "Don't Allow", "不允许"] {
            let button = alert.buttons[title]
            if button.exists {
                button.tap()
                return true
            }
        }
        alert.buttons.element(boundBy: alert.buttons.count - 1).tap()
        return true
    }
}
