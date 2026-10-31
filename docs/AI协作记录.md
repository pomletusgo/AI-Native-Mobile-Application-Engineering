# AI 协作记录（真实会话导出）

本文件是作业要求的「AI 协作记录」的真实导出，不是模板——模板见 `docs/TRAE提示词.md`（该文件第 9 节已声明自己不能作为协作记录的证据）。下面每一轮都对应一次真实的 TRAE 协作，记录四件事：提示词要点、AI 输出摘要、AI 犯的错误、实际执行的命令与结果。

本项目的协作形态遵循 `PROJECT_RULES.md` 第 2 条：**只做增量开发，禁止用一个 Prompt 生成整个 App**。因此全过程的提示词都是「一次只推进一个任务切片」，并且每条都按课程要求的三条硬约束组织——**限定上下文**（先读现存规格与规则，只改被点名的文件）、**保护回归**（写明不得改动的接口、模型与已通过的测试）、**要求真实证据**（编译 / 测试 / `openspec validate` 要给命令与退出码，未执行就写未执行）。下文的「提示词要点」是对这一结构的归纳，**不逐字引用会话原话**。

## 0. 记录环境

| 项 | 值 |
| --- | --- |
| 使用的模型 | DeepSeek-V4.1-Flash |
| TRAE / IDE 版本 | `<待填：本机 TRAE 版本号>`（仓库内无版本留痕，不猜） |
| 交互方式 | TRAE 内 Agent 模式，逐轮对话；每轮结束即提交并推送 |
| 提示词形态 | WBS 逐项推进（Week 1 → Week 6），每轮一个切片；未出现一次性生成整个 App 的提示词 |
| 上下文约束 | `PROJECT_RULES.md`、`.trae/rules/project_rules.md`、`docs/规格说明书.md`、`openspec/changes/replicate-camcard-core-slice/` |
| 机器环境 | Windows，**无 macOS / Xcode**；编译与单元测试由 GitHub Actions 的 `macos-15` runner 执行 |
| 证据口径 | 本机命令记退出码；云端编译与测试记 `iOS CI` 运行号与作业级结论（经 GitHub 公开 API 读取）。未执行的检查一律标「待执行」，不把编译成功写成测试通过 |

## 1. 人工干预汇总（人做了什么、为什么）

| 轮次 | 人工干预 | 原因 |
| --- | --- | --- |
| 起步 | 选定 iOS 原生 SwiftUI，而不是跨端方案 | 与课程验收环境对齐 |
| 起步 | 选定对齐 OpenSpec + TRAE 规范；要求直接提供可用 Xcode 打开的 `.xcodeproj` | 作业要求 SDD 流程与可直接打开的工程 |
| 起步 | 在确认本机没有 Mac 之后，选定「生成 GitHub Actions CI」作为编译与测试途径 | 需要一个不依赖本机的真实可验证通道 |
| 起步 | 提供真实姓名、邮箱与 GitHub 用户名、仓库名 | 提交需要真实作者身份；仓库由本人创建 |
| 全程 | 要求一次只推进一个任务项，否决一次性铺开 | 对应 `PROJECT_RULES.md` 第 2 条 |
| 全程 | 要求先做不依赖真机的部分，等拿到 Mac 再统一核验 | 物理 Mac 缺失 |
| 全程 | 要求按作业规定维护 AI 协作记录 | 交付物要求 |
| Week 6 | 要求先修掉追踪表里与实现不同步的陈旧记录 | AI 未主动发现的文档与代码不一致 |
| Week 6 | 在候选项里拍板优先修规格 4.3 的「多 Email」偏差 | 该偏差是真实功能缺口，先补齐再谈其它 |
| Week 6 | 在候选项里拍板做 5.4 的 UI Golden Test 骨架 | 这是当时还不依赖 Mac 的功能性交付物，先把录制 / 比对工具与断言写好，截图对比留待 Mac |
| 各轮 | 由人在候选项里拍板下一步做哪一项 | 决定权在人，AI 不自行扩张范围 |
| 会话中 | 人工清理 AI 留下的临时提交信息文件 | 保持工作区干净 |

