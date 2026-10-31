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
- [ ] 3.1 接入相机拍摄与相册导入，替换 `ScannerEntryView` 占位，覆盖 T02–T05。（**进行中**，已完成四段不依赖真机的部分：① `ScanAccess`——用本地枚举替代 `AVAuthorizationStatus` / `PHAuthorizationStatus`，把「相机/相册授权状态 → 继续 / 请求授权 / 提示并跳转设置」映射成纯函数（覆盖 E1、E2），并用 `ScanSession` 表达「取消 / 重拍不得残留图片与来源」（覆盖 E3），`ScanAccessTests` 16 个方法，`iOS CI` run #16，commit `e13d45d`；② `ScanAuthorization` + `PhotoImport`——`ScanAuthorizationMapping` 把 AVFoundation / Photos 的真实状态映射过来（相册 `.limited` 视为已授权），`ScanAccessCoordinator.prepare` 把「查询 → 判断 → 按需申请 → 再判断」的异步顺序收成可单测的函数，`PhotosPickerImageImporter` 用 `PhotosPicker` 读取照片并把结果规范化（区分「读不出来」与「空数据」），`ScanAuthorizationTests` 16 个方法，`iOS CI` run #20，commit `c286790`（单元测试总数由 138 增至 170）；③ `CameraCapture` 与 `CameraPreview`——`CameraCaptureError` 区分「无可用摄像头（如模拟器）/ 拍照报错 / 没拿到图像」三种失败，`ScanCaptureCoordinator.capture` 把「查权限 → 按需申请 → 拍摄」串成可单测的异步函数，权限未获批准时直接返回 `.permissionDenied` 且**不触碰相机**，`AVCapturePhotoCapturer` 让取景与拍摄共用同一个 `AVCaptureSession`、采集会话的配置与启停都在私有串行队列上执行，`CameraPreviewView` 只负责显示不参与权限与拍摄；`CameraCaptureTests` 13 个方法，`iOS CI` run #22，commit `d8edeea`（单元测试总数由 170 增至 183）；④ **扫描页接线**——新建 `ScannerEntryViewModel` 把上面三段收敛成可注入、可单测的状态机（`Phase` / `ScanSession` / `AccessPrompt`），把「权限推进 → 拍摄 / 导入 → 结果收进会话」与 E1（相机权限拒绝）、E2（相册权限拒绝）、E3（取消 / 重拍不留脏数据）做成可断言状态；`ScannerEntryView` 整体重写为真实取景页（`CameraPreviewView` + 快门 + `PhotosPicker` + 重拍 / 取消），保留 `AppRoute.scanner` 契约与 `scannerEntry` / `scannerCancelButton` 无障碍标识，移除 Week 2 的模拟识别占位按钮，`BusinessCardMockData.makeRecognizedCard()` 随占位一并删除（全仓库无引用）；`ScannerEntryViewModelTests` 20 个方法，`iOS CI` run #25，commit `ef9119e`（其间 run #24 又踩到 `PhotosPickerItem` 只 `import PhotosUI` 时不在作用域内的坑，补 `import SwiftUI` 后通过；单元测试总数由 183 增至 203）。**仍待真机**：系统权限弹窗、「跳转设置」、`PhotosPickerItem.loadTransferable` 与真实取景画面/快门属人工验收，因此 T04 与 T02/T05 的端到端结论仍为「待执行」）
- [x] 3.2 实现名片区域检测与透视/方向校正，覆盖 T06（2026-10-27 通过。`CardQuad` 承载归一化四边形并提供面积、长宽比与 `isReliable()` 可靠判定（排除面积过小、几乎覆盖整图、长宽比不像名片三类候选），`CardDetectionOutcome` 区分 `.detected` / `.unreliable` / `.notFound`，对应「检测不可靠时提示重拍或手动调整，不把整张图片当作名片」；`VisionCardBoundaryDetector` 用 `VNDetectRectanglesRequest` 检测、`CIPerspectiveCorrection` 做透视摆正，几何与校正均写成可脱离相机调用的纯函数。`iOS CI` run #14，commit `67b4050`，单元测试总数由 118 增至 138 且全部通过。**方向校正的范围**：只做透视摆正，不按长宽比自动转 90°——竖版名片本身合法，仅凭四边形比例无法区分「竖版名片」与「照片方向不对」，误转会直接破坏识别；图像方向留待 3.1 拍摄/导入阶段提供，识别不理想时由用户重拍。真实名片照片上的检测成功率属人工验收）
- [x] 3.3 定义并实现 `OCRService`，输出原始识别文本，覆盖 T07（2026-10-27 通过。`OCRService` 协议以图片 `Data` 为输入、输出 `OCRTextResult`（文本行按阅读顺序排列），`VisionOCRService` 用 `VNRecognizeTextRequest` 做端上识别，默认 `.accurate` 级别并同时启用 `zh-Hans` / `en-US`；识别不到文字时抛 `OCRError.noTextFound` 而不是返回空结果，与「不得保存空名片」一致。`iOS CI` run #9，commit `3308a0b`，`Build for testing` 与 `Run unit tests` 均退出码 0。**注意**：CI 只验证编译与下方单测，真实名片图片上的识别效果属人工验收）。
- [x] 3.4 新增 OCR 相关自动化测试并保存日志（2026-10-27 通过。新增 `OCRServiceTests` 10 个方法，覆盖结果规范化与空结果判定、阅读顺序（跨行自上而下 / 行内从左到右 / 轻微纵向抖动仍归同一行 / 空输入）、错误文案，以及两条真实的 `VisionOCRService` 失败路径（不可解码图片 → `invalidImageData`；纯白图片 → `noTextFound`）与异步封装的错误传播。`iOS CI` run #10，commit `c4629ca`，单元测试总数由 108 增至 118 且全部通过，日志见 artifact `ios-build-test-logs`）。

