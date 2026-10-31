# CamCardClone 的 TRAE 提示词

本文件是**可复制的教学输入模板**，不是实际发生过的对话记录。Week 1–2 的产物已存在于本仓库，对应提示词可作为复现模板；真实会话需按第 9 节另行导出，不能用本文件充当对话证据。

课程作业第十六节的要求在本文件中体现为三条硬约束，每段提示词都必须带上：

- **限定上下文**：先读书写现存的 `PROJECT_RULES.md`、`docs/规格说明书.md`、`openspec/` 产物，只改被点名的文件。
- **保护回归**：明确「不得改动」的接口、模型与已通过的测试。
- **要求真实证据**：编译、测试、`openspec validate` 必须给命令与退出码；未执行就说未执行。

## 1. Week 1 — 黑盒观察与规格

```text
请先检查当前工作区，读 PROJECT_RULES.md 与 openspec/config.yaml，确认工程里还没有任何业务代码。
然后只做观察与规格，不写业务代码。

以「名片全能王」为黑盒对象，界定本次功能切片：名片数字化与联系人管理的完整闭环。
输出 docs/规格说明书.md，至少包含：术语表、复刻边界、明确不复刻的越界功能清单、
锁定的参考环境（App 版本、iOS 版本、设备、语言、登录状态）、BusinessCard Schema、
页面清单 P01–P10、状态清单 S1–S4 / D1–D3 / E1–E5、Reference Test Suite T01–T20。

BusinessCard 必须逐字段列出：originalImageName、processedImageName、name、company、jobTitle、
mobile、phone、fax、email、website、address、postalCode、department、tags、notes、createdAt，
并注明哪些必填、哪些可为 nil。

同时产出 testcards/ground_truth.json：30 张合成名片，覆盖中文、英文、中英双语、竖版、
多电话、多邮箱、字段缺失、拍摄质量差、复杂 Logo 背景等类别，每张带 Ground Truth。

不要出现用户注册、会员、订阅支付、云同步、CRM、二维码名片等越界功能。
不要写 Swift 代码。
```

## 2. Week 2 — 架构、UI 与数据模型

```text
请按已审查的规格建立 Week 2 骨架，先构建稳定的软件骨架，不要做 OCR。

只新建以下内容，不要顺带实现 Week 3 及以后的能力：
BusinessCard 值类型（Foundation-only，Codable + Equatable + Hashable）与 Mock 数据；
BusinessCardRepository 协议与 InMemoryBusinessCardRepository（CRUD / 搜索 / 标签）；
AppRouter + NavigationStack（push / pop / popToRoot）；
@MainActor 的 CardHolderViewModel 与 CardDetailViewModel，覆盖 S1–S4 / D1–D2；
名片夹首页、空状态、名片行、详情/编辑页、扫描入口占位。
扫描入口只做占位取景页，不代表真实 OCR 已实现。

同时生成可直接用 Xcode 打开的 CamCardClone.xcodeproj（app target + test target + 共享 Scheme），
并写第一批单元测试：Model、Repository、ViewModel 三层，覆盖 T01、T12、T13、T14、T15、T16、T17、T20。

「姓名为空或全空格必须拒绝保存并保持编辑态」这条要有独立测试。
完成后给出编译与运行测试的真实命令、退出码与日志路径；未执行就说未执行。
```

## 3. Week 3 — 相机与 OCR

```text
现有 ScannerEntryView 是占位页，只用于验证 T02/T12。请不要修改 BusinessCard 数据模型
和 BusinessCardRepository 协议，仅按下列顺序接入相机与 OCR：

1. 相机预览、相机权限申请与拒绝分支、拍摄、取消、重拍、返回，替换占位页，覆盖 T02–T04。
2. 从照片库导入并进入识别流程，覆盖 T05。
3. 名片区域检测与自动裁剪，落成可单测的函数；再做透视校正与方向校正，覆盖 T06。
4. 定义 OCRService 协议，实现一个输出「原始识别文本」的实现，覆盖 T07。
   本阶段只要求产出 OCR Raw Text，不做字段解析。

拍摄与校正的输入输出要能脱离相机单独测试（传入固定图像，断言输出），
相机权限拒绝、相册权限拒绝、中途退出这三条异常路径必须有测试，覆盖 T20 的相关场景。

保留全部已通过的 Week 2 测试，不得为了通过而修改其预期。
完成后分别报告：编译退出码、单元测试数量与结果、哪些项在真机上验证过、哪些仍是待验。
```

## 4. Week 4 — 结构化抽取与人工校正

这是整个作业最重要的一周，提示词必须写得比前几周更窄。