人与 AI 的分工：**路线、取舍与「做哪一项」由人决定**；AI 按 `tasks.md` 逐项实现、跑 CI、回填台账。凡涉及规格解释的取舍（例如手动调整框是否豁免最小面积），AI 先说明理由再落地，并同步写进 `docs/验证报告.md` 与 `tasks.md`，不静默改动。

## 2. 逐轮记录

每一轮的提示词要点都用四条固定槽位记录：**限定上下文**（本轮先读什么、只改哪些文件）、**目标**（本轮唯一交付什么）、**不得改动 / 不做**（保护回归与越界防线）、**证据要求**（要什么命令、退出码或 CI 结论）。

### 第 1 轮 — Week 1–2：规格与骨架

- **提示词要点**
  - 限定上下文：先检查工作区，读 `PROJECT_RULES.md` 与 `openspec/config.yaml`，确认工程中还没有业务代码。
  - 目标：以「名片全能王」为黑盒对象界定本次功能切片，**只做观察与规格、不写业务代码**，产出租出规格说明书（术语、复刻边界、明确不复刻清单、锁定参考环境、BusinessCard Schema、P01–P10、S1–S4 / D1–D3 / E1–E5、T01–T20）与 30 张 Ground Truth；随后按已审查的规格**只建 Week 2 骨架**。
  - 不做：不出现用户注册、会员、订阅支付、云同步、CRM、二维码名片等越界功能；Week 2 阶段不做 OCR，扫描入口只做占位。
  - 证据要求：给出编译与运行测试的真实命令、退出码与日志路径；未执行就写未执行。
- **AI 输出**：`docs/规格说明书.md`、`testcards/ground_truth.json`（30 张）、四个 ADDED Delta、可打开的 `CamCardClone.xcodeproj`、Model/Repository/ViewModel 三层与首批 42 个单测。
- **AI 的错误**：`BusinessCard` 构造函数缺 `postalCode` / `department`，与规格 Schema 不一致导致编译失败；CI 的模拟器 destination 写法不稳。
- **修正**：补参数并改为从可用设备里挑第一个 iPhone（commit `7e0ab39`）。
- **证据**：`iOS CI` **run #2**（commit `7e0ab39`）success，42 个测试。

### 第 2 轮 — Week 3：区域检测与透视校正（3.2）

- **提示词要点**
  - 限定上下文：扫描链路尚无区域检测与校正，后端能力已就绪；只改扫描相关文件。
  - 目标：只做区域检测与透视校正，覆盖 T06 的几何部分。
  - 不得改动：`BusinessCard` 模型与 `BusinessCardRepository` 协议签名。
  - 证据要求：新增测试并给出 CI 运行号。
- **AI 输出**：`CardQuad`（归一化四边形、面积、长宽比、`isReliable()`）、`CardDetectionOutcome` 三态、`VisionCardBoundaryDetector`（`VNDetectRectanglesRequest` + `CIPerspectiveCorrection`）、`CardBoundaryTests` 20 个方法。
- **AI 的错误**：① 用 `CGImage.size` 取宽高（该属性不存在）；② 鞋带公式符号约定写反，两条测试当场暴露。
- **修正**：改用 `width` / `height`（commit `01353b5`）；统一「顺时针为正」的约定（commit `67b4050`）。
- **证据**：run #12 / run #13 失败后，**run #14**（commit `67b4050`）success，测试数 118 → 138。

### 第 3 轮 — Week 3：OCR 服务（3.3 / 3.4）

- **提示词要点**
  - 限定上下文：检测与校正已通过，本次只接文字识别。
  - 目标：`OCRService` 协议 + Vision 实现 + 文本规范化 + 失败路径，覆盖 T07 的规则部分。
  - 不做：不改扫描页界面，不碰字段抽取（下一轮再做）。
  - 证据要求：失败路径也要有测试；给 CI 运行号。