## 4. Week 4 - Structured extraction and human verification
- [x] 4.1 实现字段结构化抽取（姓名/公司/职位/电话/邮箱/地址等），覆盖 T08–T10（2026-10-27 通过。`BusinessCardFieldParser` 把 OCR 原始文本按固定优先级拆段判型（邮箱子串 → 网址 → 标签:值 → 邮编 → 电话 → 强地址 → 公司 → 弱地址 → 部门 → 职位 → 姓名），未确认的段落直接丢弃；`iOS CI` run #6，commit `19fb143`，`BusinessCardFieldParserTests` 19 个方法通过。**注意**：测试输入是手写 OCR 文本夹具，不是真实名片图片，T08–T10 的端到端结论要等 3.3 的 OCR 接线后复验）。
- [x] 4.2 落实「不得虚构」原则：缺失字段返回 nil，覆盖 T09（2026-10-27 通过。`ExtractedCardFields` 全部字段默认 nil、`assign` 有值不覆盖；单个西文单词（如 `Apple`）既不判姓名也不判机构，宁可留空；无姓名候选时 `name` 保持 nil，且 `makeCard()` 返回 nil 不允许用公司名顶替保存。同一 CI run #6 中的 `testSingleLatinWordIsNeitherNameNorCompany`、`testCompanyOnlyCardHasNoNameAndCannotBecomeCard` 等方法覆盖）。
- [x] 4.3 打通人工校正与保存流程，覆盖 T11–T12（2026-10-31 通过。新增 `ScanReviewViewModel`，把「检测 → 透视校正 → OCR → 字段抽取 → 人工逐字段校正 → 确认保存」串成可注入、可单测的状态机：`analyze()` 依次调用 `CardBoundaryDetecting` / `CardBoundaryCorrecting` / `OCRService` / `BusinessCardFieldParser`，检测不可靠 / 未找到 / 校正失败 / 无文字 / 非预期错误五条失败路径都先于校正与识别返回（不把整张图当作名片）；`confirmSave()` 带 `guard phase == .review` 双保险，未确认前不写仓储。新增 `ScanReviewView` 承接 P03 / P04 / P05，`ScannerEntryView` 取得照片后即转入该页（重拍只丢弃本次照片，取消或保存完成才返回名片夹）。`ScanReviewViewModelTests` 17 个方法覆盖上述路径，以及「确认后写入的是人工改正过的字段」（T11）、「姓名为空或纯空白都拒绝保存」（E5 / T12）、「放弃识别后既有名片数量与内容不变」。`iOS CI` run #27，commit `07992c6`，单元测试总数由 203 增至 220 且全部通过。**仍待真机**：确认页的呈现与交互、识别进行中的真实观感，以及真实名片照片上的检测成功率与 OCR 效果属人工验收，见 `docs/UI验收清单.md` M18–M22）。
- [ ] 4.4 用 `testcards/ground_truth.json` 统计字段级准确率并记录错误分析（脚本已就绪、数值待执行。`FieldExtractionEvaluator` 实现字段级准确率与缺失字段误报率统计，含大小写/空白与电话分隔符归一化、五种判定（正确/不一致/漏抽/虚构/本应为空）与 Markdown 报告生成，12 个自测方法通过；但 `ground_truth.json` 目前只有字段真值、**没有对应 OCR 原文**，凭空计算等于编造输入，故数值仍留空，`testFieldAccuracyOnCorpusIsPendingUntilOCRTextsExist` 以 `XCTSkip` 退出，待 3.3 产出 `testcards/ocr/<卡片ID>.txt` 后运行）。

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

> 勾选状态只能根据实际证据更新。2.8 的编译与测试证据来自 CI 的 macOS runner（非本机 Mac），已在条目内注明来源。5.2 / 5.3 的证据为 `iOS CI` run #4（commit `fe755e7`，单元测试从 42 个增至 77 个并全部通过）；Week 4 的证据为 `iOS CI` run #6（commit `19fb143`，单元测试增至 108 个并全部通过）；Week 3 的 3.3 / 3.4 证据为 `iOS CI` run #9 与 run #10（commit `3308a0b` / `c4629ca`，单元测试增至 118 个并全部通过；其间 run #8 因 `Sequence` 扩展内 `max` 被解析为实例方法而编译失败，已在 run #9 修正）；3.2 的证据为 `iOS CI` run #14（commit `67b4050`，单元测试增至 138 个并全部通过；其间 run #12 因 `CGImage` 没有 `size` 属性而编译失败，run #13 又在两条测试上暴露鞋带公式符号约定写反，均已在 run #14 前修正）。4.1 / 4.2 勾选的是**规则级**实现与测试，其测试输入为手写 OCR 文本夹具而非真实名片图片；3.3 只交付了 OCR 服务与失败路径，尚未接到扫描页，因此 4.1 / 4.2 的端到端复验仍待 3.1 完成。4.3 勾选的是**逻辑层**的接线与测试（`ScanReviewViewModelTests` 17 个方法，覆盖 T11–T12 与 E5），其证据为 `iOS CI` run #27（commit `07992c6`，单元测试增至 220 个并全部通过）；确认页呈现与真实名片照片上的识别效果仍待真机，见 `docs/UI验收清单.md` M18–M22。4.4 因缺 OCR 原文而未勾选。5.1 / 5.4 与全部依赖模拟器或真机的人工验收项仍未完成，留待拿到 Mac 后补验。