```text
现有 OCRService 已能返回 OCR 原始文本。请不要修改 OCRService 接口和现有 MVVM 架构，
仅实现 BusinessCardFieldParser，把 OCR 结果映射为 name、company、jobTitle、mobile、phone、
fax、email、website、address、postalCode、department。

硬性规则：无法确认的字段必须返回 nil，绝不允许根据语义生成原图中不存在的信息。
名片上没有 Website 时不得产出 Website，这是 T09。

必须先处理这几类歧义，并为每一类写独立测试：
字段歧义（如 "Apple" 是公司、产品还是地址）；
人名与公司混淆（如 "Jordan Lee" 与 "Lee Consulting"）；
多电话号码归属（Mobile / Office / Fax，含 T10）；
中英文混排（如 "朱宏明 Professor Tongji University"）；
同一字段多个 Email 或多条地址；
OCR 错字与残缺行。

广度：姓名识别、公司识别、职位识别、电话识别、Email 识别、地址识别。
完成后用 testcards/ground_truth.json 统计字段级准确率与「缺失字段被误报」的比例，
输出可复现的统计脚本或测试，并把每类的错误样例与原因写入错误分析文档。

打通人工校正链路：识别结果 → 结构化字段 → 用户检查 → 人工修改 → 确认 → 保存，覆盖 T11–T12。
用户至少能修改姓名、公司、职位、手机、电话、Email、Website、地址；取消修改必须能丢弃草稿。

不得改动 BusinessCard 数据模型与已通过的测试。完成后重跑全部测试并报告结果。
```

## 5. Week 5 — 名片管理、持久化与导出

```text
请补齐名片管理的完整交互，并接入真正的持久化，覆盖 T13–T19。

1. 列表、详情、搜索（姓名/公司/职位/电话/Email）、标签（创建/添加/按标签查看/删除）、
   备注、编辑、删除的完整交互，覆盖 T13–T17。
2. 新增一个持久化实现替换 InMemoryBusinessCardRepository 在 App 层的注入点，
   但不得改动 BusinessCardRepository 协议签名，也不得改动已通过测试的调用方。
   验收：扫描 → 识别 → 人工修改 → 保存 → 强杀 App → 重启 → 该名片仍在，
   原始图像、修改后的字段、标签、备注全部保留，覆盖 T18。
3. 实现联系人导出（写入系统联系人，或导出 VCF/vCard），校验姓名、公司、职位、
   电话、Email、地址的字段映射，覆盖 T19。
4. 增加 UI Golden Test 与首批截图对比。

不得为了通过测试而放宽断言；持久化实现必须与内存实现通过同一套 Repository 测试。
报告真实运行结果，受阻项保持未勾选。
```

## 6. Week 6 — 全量验收与回归

```text
本周不再增加大型新功能，只做验收、回归与归档。

请对照 openspec/ 的规格与 Delta 审查完成版，逐条给出确定性 20 条 Reference Test Scenarios
T01–T20 的实际结果，任何一项未达到 100% 通过都要如实列出而不是回避。

分别给出证据：单元测试数量与结果、iOS 编译退出码、实际 UI 测试结果、模拟器人工验收结论、
官方 openspec validate --all --strict 的日志路径。
不得因编译成功或 build-for-testing 成功而声称模拟器测试已通过。

汇总两类错误分析：OCR 的错误样例与原因；字段抽取的错误样例与原因。
明确写出 AI 的能力边界：哪些情况它一定会错、哪些必须由人校正、哪些字段绝不允许它补全。

检查 tasks.md 中所有受阻项是否仍保持未勾选，并列出可执行的补验命令。
```

## 7. 通用回归保护提示词

每次修改已有代码时追加这段，用于训练 AI Context Control 与增量开发。

```text
目前 TC07 中公司名被错误识别为姓名。请先分析原因，只修改字段分类规则，
不要改动 BusinessCard 数据模型、OCRService 接口和现有已通过的测试。
修改完成后重新运行全部测试，并逐一报告哪些测试从通过变为失败、为什么。
如果修复需要改动已通过的测试预期，先停下来向我说明，不要自行修改。
```

## 8. 归档

```text
先检查真实验证记录和 tasks.md 的必需任务，未完成时不要归档。
确认四项能力 app-shell、card-library、card-holder、card-scanner 均为 ADDED（本工程没有 MODIFIED 基线）。
完成后把活动变更移动到 openspec/changes/archive/ 下以真实日期命名的目录，
并把四个 ADDED 能力合并为主规格 openspec/specs/<capability>/spec.md。
新主规格使用 Requirements，不得残留 ADDED / MODIFIED 标题。
归档后再次运行 openspec validate --all --strict 并报告路径。
```

## 9. 真实会话的导出

本文件是模板，不能作为「AI 协作记录」的证据。作业要求的是真实记录，请在每次与 TRAE 的实际协作后自行导出，并至少注明：

- 使用的模型与 TRAE / IDE 版本；
- 该轮的原始提示词（可直接引用本文件对应小节，但须标出实际改动过的部分）；
- AI 的实际输出摘要与它犯的错误；
- 你人工修改了什么、为什么；
- 实际执行的命令与退出码。

真实会话记录与人工修改痕迹，另行保存，不要与本模板混为一谈。**本项目的真实协作记录见 `docs/AI协作记录.md`**：逐轮记录提示词要点（按「限定上下文 / 保护回归 / 要求真实证据」三条硬约束归纳，不逐字引用会话原话）、AI 输出、AI 犯的错与修正、人工干预、命令与退出码；该项目全程按 `PROJECT_RULES.md` 第 2 条逐项推进，未出现一次性生成整个 App 的提示词。该文件里「TRAE / IDE 版本」一项需填本机实际版本号。