- **AI 输出**：`OCRService` / `VisionOCRService`（`.accurate` + `zh-Hans`/`en-US`）、`OCRTextResult` 规范化与 `sortedInReadingOrder()`、`OCRError` 三类失败、`OCRServiceTests` 10 个方法。
- **AI 的错误**：`Sequence` 扩展内调用 `max` 被解析为实例方法而编译失败（run #8）。
- **修正**：显式写 `Swift.max`（commit `3308a0b`）。
- **证据**：**run #9**（commit `3308a0b`）、**run #10**（commit `c4629ca`）success，测试数 108 → 118。

### 第 4 轮 — Week 4：字段抽取（4.1 / 4.2）

- **提示词要点**
  - 限定上下文：OCR 服务已就绪；只做「文本 → 结构化字段」这一段。
  - 目标：规则抽取器与「不得虚构」约束，覆盖 T08–T10。
  - 不得改动：`BusinessCard` Schema 与仓储协议。
  - 证据要求：为每条抽取规则写测试；**不得**把夹具级测试说成端到端结论。
- **AI 输出**：`BusinessCardFieldParser`（固定判定顺序、词表、不覆盖已有值）、`ExtractedCardFields`（默认全 `nil`）、`BusinessCardFieldParserTests` 19 个方法、`FieldExtractionEvaluator`（准确率 / 误报率评价脚本，12 个自测）。
- **AI 的自我约束**：测试输入是手写 OCR 文本夹具，AI 主动在台账中**没有**把它记成 T08–T10 的端到端结论，并把字段级准确率留为「待执行」。
- **证据**：**run #6**（commit `19fb143`）success，测试数增至 108。

### 第 5 轮 — Week 3：权限适配层与相册导入（3.1 第 1–2 段）

- **提示词要点**
  - 限定上下文：只做相机 / 相册的权限与导入这一段，不碰检测、OCR。
  - 目标：授权状态机、取消与重拍不留脏数据、相册导入，覆盖 E1 / E2 / E3。
  - 不做：不写相机取景（下一段再做）。
  - 证据要求：各授权分支都要有可断言的结果。
- **AI 输出**：`ScanAccess`（授权状态 → 继续 / 请求 / 提示跳设置）、`ScanSession`（取消与重拍不留脏数据）、`ScanAuthorizationMapping`、`PhotosPickerImageImporter`；`ScanAccessTests` 16 + `ScanAuthorizationTests` 16。
- **AI 的错误**：① `PhotosPickerItem` 只 `import PhotosUI` 时不在作用域（run #18）；② 误用不存在的 `PHAuthorizationStatus.addOnly`（run #19）。
- **修正**：补 `import SwiftUI`（commit `7b5aac4`）；改用 `PHAccessLevel` 上的 `.addOnly`（commit `c286790`）。
- **证据**：**run #16**（commit `e13d45d`）、**run #20**（commit `c286790`）success，测试数 138 → 170。

### 第 6 轮 — Week 3：相机取景与拍摄（3.1 第 3 段）

- **提示词要点**
  - 限定上下文：授权层已就绪，本地无相机设备（模拟器场景）也要能给出明确提示。
  - 目标：取景与拍摄，覆盖 T02–T04；把「可单测的编排」与 AVFoundation 实现分离。
  - 不做：不接入识别流程（下一段接线时做）。
  - 证据要求：权限被拒时不触碰相机这一条要有测试。
- **AI 输出**：`CameraCaptureError` 三种失败、`ScanCaptureCoordinator`（查权限 → 按需申请 → 拍摄）、`AVCapturePhotoCapturer`（配置与启停在私有串行队列）、`CameraPreviewView`；`CameraCaptureTests` 13 个方法。
- **证据**：**run #22**（commit `d8edeea`）success，测试数 170 → 183。

### 第 7 轮 — Week 3：扫描页接线（3.1 第 4 段）

- **提示词要点**
  - 限定上下文：各能力已具备，只做界面接线与占位替换。
  - 目标：把权限、取景、拍摄、导入接进扫描页，删除占位实现。
  - 不得改动：协议与模型签名不变。
  - 证据要求：界面接线也要有 CI 编译证据，人工验收另记。
