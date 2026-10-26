## Context
起点只有一份 Week 1 规格说明书（`docs/规格说明书.md`）与 30 张合成名片的 Ground Truth（`testcards/ground_truth.json`），没有工程文件、没有 Xcode 工程、没有仓储与视图模型。本次要在锁定环境内复刻 CamCard 的核心闭环，并只交付 Week 1–2 的可运行增量。相机、OCR、字段抽取与持久化在后续周次增量引入，但接口必须先稳定。

## Goals / Non-Goals
交付可直接用 Xcode 打开并运行的名片夹骨架：原生启动、名片夹列表、空状态、搜索、标签筛选、详情、编辑、删除、扫描入口占位，以及覆盖 Model / Repository / ViewModel 的首批单元测试。所有确定性行为对齐 Reference Test Suite T01–T20 中 Week 2 可验证的子集。

非目标：本轮不实现真实相机、相册、区域检测、OCR、字段抽取、本地持久化与联系人导出；不实现注册、会员、支付、云同步、CRM 等任何越界功能；不追求视觉像素级等同，只要求可观察行为等价。

## Decisions
### D1. 全新 MVVM 工程，起点即规格驱动
新建 `app-shell`、`card-library`、`card-holder`、`card-scanner` 四个 ADDED 能力。Model 是不依赖 SwiftUI 的值类型；ViewModel 使用 `@MainActor` 与 `@Published` 发布状态；View 只负责转发用户意图、不承载业务规则。归档前主规格为空，契约只存在于活动 Delta 中。

### D2. BusinessCard 作为唯一数据契约
`BusinessCard` 是 `struct`，遵循 `Identifiable, Codable, Equatable, Hashable`。字段与规格说明书第 4 节一致，其中 `name` 是唯一必填字段；其余字段缺失时必须为 `nil`，**不得由 AI 补全**。派生属性 `subtitle`、`primaryPhone`、`hasContactActions`、`searchableText` 不参与持久化。

### D3. 仓储用协议隔离实现
`BusinessCardRepository` 定义为稳定协议：`fetchAll`、`card(withID:)`、`add`、`update`、`delete`、`search`、`cards(taggedWith:)`、`allTags`。Week 2 只提供 `InMemoryBusinessCardRepository`；Week 5 增加文件/数据库持久化实现时协议不变，从而保证既有测试与上层代码零改动。

### D4. 外观状态与数据状态分离
名片夹的 S1（空）、S2（有名片）、S3（搜索中）、S4（标签筛选）由 ViewModel 的派生属性推导（`isEmpty`、`isSearching`、`hasNoResults`、`visibleCards`），不额外保存冗余布尔量，避免状态不一致。详情页 D1/D2 通过 `isEditing` 与 `draft` 草稿区分查看态与编辑态。

### D5. 编辑采用草稿副本，取消即丢弃
详情页进入编辑时把名片复制为 `draft`；保存时才写回仓储，取消则丢弃草稿。`saveEditing()` 在 `name` 为空或纯空白时返回 `false` 并保持编辑态，对应 E5 / T20，防止产生脏数据。

### D6. 扫描入口先做占位、后接相机
Week 2 的 `ScannerEntryView` 只提供入口与「模拟识别结果」动作，用于验证 T02（进入扫描）与 T12（保存后回到列表）。Week 3 用真实相机与相册替换占位内容，`AppRoute.scanner` 契约不变。

### D7. 工程文件手工编写并纳入版本库
提供 `CamCardClone.xcodeproj/project.pbxproj` 与共享 Scheme `CamCardClone.xcscheme`，可用 Xcode 直接打开。`objectVersion = 56`、`compatibilityVersion = "Xcode 14.0"`，与课程参考案例一致；不使用 XcodeGen 等额外生成器，降低环境依赖。

### D8. 语言模式与部署目标
部署目标取 iOS 17.0，与课程参考案例基线一致。Swift 语言模式取 5.0：本机（Windows）无法编译验证，严格并发检查（Swift 6 语言模式）可能引入不可验证的构建失败，故先以 5.0 保证可构建性，后续在 Mac 上验证通过后再评估迁移。

## State Transitions
| 状态 | 触发 | 表现 | 退出 |
|---|---|---|---|
| S1 空名片夹 | 无任何名片 | 空状态插图 + 「扫描第一张名片」 | 保存首张名片 → S2 |
| S2 有名片 | 存在 ≥1 张名片 | 名片列表（缩略信息） | 输入搜索 → S3；选标签 → S4 |
| S3 搜索中 | 搜索框有输入 | 按关键字过滤，无结果给提示 | 清空 → S2 |
| S4 标签筛选 | 选中某标签 | 仅显示该标签名片 | 再次点击标签 → S2 |
| D1 查看 | 打开详情 | 展示全部已保存字段，空字段不显示 | 点编辑 → D2 |
| D2 编辑 | 点编辑 | 可编辑表单 | 保存成功 → D1；取消 → D1（丢弃草稿） |

## Technical Approach
按周次里程碑交付：W1 规格说明书与 Ground Truth；W2 工程骨架 + Model + Repository + ViewModel + 名片夹/详情/扫描入口占位 + 首批单元测试；W3 相机与 OCR；W4 字段抽取与人工校正（最关键一周）；W5 名片管理、持久化与导出；W6 全量回归、错误分析与 SDD 归档。

导航使用 `NavigationStack(path:)` + `navigationDestination(for: AppRoute.self)`，`AppRouter` 统一管理 `push` / `pop` / `popToRoot`。数据流是 View → `@Published` 意图方法 → Repository → 重新派生的 `visibleCards`，不存在 View 直接写仓储的路径。

## Risks / Trade-offs
- **无法在本机编译验证**：Windows 无 Xcode，只能保证结构与引用自洽。缓解：手工编写 pbxproj 时严格对照参考案例格式，并在验证报告中标记为「待 Mac 验证」。
- **Swift 6 严格并发**：见 D8，选择语言模式 5.0 换取可构建性。
- **占位扫描入口**：Week 2 用模拟识别结果验证 T02/T12，若被误当成真实 OCR 会造成验收误判。缓解：`ScannerEntryView` 明确标注占位，验证报告中单列。
- **概率性功能不可 100% 断言**：OCR 与字段抽取改用固定测试集 + Ground Truth 量化评价，绝不能把准确率包装成「通过」。

## Migration Plan
没有用户数据需要迁移。归档前 `openspec/specs/` 为空，四个能力的契约只存在于活动 Delta；W6 全部必需验证通过后再归档，把 ADDED Delta 合并为主规格。

## Verification Plan
在 Mac 上执行：`xcodebuild -project CamCardClone.xcodeproj -scheme CamCardClone -destination 'platform=iOS Simulator,name=iPhone 15' build-for-testing` 编译，`Cmd+U` 运行首批单元测试，按 `docs/UI验收清单.md` 逐项人工验收，并在可联网环境执行 `npm run spec:validate`（`openspec validate --all --strict`）。受阻项目在 `docs/验证报告.md` 中保持「待执行」，不得预先勾选。
