# Card Scanner Specification

## Purpose
把名片扫描闭环中「原始文本 → 结构化字段」的判定规则写细，覆盖无标签行的归属裁决、无标签号码的分类与职位识别，并重申「无法确认归属时保持为空、不得依据语义补全」这一硬约束。

## ADDED Requirements
### Requirement: Unlabeled line classification
系统 SHALL 对没有字段标签的文本行按内容特征判定归属；当一段文本同时命中多种字段特征（如既含行业词又含地址特征）时，SHALL 依据内容形态裁决而不是依据词表的命中顺序；无法裁决时相关字段 SHALL 保持为空值，系统 SHALL NOT 把可能属于其它字段的内容填入。

#### Scenario: Company name without a street number
- **WHEN** 名片上有一行是公司名（以「有限公司」「工作室」「Ltd.」「Studios」等结尾），且该行不含门牌号或行政区划词
- **THEN** 该文本进入公司字段，地址字段与姓名字段保持为空

#### Scenario: Address that happens to contain an industry word
- **WHEN** 一行文本是地址，其中偶然包含行业词或单字地址特征（如「张江高科技园区」含「科技」「园区」、「写字楼」含「楼」）
- **THEN** 该文本进入地址字段，公司字段保持为空

#### Scenario: Ambiguous line stays empty
- **WHEN** 一行文本同时具备两种字段特征，且形态规则无法裁决
- **THEN** 相关字段保持为空，不产生任何虚构值

### Requirement: Phone number classification without labels
无标签号码 SHALL 依据号码形态（国家码、首位、位数）判定归属；当形态不足以区分手机与固话时，系统 SHALL 按「手机 → 固话 → 传真」的顺序把它填入第一个空槽位，使同一张卡上的多个无标签号码各占一个槽位，且 SHALL NOT 覆盖任何已有值。

#### Scenario: Unlabeled number starting with zero
- **WHEN** 一行只包含一个无标签号码，且其首位为 `0`（如 `0755-1234567`）
- **THEN** 该号码进入固话字段

#### Scenario: Unlabeled Chinese mobile number
- **WHEN** 一行只包含一个无标签号码，以 `1` 开头且为 11 位数字
- **THEN** 该号码进入手机字段

#### Scenario: Unlabeled number with an international prefix
- **WHEN** 一行只包含一个无标签号码，且形态不足以区分手机与固话（如 `+1-555-0307`）
- **THEN** 该号码进入「手机 → 固话 → 传真」中的第一个空槽位，不产生新字段、也不覆盖已有值

#### Scenario: Several unlabeled numbers fill distinct slots
- **WHEN** 一张卡上有多个形态不足以区分手机与固话的无标签号码（如 `+1-555-0923` / `+1-555-0924` / `+1-555-0925`）
- **THEN** 这些号码依次进入手机、固话、传真字段，互不覆盖

#### Scenario: Label takes precedence over shape
- **WHEN** 号码前带有标签（如「手机」「传真」「Tel」「Fax」）
- **THEN** 按标签判定字段归属，号码形态只用于校验

### Requirement: Job title recognition
系统 SHALL 识别名片上的职位行，包括不在一份种子词表内的常见职务（如「教师」「注册会计师」「编导」「店长」「导游」「Producer」「Data Scientist」）；职位判定 SHALL 基于可外推的形态特征与通用职务词，SHALL NOT 依赖针对测试语料逐条列举的字符串；无法确认是职位时，职位字段 SHALL 保持为空值。

#### Scenario: Common job outside the seed list
- **WHEN** 名片上有一行是常见职务（中文或西文），但它不在既有词表内
- **THEN** 该文本进入职位字段

#### Scenario: Tagline is not a job title
- **WHEN** 一行是宣传标语或口号，既无职务后缀证据也无词表命中
- **THEN** 职位字段保持为空

#### Scenario: Job title beside company on one line
- **WHEN** 职位与公司名出现在同一行
- **THEN** 两者分别进入职位字段与公司字段