- **AI 输出**：`ScannerEntryViewModel`（权限推进 → 拍摄 / 导入 → 会话收敛）、`ScannerEntryView` 改为真实取景页、删除 `BusinessCardMockData.makeRecognizedCard()` 占位；`ScannerEntryViewModelTests` 20 个方法。
- **AI 的错误**：再次踩到 `PhotosPickerItem` 的 import 问题（run #24）。
- **修正**：补 `import SwiftUI`（commit `ef9119e`）。
- **证据**：**run #25**（commit `ef9119e`）success，测试数 183 → 203。

### 第 8 轮 — Week 4：打通「检测 → 保存」（4.3）

- **提示词要点**
  - 限定上下文：识别链路各段已就绪，本次只做串接与失败路径收敛。
  - 目标：检测 → 校正 → OCR → 抽取 → 人工校正 → 保存，覆盖 T11–T12 / E5。
  - 不做：不改后续的列表与详情交互。
  - 证据要求：先于识别的五条失败路径必须都有测试。
- **AI 输出**：`ScanReviewViewModel`（失败优先返回、`confirmSave()` 校验相位）、`ScanReviewView`（识别中 / 确认 / 失败三态）；`ScanReviewViewModelTests` 17 个方法。
- **证据**：**run #27**（commit `07992c6`）success，测试数 203 → 220。

### 第 9 轮 — Week 5：标签与字段编辑（5.1 第 1 段）

- **提示词要点**
  - 限定上下文：详情页功能已存在，本次只补字段与标签编辑。
  - 目标：标签增删做成草稿语义、`postalCode` / `department` 可读可写，覆盖 T13 / T14 / T16。
  - 不得改动：不改模型字段与仓储协议。
  - 证据要求：空串、纯空白、重复标签、非编辑态这些边界都要有断言。
- **AI 输出**：`CardDetailViewModel` 的草稿式标签增删与字段读写、详情页查看态 / 编辑态补齐。
- **证据**：**run #30**（commit `a78e03c`）success，测试数 220 → 233。

### 第 10 轮 — Week 5：详情页展示原始图（P06）

- **提示词要点**
  - 限定上下文：名片已能持久化，本次只加图像存储与展示这一段。
  - 目标：原始图与校正图随名片落盘、详情页优先展示原图、删除名片时一并清理。
  - 不得改动：`BusinessCard` 的既有字段语义（只回写文件名）。
  - 证据要求：落盘、回读、缺失退回、清理四条都要有测试。
- **AI 输出**：`CardImageStore` / `FileCardImageStore`、`confirmSave()` 落盘并回写文件名、`displayImageData` 优先原图、`delete()` 清理图像。
- **AI 的错误**：新测试里误写属性名 `harness.photoBytes`（run #32）。
- **修正**：改为正确属性名（commit `4d0cc5a`）。
- **证据**：**run #33**（commit `4d0cc5a`）success，测试数 233 → 249。

### 第 11 轮 — Week 5：独立标签管理页（P09）

- **提示词要点**
  - 限定上下文：标签已能挂在名片上，本次只做标签维度的管理页。
  - 目标：标签汇总与张数、按标签查看、删除整标签、新建标签三步校验。
  - 不做：不改名片夹与详情页的既有行为。
  - 证据要求：同名忽略大小写、重复计数、空名与未勾选拒绝保存都要有断言。
- **AI 输出**：`TagManagementViewModel` 与 `TagManagementView`（三态）、`AppRoute.tagManagement`、名片夹工具栏入口；`TagManagementViewModelTests` 19 个方法。
- **证据**：**run #36**（commit `57c872f`）success，测试数 249 → 268。

### 第 12 轮 — Week 5：导出接线（P10，5.3）

- **提示词要点**
  - 限定上下文：导出器已存在，本次只把它接进详情页并处理权限。
  - 目标：写入系统联系人与分享 VCF，覆盖 T19，含外发前的确认与「去设置」路径。
  - 不得改动：`VCardExporter` 既有输出格式（只新增临时文件能力）。
  - 证据要求：映射、授权分支、导出流程三段都要有测试。
