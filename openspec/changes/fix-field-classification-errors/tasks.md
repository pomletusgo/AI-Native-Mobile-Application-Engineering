## 1. 规格与准备
- [ ] 1.1 提交 `card-scanner` 的三条 ADDED 需求（`Unlabeled line classification` / `Phone number classification without labels` / `Job title recognition`），并跑 `npm run spec:validate`（`openspec validate --all --strict`）退出码 0，记录输出。
- [ ] 1.2 给 `.github/workflows/ios-ci.yml` 的 `ios` 作业新增**字段级报告的注解通道**（仿既有 `DETECTCORPUS` 的 `split -l 8` 分块发 `::notice::`），使报告能在本机（Windows）读回。

## 2. 规则实现（`CamCardClone/Scanning/BusinessCardFieldParser.swift`）
- [ ] 2.1 公司 / 地址改**特征竞争**（D1）：段内含门牌号类数字或行政区划词 → 地址；公司后缀位于**段尾** → 公司；其余按地址；仍不确定则留空。取消单字级地址特征（室 / 号 / 楼 / 层）在整词内部生效，`工作室` / `写字楼` 按整词处理。
- [ ] 2.2 无标签号码改**形态判定、判不出留空**（D2）：删除 `phoneTargetWithoutLabel` 末尾的 `return (.mobile, value)` 兜底，改按 `+86` 且 ≥13 位 → 手机、首位 `0` → 固话、≥11 位 → 手机、其它国际区号且位数低于移动号阈值 → 固话、其余留空。
- [ ] 2.3 职位改「**后缀形态 + 通用职务词**」双路（D3）：中文职务后缀（师 / 员 / 长 / 监 / 理 / 士 / 教练 / 主任 / 总监…）且长度 2–6 字、不含数字与地址特征；词表路补入通用中文职务词与西文职务词，并把匹配由子串改为**整词**；保留「整段无证据不得判为职位」的防线。

## 3. 测试
- [ ] 3.1 三类规则各补单测（`CamCardCloneTests/BusinessCardFieldParserTests.swift`）：字段归属（公司不被地址抢走 / 地址不被公司抢走 / 歧义留空）、无标签号码（`+1-555-0307`、`13800000001`、`0755-1234567`、标签优先）、职位（词表外常见职务 / 标语不判职位 / 职位与公司同行）。
- [ ] 3.2 补**语料外构造样例**专项用例（D4，防过拟合）：如「摄影师」「调度员」「+44-20-7946-0958」等未出现在 30 张语料中的输入，验证规则可外推。
- [ ] 3.3 既有 344 个单测**无回归**（其中 `BusinessCardFieldParserTests` 22 个方法为直接回归面），CI `Build & Test (iOS Simulator)` 作业通过。

## 4. 评价与台账
- [ ] 4.1 重跑 `FieldExtractionEvaluatorTests` 取得**前后对比**：判据为错误明细中三类错例**归零**、`invented` 由 4 降为 **0**；保存报告到 `docs/evidence/` 并在 CI 注解通道读回。
- [ ] 4.2 回填 `docs/验证报告.md`、`docs/能力边界分析.md` §6.3、`docs/规格测试追踪表.md`、`docs/AI协作记录.md`：写明三类归零的前后数值、OCR 噪声 4 条（TC12 / TC13 / TC15 / TC28）作为**已知残留**保留、以及「判不出留空」的宁漏不假取舍。
- [ ] 4.3 保持「待执行」的项如实标注：真实照片准确率复核（M18，缺物理设备与实物名片）、`isReliable()` 阈值标定（T06）。
