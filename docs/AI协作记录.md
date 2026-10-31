# AI 协作记录（真实会话导出）

本文件是作业要求的「AI 协作记录」的**真实导出**，不是模板——模板见 `docs/TRAE提示词.md`（该文件第 9 节已声明自己不能作为协作记录的证据）。下面每一轮都对应一次真实的 TRAE 协作，包含：原始提示词、AI 输出摘要、AI 犯的错误、人工干预、实际执行的命令与结果。

## 0. 记录环境

| 项 | 值 |
| --- | --- |
| 使用的模型 | DeepSeek-V4.1-Flash |
| TRAE / IDE 版本 | `<待填：本机 TRAE 版本号>`（仓库内无版本留痕，不猜） |
| 交互方式 | TRAE 内 Agent 模式，逐轮对话；每轮结束即提交并推送 |
| 上下文约束 | `PROJECT_RULES.md`、`.trae/rules/project_rules.md`、`docs/规格说明书.md`、`openspec/changes/replicate-camcard-core-slice/` |
| 机器环境 | Windows，**无 macOS / Xcode**；编译与单元测试由 GitHub Actions 的 `macos-15` runner 执行 |
| 证据口径 | 本机命令记退出码；云端编译与测试记 `iOS CI` 运行号与作业级结论（经 GitHub 公开 API 读取）。未执行的检查一律标「待执行」，不把编译成功写成测试通过 |

## 1. 人工干预汇总（用户做了什么、为什么）

| 轮次 | 人工干预 | 原因 |
| --- | --- | --- |
| 起步 | 选「iOS 原生 SwiftUI」而非跨端 | 课程要求与验收环境对齐 |
| 起步 | 选「对齐 OpenSpec + TRAE 规范」、「直接提供 .xcodeproj」 | 作业要求 SDD 流程与可直接打开的工程 |
| 起步 | 提出「有什么办法可以编译吗」→ 选「生成 GitHub Actions CI」 | 本机没有 Mac，需要可验证的编译途径 |
| 起步 | 提供真实姓名与邮箱（刘润东 / 760592343@qq.com）、GitHub 用户名与仓库名 | 提交需要真实作者身份；仓库由用户创建 |
| 全程 | 「一个一个来做，不用一次性全部做完」 | 明确否决一次性铺开，要求逐项推进 |
| 全程 | 「可以先做所有能做的部分，等我拿到 mac 再进行核验」 | 物理 Mac 缺失，先推进不依赖真机的部分 |
| 全程 | 「我现在还没有找到 mac 真机……并且要按要求补上提示词」 | 明确要求维护 AI 协作记录 |
| Week 6 | 「先修掉」（`规格测试追踪表.md` 里的陈旧占位记录） | AI 未主动发现的文档与实现不同步 |
| Week 6 | 本会话多次以「1」「2」选择 AI 给出的候选方案 | 由人拍板下一步做哪一项 |
| 会话中 | 用户自行删除 AI 留下的临时提交信息文件（`.git-commit-msg.tmp`） | 保持工作区干净 |

人与 AI 的分工：**路线、取舍与「做哪一项」由人决定**；AI 负责按 `tasks.md` 逐项实现、跑 CI、回填台账。凡涉及规格解释的取舍（如手动调整框是否豁免最小面积），AI 先说明理由再加入，并写进 `docs/验证报告.md` 与 `tasks.md`。

## 2. 逐轮记录

### 第 1 轮 — Week 1–2：规格与骨架

- **原始提示词**：「请你遵循文档中的作业要求，完成相关内容」（并选定 iOS 原生 SwiftUI、OpenSpec + TRAE、直接给 .xcodeproj）。
- **AI 输出**：`docs/规格说明书.md`（术语、复刻边界、参考环境锁定、BusinessCard Schema、P01–P10、S1–S4/D1–E5、T01–T20）、`testcards/ground_truth.json`（30 张卡）、四个 ADDED Delta、工程骨架与首批 42 个单测。
- **AI 的错误**：`BusinessCard` 构造函数缺 `postalCode` / `department`，与规格 Schema 不一致导致编译失败；CI 的模拟器 destination 写法不稳。
- **修正**：补参数并改为从可用设备里挑第一个 iPhone（commit `7e0ab39`）。
- **人工干预**：提供作者身份与仓库信息；决定用 CI 代替本机 Mac。
- **命令与结果**：`git push origin main` 退出码 0 → `iOS CI` **run #2**（commit `7e0ab39`）`Build for testing` + `Run unit tests` 均 success，42 个测试。

### 第 2 轮 — Week 3：检测与透视校正（3.2）