- **AI 输出**：`ContactExportMapping`（纯函数映射）、`ContactExportAccess` / `ContactExportCoordinator`、`SystemContactExporter`、`VCardExporter.temporaryFileURL`、详情页确认框与提示；`ContactExportTests` 23 个方法。
- **AI 的错误**：① 用了不存在的 `CNLabelFax`（run #38）；② 测试里 `BusinessCard` 实参顺序写反（`jobTitle` 必须在 `department` 之前，run #39）。
- **修正**：改用 `CNLabelPhoneNumberWorkFax`（commit `99aeb75`）；改正实参顺序（commit `9af9715`）。
- **证据**：**run #40**（commit `9af9715`）success，测试数 268 → 301。

### 第 13 轮 — Week 6：回归矩阵与陈旧记录修正（6.1 前置）

- **提示词要点**
  - 限定上下文：先核对 `T01–T20` 与实际测试的对应关系，只改台账与追踪表。
  - 目标：建立逐条可核对的回归矩阵，并修掉与实现不同步的记录。
  - 不做：不动业务代码。
  - 证据要求：每条结论都要指明其断言来源（测试方法或人工验收项）。
- **AI 输出**：追踪表新增「Reference Test Suite T01–T20 回归矩阵」，逐条标注判定口径与人工验收项；修正持久化行的陈旧占位记录。
- **证据**：矩阵引用的断言来源见 `docs/验证报告.md`（run #40 / #42 / #46）。

### 第 14 轮 — 补漏：P03 手动调整边界（逻辑层 + 界面层）

- **提示词要点**
  - 限定上下文：规格要求「检测不可靠时允许手动调整或重拍」，先做纯逻辑，再做界面。
  - 目标：先交付「起点选取 / 命中测试 / 拖拽夹紧 / 凸性与面积合法性判定 / 重置」的逻辑层，再交付四角拖拽手柄与检测框叠层。
  - 不得改动：`ScanReviewViewModel.Phase` 只**新增 case**，既有初始化签名不变；手动框豁免自动检测的最小面积与长宽比，但**保留面积上限 0.98**（不得把整张图片当作名片）。
  - 证据要求：逻辑层要有单元测试；界面层给出编译证据并写明人工验收项。
- **AI 输出**：`CardBoundaryAdjustment`（20 个方法）、`ScanReviewViewModel.adjustingBoundary` 接线（16 个方法）、`BoundaryAdjustmentCanvas`（底图 + 四边形叠层 + 四角手柄）。
- **AI 的错误**：① `Phase` 新增 case 后 `ScanReviewView` 的 `switch` 不再穷尽（run #44）；② 测试里用 `CGPoint` 直接相等比较浮点累加结果（run #45）。
- **修正**：补 `case .adjustingBoundary` 分支（commit `5dc7262`）；改成逐分量 `accuracy: 0.0001` 比较（commit `efc2417`）。
- **AI 的自纠（未触发 CI 失败）**：画布最初用命名坐标空间，后简化为手势挂在画布自身用默认 local 坐标系；拖拽基准从「手指落点」改为「角的当前位置」，避免轻点一下角就跳到手指下。
- **证据**：**run #46**（commit `efc2417`）success，测试数 301 → 337；**run #48**（commit `8008a36`）success（纯界面改动，测试数不变）。

### 第 15 轮 — Week 6：能力边界分析（6.2）

- **提示词要点**
  - 限定上下文：只汇总已实现代码的错误原因，不新增功能代码。
  - 目标：产出 OCR 与字段抽取的分层边界分析，明确哪些是实测、哪些待验证。
  - 不做：不实现能力边界分析中提到的新功能。
  - 证据要求：结论要落到具体文件与规则；没有真实数据支撑的数值一律留白。
- **AI 输出**：`docs/能力边界分析.md`——按「检测 → 校正 → OCR → 字段抽取」分层汇总错误原因，逐字段列漏抽与误报，并**主动标出与规格 4.3 的偏差**：「多 Email 其余入 `notes` 或保留列表」未实现。
- **AI 的执行错误**：`npx openspec@1.13.2 validate` 退出码 **1**（`ETARGET: No matching version found`）。
- **修正**：改用仓库已有脚本 `npm run spec:validate`，退出码 **0**，输出 `Totals: 1 passed, 0 failed (1 items)`。
- **证据**：**run #50**（commit `7726e31`）success。

