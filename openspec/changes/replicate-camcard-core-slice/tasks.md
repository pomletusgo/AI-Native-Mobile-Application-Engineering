## 1. Week 1 - Black-box observation and specification
- [x] 1.1 观察参考 App 的「名片数字化与联系人管理」闭环，界定复刻边界与越界功能清单。
- [x] 1.2 输出规格说明书 `docs/规格说明书.md`：术语、复刻边界、参考环境锁定、BusinessCard Schema、页面清单 P01–P10、状态清单 S1–S4/D1–D3/E1–E5、Reference Test Suite T01–T20。
- [x] 1.3 建立 30 张合成名片与 Ground Truth：`testcards/ground_truth.json`（含中/英/双语、竖版、多电话、多邮箱、字段缺失、低质量、复杂背景等类别）。
- [x] 1.4 提供本变更的 proposal、四个 ADDED Delta、design 与可验证任务。

## 2. Week 2 - Architecture, UI and data model
- [x] 2.1 建立工程目录与 `CamCardClone.xcodeproj`（含共享 Scheme），可直接用 Xcode 打开。
- [x] 2.2 新建 `BusinessCard` 值类型与 Mock 数据，字段规则符合 Schema 第 4 节。
- [x] 2.3 新建 `BusinessCardRepository` 协议与 `InMemoryBusinessCardRepository` 实现（CRUD / 搜索 / 标签）。
- [x] 2.4 新建 `AppRouter` 与 `NavigationStack` 导航，支持 push / pop / popToRoot。
- [x] 2.5 新建 `CardHolderViewModel` 与 `CardDetailViewModel`，覆盖 S1–S4 / D1–D2 与「姓名为空拒绝保存」。
- [x] 2.6 新建名片夹首页、空状态、名片行、详情/编辑页与扫描入口占位。
- [x] 2.7 新建首批单元测试（Model / Repository / ViewModel）。
- [x] 2.8 在 Mac 上编译并运行首批单元测试，保存日志（2026-10-26 通过。证据来源为 GitHub Actions 的 `macos-15` runner 而非本机 Mac：`iOS CI` run #2，commit `7e0ab39`，`Build for testing` 34 秒、`Run unit tests` 2 分 46 秒共 42 个测试，退出码 0，日志见 artifact `ios-build-test-logs`；见 docs/验证报告.md）。

## 3. Week 3 - Camera and OCR
- [ ] 3.1 接入相机拍摄与相册导入，替换 `ScannerEntryView` 占位，覆盖 T02–T05。
- [ ] 3.2 实现名片区域检测与透视/方向校正，覆盖 T06。
- [ ] 3.3 定义并实现 `OCRService`，输出原始识别文本，覆盖 T07。
- [ ] 3.4 新增 OCR 相关自动化测试并保存日志。

## 4. Week 4 - Structured extraction and human verification
- [ ] 4.1 实现字段结构化抽取（姓名/公司/职位/电话/邮箱/地址等），覆盖 T08–T10。
- [ ] 4.2 落实「不得虚构」原则：缺失字段返回 nil，覆盖 T09。
- [ ] 4.3 打通人工校正与保存流程，覆盖 T11–T12。
- [ ] 4.4 用 `testcards/ground_truth.json` 统计字段级准确率并记录错误分析。

## 5. Week 5 - Card management, persistence and export
- [ ] 5.1 补齐列表/详情/搜索/标签/备注/编辑/删除的完整交互，覆盖 T13–T17。
- [x] 5.2 增加持久化实现并在重启后恢复数据，覆盖 T18（协议不变）（2026-10-26 通过。`PersistentBusinessCardRepository` 落盘 JSON，App 层注入点已替换，协议与调用方零改动；`iOS CI` run #4，commit `fe755e7`，`Build for testing` 与 `Run unit tests` 均退出码 0，其中 `testDataSurvivesRelaunch` / `testEditsSurviveRelaunch` 用新建实例指向同一文件模拟重启；见 docs/验证报告.md）。
- [x] 5.3 实现联系人/VCF 导出，覆盖 T19（2026-10-26 通过。`VCardExporter` 输出 vCard 3.0，字段一一映射且缺失字段不写占位值；同一 CI run #4 中 `VCardExporterTests` 19 个方法通过。写入系统联系人的 `Contacts` 接入与外发确认 UI **尚未实现**，本项只覆盖 VCF 生成，见 6.4）。
- [ ] 5.4 增加 UI Golden Test 与首批截图对比。

## 6. Week 6 - Acceptance and regression
- [ ] 6.1 全量回归 Reference Test Suite T01–T20，确定性功能 100% 通过。
- [ ] 6.2 汇总 OCR 与字段抽取的错误原因与能力边界分析。
- [x] 6.3 在可用环境执行 `openspec validate --all --strict` 并保存日志（2026-10-26 通过，见 docs/logs/openspec-validate.log）。
- [ ] 6.4 完成 `docs/UI验收清单.md` 手工验收。
- [ ] 6.5 必需验证全部通过后归档，把四个 ADDED 能力合并为主规格。

> 勾选状态只能根据实际证据更新。2.8 的编译与测试证据来自 CI 的 macOS runner（非本机 Mac），已在条目内注明来源。5.2 / 5.3 的证据为 `iOS CI` run #4（commit `fe755e7`），该运行中单元测试从 42 个增至 77 个并全部通过；5.1 / 5.4 与全部依赖模拟器或真机的人工验收项仍未完成，留待拿到 Mac 后补验。