- **原始提示词**：「先做 3.2 检测与校正（推荐）」「继续」。
- **AI 输出**：`CardQuad`（归一化四边形、面积、长宽比、`isReliable()`）、`CardDetectionOutcome` 三态、`VisionCardBoundaryDetector`（`VNDetectRectanglesRequest` + `CIPerspectiveCorrection`）、`CardBoundaryTests` 20 个方法。
- **AI 的错误**：① 用 `CGImage.size` 取宽高（该属性不存在）→ run #12 失败；② 鞋带公式符号约定写反，两条测试暴露 → run #13 失败。
- **修正**：改用 `width` / `height`（commit `01353b5`）；统一「顺时针为正」的约定并调整实现（commit `67b4050`）。
- **命令与结果**：`iOS CI` **run #14**（commit `67b4050`）success，测试数 118 → 138。

### 第 3 轮 — Week 3：OCR 服务（3.3 / 3.4）

- **原始提示词**：「继续」「开始吧」。
- **AI 输出**：`OCRService` 协议与 `VisionOCRService`（`.accurate` + `zh-Hans`/`en-US`）、`OCRTextResult` 规范化、`sortedInReadingOrder()`、`OCRError` 三类失败、`OCRServiceTests` 10 个方法。
- **AI 的错误**：`Sequence` 扩展内调用 `max` 被解析为实例方法而编译失败（run #8）。
- **修正**：显式写 `Swift.max`（commit `3308a0b`）。
- **命令与结果**：**run #9**（commit `3308a0b`）与 **run #10**（commit `c4629ca`）均 success，测试数 108 → 118。

### 第 4 轮 — Week 4：字段抽取（4.1 / 4.2）

- **原始提示词**：按 `tasks.md` 推进 Week 4。
- **AI 输出**：`BusinessCardFieldParser`（11 步判定顺序、词表、`assign` 不覆盖）、`ExtractedCardFields`（默认全 nil、`makeCard()` 姓名空则返回 nil）、`BusinessCardFieldParserTests` 19 个方法、`FieldExtractionEvaluator`（准确率与误报率评价脚本，12 个自测）。
- **AI 的错误与自限**：测试输入是手写 OCR 文本夹具而非真实名片图片，AI 主动在台账中**没有**把它写成 T08–T10 的端到端结论。
- **命令与结果**：**run #6**（commit `19fb143`）success，测试数增至 108。

### 第 5 轮 — Week 3：权限适配层与相册导入（3.1 第 1–2 段）

- **原始提示词**：选「权限适配层 + 相册导入（推荐）」。
- **AI 输出**：`ScanAccess`（授权状态 → 继续 / 请求 / 提示跳设置，E1/E2）、`ScanSession`（取消与重拍不留脏数据，E3）、`ScanAuthorizationMapping` / `ScanAccessCoordinator`、`PhotosPickerImageImporter`；`ScanAccessTests` 16 + `ScanAuthorizationTests` 16。
- **AI 的错误**：① `PhotosPickerItem` 只 `import PhotosUI` 时不在作用域（run #18）；② 误用不存在的 `PHAuthorizationStatus.addOnly`（run #19）。
- **修正**：补 `import SwiftUI`（commit `7b5aac4`）；改用 `PHAccessLevel` 上的 `.addOnly`（commit `c286790`）。
- **命令与结果**：**run #16**（commit `e13d45d`）、**run #20**（commit `c286790`）success，测试数 138 → 170。

### 第 6 轮 — Week 3：相机取景与拍摄（3.1 第 3 段）

- **原始提示词**：「继续」。
- **AI 输出**：`CameraCaptureError` 三种失败、`ScanCaptureCoordinator`（查权限 → 按需申请 → 拍摄，被拒时不触碰相机）、`AVCapturePhotoCapturer`（配置与启停在私有串行队列）、`CameraPreviewView`；`CameraCaptureTests` 13 个方法。
- **命令与结果**：**run #22**（commit `d8edeea`）success，测试数 170 → 183。

### 第 7 轮 — Week 3：扫描页接线（3.1 第 4 段）

- **原始提示词**：选「扫描页接线（推荐）」。
- **AI 输出**：`ScannerEntryViewModel`（权限推进 → 拍摄 / 导入 → 会话收敛）、`ScannerEntryView` 整体重写为真实取景页、删除 `BusinessCardMockData.makeRecognizedCard()` 占位；`ScannerEntryViewModelTests` 20 个方法。
- **AI 的错误**：再次踩到 `PhotosPickerItem` 的 import 问题（run #24）。
- **修正**：补 `import SwiftUI`（commit `ef9119e`）。
- **命令与结果**：**run #25**（commit `ef9119e`）success，测试数 183 → 203。