### 第 16 轮 — Week 6：修规格 4.3 的多 Email 偏差（4.x）

- **提示词要点**
  - 限定上下文：只处理上一轮主动标出的唯一功能偏差（「多 Email 其余入 `notes` / 保留列表」未实现），不新增其它功能。
  - 目标：让抽取器不再丢弃主邮箱之外的邮箱，并按规格 4.3 选定的承载方式落库。
  - 不得改动：`CardFieldKey` 的 11 个键与确认页字段数、评价脚本的逐字段统计口径、`BusinessCardRepository` 协议签名；不采用「新增需要数据库迁移的模型字段」这类破坏性改动。
  - 证据要求：新增 / 扩充单测并给出 CI 运行号；未执行项（真实名片准确率）继续标「待执行」。
- **AI 输出**：`ExtractedCardFields` 新增 `additionalEmails: [String]`（注释声明不进 `CardFieldKey`、不改变确认页字段数）；`assign` 对邮箱改为「首个占 `email`、其余按序追加、与主邮箱重复的不重复收集」；`makeCard()` 把额外邮箱拼成「其它邮箱：…」写入 `BusinessCard.notes`（无额外邮箱时保持 `nil`）；`BusinessCardFieldParserTests` 19 → 22 个方法。
- **AI 的错误**：本轮没有触发新的编译 / 测试失败。
- **修正**：无需修正；改动的接口面只用「新增带默认值的存储属性 + 新增可选参数」，未触碰既有签名。
- **证据**：**run #53** success。

### 第 17 轮 — Week 5：UI Golden Test 骨架（5.4）

- **提示词要点**
  - 限定上下文：只做 `tasks.md` 的 5.4，不新增页面、不改既有视图与模型的呈现。
  - 目标：交付可编译、可由 CI 跑通的截图对比骨架——录制与比对工具 + 首批组件级基线断言；真实录制与比对结论留待 Mac。
  - 不得改动：`BusinessCard` 模型、`BusinessCardRepository` 协议、既有视图的无障碍标识；不引入第三方快照库。
  - 证据要求：新增测试并给出 CI 运行号；截图对比本体未执行就写未执行，不得用「编译通过」冒充「比对通过」。
- **AI 输出**：`UISnapshotGolden`（用 `ImageRenderer` 把纯 SwiftUI 视图离屏渲染成位图 → 与 `testcards/ui-baselines/<名字>.png` 逐像素比对，给出差异像素占比与最大通道差；`RECORD_GOLDEN=1` 为录制模式；基线目录的仓库根复用 `FieldExtractionEvaluator.repositoryRoot` 的同一套规则）与 `UISnapshotGoldenTests`（`CardRowView` / `TagChipsView` / `EmptyCardHolderView` 三条组件级断言，缺基线时 `XCTSkip` 并注明录制方法）；`project.pbxproj` 登记两个新文件。
- **AI 的错误**：本轮没有触发新的编译 / 测试失败。
- **修正**：无需修正；未改动任何既有视图与协议签名。
- **证据**：**run #54**（commit `077b3ae`）success。**边界**：三条用例因基线缺失按设计跳过，逐像素比对的**结论**待 Mac 上用 `RECORD_GOLDEN=1` 录制基线后才产生；含 `List` 的整页留待 Mac + 模拟器的页面级 UI 测试，本轮不假装已覆盖。

### 第 18 轮 — 文档：Mac 端验收执行手册（为「拿到 Mac 后」预置可对照的步骤）

- **提示词要点**
  - 限定上下文：本轮只写文档，不写业务代码、不改任何视图与模型。
  - 目标：把「拿到 Mac 之后按什么顺序做什么、产出哪些产物」固化成一份可逐条对照的执行手册，覆盖 5.4 / 6.4 / 4.4 / T06 / 6.5 全部待办；同时说清「远程连 Mac 能做什么、不能做什么」。
  - 禁止项：不得把手册写成已执行记录；预期值只能来自 CI 已通过的结论与源码，凡未在本机跑过的一律标「待执行」；不得引用口语化的原始提示词。
  - 证据要求：文档内所有结论性描述须指回已有证据（CI run 号、源码位置、既有台账行）。
