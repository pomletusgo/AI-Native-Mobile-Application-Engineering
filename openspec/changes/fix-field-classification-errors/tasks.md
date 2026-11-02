## 1. 规格与准备
- [x] 1.1 提交 `card-scanner` 的三条 ADDED 需求（`Unlabeled line classification` / `Phone number classification without labels` / `Job title recognition`），并跑 `npm run spec:validate`（`openspec validate --all --strict`）退出码 0，记录输出。
- [x] 1.2 给 `.github/workflows/ios-ci.yml` 的 `ios` 作业新增**字段级报告的注解通道**（仿既有 `DETECTCORPUS` 的 `split -l 8` 分块发 `::notice::`），使报告能在本机（Windows）读回。做法是在 `FieldExtractionEvaluatorTests` 里给报告逐行加 `FIELDRPT` 前缀，workflow 内 `grep "^FIELDRPT"` 后按 8 行分块发 `::notice::`；提交 `d74450e`（`iOS CI` run #72）后以 `check-runs/125116046722/annotations` 免登录读回，落盘为 `docs/evidence/ci-2026-11-02/field-accuracy-report.md`。

## 2. 规则实现（`CamCardClone/Scanning/BusinessCardFieldParser.swift`）
- [x] 2.1 公司 / 地址改**特征竞争**（D1）：段内含门牌号类数字或行政区划词 → 地址；公司后缀位于**段尾** → 公司；两者都无证据则**不下判**（返回 `nil` 继续下渗到部门 / 姓名，不默认塞进地址）。取消单字级地址特征（室 / 号 / 楼 / 层）在整词内部生效，`工作室` / `写字楼` 按整词处理。
- [x] 2.2 无标签号码改**形态优先 + 空槽位落位**（D2）：删除 `phoneTargetWithoutLabel` 末尾的 `return (.mobile, value)` 兜底，改为 `+86` 且 ≥13 位 → 手机、首位 `0` → 固话、≥11 位 → 手机；形态判不出时按「手机 → 固话 → 传真」填第一个**空槽位**（函数需读 `fields` 快照）；形态能判出但目标槽位已占用则返回 `nil`（宁漏不假）。TC07 / TC21 的 4 条错例因 `ground_truth.json` 标注不一致记为**已知残留**，不动数据。
- [x] 2.3 职位改「**后缀形态 + 通用职务词**」双路（D3）：中文职务后缀（师 / 员 / 长 / 监 / 理 / 士 / 教练 / 主任 / 总监…）且长度 2–6 字、不含数字与地址特征；词表路补入通用中文职务词与西文职务词，并把匹配由子串改为**整词**；保留「整段无证据不得判为职位」的防线。

## 3. 测试
- [x] 3.1 三类规则各补单测（`CamCardCloneTests/BusinessCardFieldParserTests.swift`）：字段归属（公司不被地址抢走 / 地址不被公司抢走 / 歧义不下判）、无标签号码（`+1-555-0307` 落首个空槽、`13800000001` → 手机、`0755-1234567` → 固话、标签优先、多枚无标签号码分占手机 / 固话 / 传真三槽）、职位（词表外常见职务 / 标语不判职位 / 职位与公司同行）。
- [x] 3.2 补**语料外构造样例**专项用例（D4，防过拟合）：如「摄影师」「调度员」「+44-20-7946-0958」等未出现在 30 张语料中的输入，验证规则可外推。
- [x] 3.3 既有 344 个单测**无回归**（其中 `BusinessCardFieldParserTests` 22 个方法为直接回归面），CI `Build & Test (iOS Simulator)` 作业通过。

## 4. 评价与台账
- [x] 4.1 重跑 `FieldExtractionEvaluatorTests` 取得**前后对比**：整体「正确」51.9%（140/270）→ **57.8%（156/270）**，误报率 3.8%（4/105）→ **1.9%（2/105）**，错误明细 29 → **11** 条。「字段归属错」与「职位召回缺失」两类错例**归零**（职位 56.7% → 93.3%、公司 76.7% → 83.3%、地址 33.3% → 36.7%），TC23 固话 / 传真漏抽修好（固话 36.7% → 40.0%、传真 10.0% → 13.3%）。**未达「`invented` 归零」**：`invented` 由 4 降为 **2**（不是 0），剩余 2 条即已授权的 TC07 / TC21「`ground_truth.json` 标注内部不一致」残留（电话类不归零，手机 / 固话错误 6 → 4），如实记为**非规则缺陷**。报告落盘 `docs/evidence/ci-2026-11-02/field-accuracy-report.md`（改前基线 `docs/evidence/mac-2026-11-01/mac-field-accuracy.log`），经 `check-runs/125116046722/annotations` 免登录读回。
- [x] 4.2 回填 `docs/验证报告.md`、`docs/能力边界分析.md`（§0 / §3 / §6.3）、`docs/规格测试追踪表.md`、`docs/AI协作记录.md`：写明两类归零的前后数值；剩余 11 条按三类如实归因——**数据集标注内部不一致 4 条**（TC07 / TC21，非规则缺陷）、**OCR 噪声 6 条**（TC12 邮箱 `edu→eau`、TC13 公司 `Ltd.→Lta.` 连带姓名归属、TC15 公司 `器械→嚣械`、TC20 / TC26 邮箱原文含空格）、**能力边界 1 条**（TC28 公司 `Apple` 无公司后缀，按 D1「无证据不下判」保持 `nil`，属刻意取舍）；并写明「形态判出但目标槽位已占用则留空」的宁漏不假取舍。
- [ ] 4.3 保持「待执行」的项如实标注：真实照片准确率复核（M18，缺物理设备与实物名片）、`isReliable()` 阈值标定（T06）。（**2026-11-02 核定：仍待执行，故本变更保持未勾、暂不归档**；两项均需物理 iPhone 与实物名片，`testcards/real-photos/` 目前不存在。本变更的归档阻塞项与不可颠倒的顺序——**先归档 `replicate-camcard-core-slice`，再归档本变更**——见 `docs/Mac端验收执行手册.md` §6.0 / §6.1）