### 第 8 轮 — Week 4：打通「检测 → 保存」（4.3）

- **原始提示词**：「4.3」。
- **AI 输出**：`ScanReviewViewModel`（五条失败路径先于校正与识别返回；`confirmSave()` 带 `guard phase == .review`）、`ScanReviewView`（P03/P04/P05 三态）；`ScanReviewViewModelTests` 17 个方法。
- **命令与结果**：**run #27**（commit `07992c6`）success，测试数 203 → 220。

### 第 9 轮 — Week 5：标签与字段编辑（5.1 第 1 段）

- **原始提示词**：选「标签与字段编辑补齐（推荐）」、「含新建 + 勾选名片（推荐）」。
- **AI 输出**：标签增删做成**草稿**（取消编辑一并丢弃）、`postalCode` / `department` 可读可写、详情页查看态与编辑态补字段。
- **命令与结果**：**run #30**（commit `a78e03c`）success，测试数 220 → 233。

### 第 10 轮 — Week 5：详情页展示原始图（P06）

- **原始提示词**：选「详情页展示原始图（P06）」。
- **AI 输出**：`CardImageStore` / `FileCardImageStore`、`confirmSave()` 落盘并回写文件名、`displayImageData` 优先原图、`delete()` 清理图像。
- **AI 的错误**：新测试里误写 `harness.photoBytes`（run #32）。
- **修正**：改为正确的属性名（commit `4d0cc5a`）。
- **命令与结果**：**run #33**（commit `4d0cc5a`）success，测试数 233 → 249。

### 第 11 轮 — Week 5：独立标签管理页（P09）

- **原始提示词**：选「独立标签管理页（P09）」。
- **AI 输出**：`TagManagementViewModel`（按名片汇总张数、按标签查看、删除整标签、新建标签三步校验）与 `TagManagementView`（三态）、`AppRoute.tagManagement`。
- **命令与结果**：**run #36**（commit `57c872f`）success，测试数 249 → 268。

### 第 12 轮 — Week 5：导出接线（P10，5.3）

- **原始提示词**：「做1」（执行 P10 导出接线）。
- **AI 输出**：`ContactExportMapping`（纯函数映射 CNMutableContact）、`ContactExportAccess` / `ContactExportCoordinator`、`SystemContactExporter`、`VCardExporter.temporaryFileURL`、详情页确认框与「去设置」；`ContactExportTests` 23 个方法。
- **AI 的错误**：① 用了不存在的 `CNLabelFax`（run #38）；② 测试里 `BusinessCard` 实参顺序写反（`jobTitle` 必须在 `department` 之前，run #39）。
- **修正**：改用 `CNLabelPhoneNumberWorkFax`（commit `99aeb75`）；改正实参顺序（commit `9af9715`）。
- **命令与结果**：**run #40**（commit `9af9715`）success，测试数 268 → 301。

### 第 13 轮 — Week 6：回归矩阵与陈旧记录修正（6.1 前置）

- **原始提示词**：「先修掉」「开始」。
- **AI 输出**：修掉 `规格测试追踪表.md` 里关于持久化实现的陈旧占位记录；在表中建立「Reference Test Suite T01–T20 回归矩阵」，逐条标注判定口径与人工验收项。
- **命令与结果**：**run #40 / #42** 为矩阵所引用的断言来源（见 `docs/验证报告.md`）。

### 第 14 轮 — Week 3 补漏：P03 手动调整边界（逻辑层 + 手势 UI）

- **原始提示词**：「P03 手动调整边界的手势逻辑层」→ 之后选「P03 的手势 UI 代码」。
- **AI 输出**：`CardBoundaryAdjustment`（命中测试、拖拽夹紧、凸性与面积合法性判定，20 个方法）、`ScanReviewViewModel.adjustingBoundary`（16 个方法）、`BoundaryAdjustmentCanvas`（底图 + 四边形叠层 + 四角手柄）。
- **AI 的错误**：① `Phase` 新增 case 后 `ScanReviewView` 的 `switch` 不再穷尽（run #44）；② 测试里用 `CGPoint` 直接相等比较浮点累加结果（run #45）。
- **修正**：补 `case .adjustingBoundary` 分支（commit `5dc7262`）；改成逐分量 `accuracy: 0.0001` 比较（commit `efc2417`）。
- **AI 的自纠（无 CI 失败）**：画布最初用命名坐标空间，后简化为手势挂在画布自身用默认 local 坐标系；拖拽基准从「手指落点」改为「角的当前位置」，避免轻点一下角就跳到手指下。
- **命令与结果**：**run #46**（commit `efc2417`）success，测试数 301 → 337；**run #48**（commit `8008a36`）success（纯界面改动，测试数不变）。