- **AI 输出**：新增 `docs/Mac端验收执行手册.md`，结构为 §0 前置条件（含远程连接硬边界、关键标识）→ §1 环境就绪 → §2 本机编译与全量单测 → §3 UI 基线录制与真实比对（5.4 收口）→ §4 M01–M36 人工验收 → §5 真实数据量化（4.4 与 T06）→ §6 归档 → §7 产物清单 11 项 → §8 注意事项。开篇显式声明「本手册是待执行清单，不是已执行记录」。
- **AI 的错误**：本轮没有触发新的编译 / 测试失败。
- **修正**：无需修正。
- **证据**：**run #56**（commit `7d46c97`）success（该次仅文档改动，CI 两个作业均为 success）。

### 第 19 轮 — 测试数据：生成 30 张合成名片图片（4.4 的输入侧）

- **提示词要点**
  - 限定上下文：只补齐 4.4 的输入侧数据（名片图片），不动抽取逻辑与评价脚本。
  - 目标：按 `testcards/ground_truth.json` 的真值逐字渲染出 30 张图片，使 4.4 具备可跑 OCR 的素材。
  - 禁止项：**不得虚构真值里没有的信息**——真值没有英文译名，因此不做翻译，`bilingual` 只用排版体现；不得引入真实个人敏感信息（数据集本身已声明全部虚构）；不得让生成脚本依赖本机特有路径而无法重跑。
  - 证据要求：脚本要自带自检（字体覆盖、排版溢出），并如实说明哪些结论本机无法验证。
- **AI 输出**：新增 `testcards/tools/generate_card_images.py` 与 `testcards/images/TC01–TC30.png`（横版 1400×900、竖版 900×1400）。六种降质（`tilted` / `complexBg` / `darkBg` / `lightBg` / `shadow` / `occluded`）由脚本确定性生成；脚本自带两项自检——字体覆盖（268 个字符无 `.notdef` 豆腐块，用私用区码位 U+E000 的位图作基准比对）与排版溢出（联系方式块必须留在卡面内、每行宽度不越界），两项均通过。
- **AI 的错误**：本机没有 `tesseract` 也没有 `pytesseract`（命令退出码 1），因此**助手无法自行核验生成图片「是否像名片」**；另外脚本在自查阶段发现并修正了 5 处问题（`font.getmask` 比较位图不可靠 → 改为渲染进固定尺寸 L 模式图再比字节；`use_zh_labels` 有冗余赋值且引用了数据集中不存在的字段；自定义 `Int()` 辅助函数与 Swift 命名习惯冲突 → 删除；旋转用 `expand=False` 导致卡角被裁 → 改 `expand=True` 并重算居中位置；补充排版溢出自检）。这些都在提交前改掉，未进入 CI。
- **修正**：上述 5 处均在本地修正；「图片观感」这一条无法自动验证，已如实告知需人工目视确认 TC01（中文横版）/ TC04（竖版）/ TC17（深底浅字）/ TC20（手指遮挡）四张。
- **证据**：**run #57**（commit `724b1d0`）success。**边界**：本轮只能证明「字符有字形、排版无溢出」，不能证明「看起来像真实名片」，也不能证明「OCR 认得出」。

### 第 20 轮 — 测试：固化 OCR 原文导出用例（4.4 的第 ② 步）

- **提示词要点**
  - 限定上下文：只做 4.4 的中间环节——把「图片 → OCR 原文」的导出动作固化成可复跑的用例，不动抽取逻辑与评价脚本。
  - 目标：交付一个在具备 Vision 的环境里执行一次即可产出 30 个 `testcards/ocr/<卡片ID>.txt` 的用例，为评价脚本备好输入。
  - 禁止项：不得让该用例在 CI 上自动运行并改写数据集；不得把「编译通过」写成「导出成功」；不得在无 OCR 原文的情况下给出准确率数字。
  - 证据要求：给出 CI 运行号，并明确标注哪些结论只能在 Mac 上产生。
