# Fix Field Classification Errors

## Why
字段级评价已于 2026-11-01 在物理 Mac 上真跑（`Executed 12 tests, with 0 failures`，日志 `docs/evidence/mac-2026-11-01/mac-field-accuracy.log`）：整体「正确」51.9%（140/270）、缺失字段误报率 3.8%（4/105）、错误明细 29 条。逐条归因后，其中三类与**解析器自己的判定规则**直接相关，而且已经造成 4 处 `invented`（虚构）判定：

1. **字段归属错**：`蓝海设计工作室` 因含「室」被强地址特征子串命中而落进地址（TC04）；`Dark Tower Studios` 因含 `tower` 同理落进地址（TC17）——两处的公司字段同时漏抽。
2. **无标签号码分类**：`phoneTargetWithoutLabel` 在形态不足以判定时**兜底 `return (.mobile, value)`**，把 `+1-555-0307` / `+1-555-0821` 判为手机（真值为固话），一次产生「手机虚构 + 固话漏抽」两个错误（TC07 / TC21）。
3. **职位召回缺失**：职位判定依赖 23 个词的封闭词表，11 条职位错误（8 条完全漏抽）全部落在词表之外（教师 / 注册会计师 / 编导 / 店长 / 导游 / Producer / Data Scientist…）。

这 4 处「虚构」填的文本都真实存在于名片上，属**分类准确率**问题而非凭空编造，未违反「未在文本中确认的字段一律 nil」的硬约束；但 `card-scanner` 的「Structured field extraction」需求原文已写明「无法确认归属的字段 SHALL 保持为空值，系统 SHALL NOT 依据语义补全名片上不存在的信息」——「形态判不出就默认手机」与「公司名落进地址」都与这条需求相抵触。

因此需要一次**只改判定规则、不改数据与评价口径**的独立变更。`docs/能力边界分析.md` §6.3 已把这件事记为「规则优化的取舍另开 change 提案」，本变更就是该提案。

## What Changes
1. 公司 / 地址的仲裁：由「词表命中顺序（先地址后公司）」改为**特征竞争**，并按内容形态裁决（含门牌号或行政区划词判地址、公司后缀位于段尾判公司、无法裁决则留空）。
2. 无标签号码：删除「判不出就默认手机」的兜底，改为按**国家码 / 首位 / 位数**判定，形态不足以区分时**留空**。
3. 职位：由封闭词表改为「**职务后缀形态特征 + 通用职务词**」双路判定，并保留原有防线（整段无证据时不得凭空判为职位）。
4. 为上述三类各补单测，另加**语料外样例**专项用例防止针对 30 张语料过拟合。
5. 重跑字段级评价，把前后对比与残留错例写入 `docs/验证报告.md`、`docs/能力边界分析.md` §6.3，并同步 `docs/规格测试追踪表.md` 的相关行。

## Capabilities
### New Capabilities
- 无。本变更不新增能力，只把既有 `card-scanner` 的字段结构化行为收紧到规格原本要求的水准。

### Modified Capabilities
- `card-scanner`：以 ADDED Delta 追加三条需求——`Unlabeled line classification`、`Phone number classification without labels`、`Job title recognition`。它们是把既有「Structured field extraction」的可观察行为写细，不改变字段集合与确认页形态。
- **归档顺序说明**：`openspec/specs/` 目前为空（首个变更 `replicate-camcard-core-slice` 尚未归档），因此本变更同样以 ADDED Delta 表达。归档时须**先归档首个变更、再合并本变更**，合并时若与本变更的三条需求与既有「Structured field extraction」重叠，则按 MODIFIED 处理，不得形成同名 ADDED 冲突。

## Impact
- 代码：`CamCardClone/Scanning/BusinessCardFieldParser.swift`（词表与判定顺序）、`CamCardCloneTests/BusinessCardFieldParserTests.swift`（新增用例）。
- CI：`.github/workflows/ios-ci.yml` 的 `ios` 作业需要新增**字段级报告的注解通道**（仿既有 `DETECTCORPUS` 的 `split -l 8` 分块），否则报告在本机（Windows）读不回来。
- **不得改动**：`BusinessCard` 与 `BusinessCardRepository` 的接口、`ExtractedCardFields` 的字段集合与构造签名、`CardFieldKey` 的 11 个键、确认页字段数、评价脚本的统计口径、`testcards/ground_truth.json` 的任何一个值。
- 台账：`docs/验证报告.md`、`docs/能力边界分析.md`、`docs/规格测试追踪表.md`、`docs/AI协作记录.md`。
- 回归：既有 344 个单测必须继续通过（其中 `BusinessCardFieldParserTests` 22 个方法为直接相关的回归面）。

## Out of Scope
- **OCR 识别质量**：TC12（`edu→eau`）、TC13（`Ltd.→Lta.`）、TC15（`器械→嚣械`）、TC28（「邮箱：」→「邮：」）属识别环节，本次只改解析规则，**不修 OCR、不做残缺标签的猜测补全**（猜测补全反而会引入虚构）。这 4 条作为**已知残留**如实保留在台账里。
- **真实照片复核**：需物理设备与实物名片（`docs/UI验收清单.md` M18），本机不可做。
- **整体正确率阈值**：本次判据是「按类别归零」，不承诺把 51.9% 提到某个数字；合成图上的数字本身偏乐观。
- **长尾职业**：规则只能覆盖有构词规律的常见职务，冷门职业（如「手作人」「脱口秀演员」）仍可能漏抽，属能力边界，不在本次内。
- `isReliable()` 阈值标定（T06）：属卡片检测环节，依赖真实照片。

## Delivery Split
本变更在一个提交范围内完成：规格 Delta → 规则实现 → 单测 → 重跑评价 → 台账回填。未真正跑通的项在 `tasks.md` 中保持未勾选，不得预先勾选。