### 第 15 轮 — Week 6：能力边界分析（6.2）

- **原始提示词**：选「① 6.2 能力边界分析」。
- **AI 输出**：`docs/能力边界分析.md`——按「检测 → 校正 → OCR → 字段抽取」分层汇总错误原因，逐字段列漏抽与误报，并**主动标出与规格 4.3 的偏差**：「多 Email 其余入 `notes` 或保留列表」未实现。
- **AI 的执行错误**：`npx openspec@1.13.2 validate` 退出码 **1**（`ETARGET: No matching version found`）。
- **修正**：改用仓库已有脚本 `npm run spec:validate`，退出码 **0**，输出 `Totals: 1 passed, 0 failed (1 items)`。
- **命令与结果**：**run #50**（commit `7726e31`）success。

## 3. AI 犯过的错误汇总

| # | 错误 | 触发的 CI 运行 | 修正 |
| --- | --- | --- | --- |
| 1 | `BusinessCard` 缺 `postalCode` / `department` 参数 | run #2 前 | 补参数（`7e0ab39`） |
| 2 | 用不存在的 `CGImage.size` | run #12 | 改用 `width` / `height`（`01353b5`） |
| 3 | 鞋带公式符号约定写反 | run #13 | 统一「顺时针为正」（`67b4050`） |
| 4 | `Sequence` 扩展内 `max` 被解析为实例方法 | run #8 | 写 `Swift.max`（`3308a0b`） |
| 5 | `PhotosPickerItem` 缺 `import SwiftUI` | run #18 / #24 | 补 import（`7b5aac4` / `ef9119e`） |
| 6 | 误用 `PHAuthorizationStatus.addOnly` | run #19 | 改用 `PHAccessLevel`（`c286790`） |
| 7 | 测试里误写 `harness.photoBytes` | run #32 | 改正属性名（`4d0cc5a`） |
| 8 | 使用不存在的 `CNLabelFax` | run #38 | 改 `CNLabelPhoneNumberWorkFax`（`99aeb75`） |
| 9 | `BusinessCard` 实参顺序写反（`jobTitle` 必须在 `department` 前） | run #39 | 改正顺序（`9af9715`） |
| 10 | `Phase` 新增 case 后 `switch` 不穷尽 | run #44 | 补分支（`5dc7262`） |
| 11 | 用 `CGPoint` 直接相等比较浮点累加结果 | run #45 | 改逐分量 `accuracy` 比较（`efc2417`） |
| 12 | 用了不存在的 npm 包版本（`openspec@1.13.2`） | 本机，未进 CI | 改用 `npm run spec:validate` |

这些错误都由 CI 或命令退出码**当场暴露**，没有一条是靠人工肉眼发现后悄悄改掉的；修正都单独提交，台账里保留「哪个 run 因何失败」。

## 4. 实际执行的命令与结果

| 命令 | 结果 |
| --- | --- |
| `git -c user.name="刘润东" -c user.email="760592343@qq.com" commit -F <临时信息文件>` | 退出码 0，作者为本人（如 `7726e31`、`8008a36`） |
| `git push origin main` | 退出码 0，触发 `iOS CI`；本文件编写前最后一次为 run #50 |
| `npm run spec:validate`（即 `openspec validate --all --strict`） | 退出码 0，`1 passed, 0 failed` |
| `npx openspec@1.13.2 validate --all --strict` | 退出码 1（版本不存在），已改用上一条 |
| 经 GitHub 公开 API 读取 `actions/runs` 与 `jobs` | run #2 / #4 / #6 / #9 / #10 / #14 / #16 / #20 / #21 / #22 / #25 / #27 / #28 / #30 / #31 / #33 / #34 / #36 / #40 / #46 / #48 / #49 / #50 的 `OpenSpec Validate` 与 `Build & Test (iOS Simulator)` 均 success |
| `xcodebuild ... build-for-testing` / `Cmd+U` | **未执行**：本机为 Windows，无 macOS 与 Xcode，故不存在本机编译与测试记录 |
| `openspec archive`（6.5） | **未执行**：必需验证（6.4 人工验收）未完成，按规则 10 不得提前归档 |

## 5. 复现与补验

1. 在仓库 Actions 页手动触发 `iOS CI`（已配置 `workflow_dispatch`），或任意推送到 `main`。
2. 失败时无需登录：workflow 的 `Surface errors as annotations` 步骤会把 `error:` 行提升为注解，可用 `repos/<owner>/<repo>/check-runs/<job_id>/annotations` 直接读到。
3. 拿到 Mac 后按 `docs/验证报告.md` 的「待补验步骤」执行人工验收（`docs/UI验收清单.md` M01–M36）。