- **AI 输出**：新增 `CamCardCloneTests/OCRTextCorpusExporterTests.swift`，用 `VisionOCRService` 逐张识别 `testcards/images/`，把原文写到 `FieldExtractionEvaluator.ocrTextURL` 约定的 `testcards/ocr/<卡片ID>.txt`，并逐张打印行数、汇总「已导出 N/30」。用例**默认跳过**，需显式设置 `EXPORT_OCR_TEXT=1` 才执行（与第 17 轮 UI 基线的 `RECORD_GOLDEN` 同一思路）。同时在 `docs/Mac端验收执行手册.md` §5.1 ② 补上 Mac 上的执行命令（`xcodebuild ... -only-testing:` + 环境变量写法）。
- **AI 的错误**：本轮没有触发新的编译 / 测试失败。
- **修正**：无需修正。文件头注释如实声明两条边界：①对整张图片识别、不经过「检测 → 透视校正」（4.4 衡量的是字段抽取器在 OCR 原文上的准确率，检测与校正属 T06 / T07）；②合成图比真实拍照干净，由此得到的准确率**偏乐观**。
- **证据**：**run #58**（commit `e6ee54b`）success。**边界**：本机可验证的只有「编译通过 + 按设计跳过」，30 个 txt 的真实产出仍需在 Mac 上执行一次。

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
| 13 | 生成名片图脚本的 5 处问题（位图比对方式不可靠、冗余赋值引用不存在的字段、自造 `Int()` 辅助函数、旋转裁掉卡角、无排版溢出自检） | 本机，未进 CI | 提交前自查逐一改正（`724b1d0`） |

这些错误都由 CI、命令退出码或提交前的自查**当场暴露**，没有一条是靠人工肉眼发现后悄悄改掉的；修正都单独提交，台账里保留「哪个 run 因何失败」。第 13 条属提交前自查发现，未产生失败运行。

## 4. 实际执行的命令与结果

| 命令 | 结果 |
| --- | --- |
| `git -c user.name="刘润东" -c user.email="760592343@qq.com" commit -F <临时信息文件>` | 退出码 0，作者为本人（如 `7726e31`、`8008a36`） |
| `git push origin main` | 退出码 0，触发 `iOS CI`；本文件编写前最后一次为 run #58 |
| `npm run spec:validate`（即 `openspec validate --all --strict`） | 退出码 0，`1 passed, 0 failed` |
| `npx openspec@1.13.2 validate --all --strict` | 退出码 1（版本不存在），已改用上一条 |
| 经 GitHub 公开 API 读取 `actions/runs` 与 `jobs` | run #2 / #4 / #6 / #9 / #10 / #14 / #16 / #20 / #21 / #22 / #25 / #27 / #28 / #30 / #31 / #33 / #34 / #36 / #40 / #46 / #48 / #49 / #50 / #53 / #54 / #55 / #56 / #57 / #58 的 `OpenSpec Validate` 与 `Build & Test (iOS Simulator)` 均 success |
| `xcodebuild ... build-for-testing` / `Cmd+U` | **未执行**：本机为 Windows，无 macOS 与 Xcode，故不存在本机编译与测试记录 |
| `openspec archive`（6.5） | **未执行**：必需验证（6.4 人工验收）未完成，按规则 10 不得提前归档 |

## 5. 复现与补验

1. 在仓库 Actions 页手动触发 `iOS CI`（已配置 `workflow_dispatch`），或任意推送到 `main`。
2. 失败时无需登录：workflow 的 `Surface errors as annotations` 步骤会把 `error:` 行提升为注解，可用 `repos/<owner>/<repo>/check-runs/<job_id>/annotations` 直接读到。
3. 拿到 Mac 后按 `docs/Mac端验收执行手册.md` 逐阶段执行（环境就绪 → 本机编译与全量单测 → UI 基线录制与比对 → M01–M36 人工验收 → 4.4 与 T06 真实数据量化 → 归档）；`docs/验证报告.md` 的「待补验步骤」只列要点，具体命令与产物清单以手册为准。
