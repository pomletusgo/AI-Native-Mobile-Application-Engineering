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
- [ ] 2.8 在 Mac 上编译并运行首批单元测试，保存日志。

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
- [ ] 5.2 增加持久化实现并在重启后恢复数据，覆盖 T18（协议不变）。
- [ ] 5.3 实现联系人/VCF 导出，覆盖 T19。
- [ ] 5.4 增加 UI Golden Test 与首批截图对比。

## 6. Week 6 - Acceptance and regression
- [ ] 6.1 全量回归 Reference Test Suite T01–T20，确定性功能 100% 通过。
- [ ] 6.2 汇总 OCR 与字段抽取的错误原因与能力边界分析。
- [x] 6.3 在可用环境执行 `openspec validate --all --strict` 并保存日志（2026-10-26 通过，见 docs/logs/openspec-validate.log）。
- [ ] 6.4 完成 `docs/UI验收清单.md` 手工验收。
- [ ] 6.5 必需验证全部通过后归档，把四个 ADDED 能力合并为主规格。

> 勾选状态只能根据实际证据更新。本次提交只覆盖 Week 1–2；Week 2.8 需要在 Mac 上真实编译与运行，未执行前保持未勾选，其余周次留待后续提交。
