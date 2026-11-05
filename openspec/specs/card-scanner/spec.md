# card-scanner Specification

## Purpose
定义从拍摄/导入到名片保存的整条识别闭环的可观察行为，覆盖权限、区域检测、OCR、字段结构化与人工校正，并明确「AI 不得补全名片上不存在的信息」这一硬约束。

## Requirements

### Requirement: Scanner entry
名片夹首页 SHALL 提供扫描入口，点击后 SHALL 进入拍摄取景页面，页面 SHALL 提供拍摄、相册导入、返回与取消操作。

#### Scenario: Enter scanner from holder
- **WHEN** 用户在名片夹点击扫描入口
- **THEN** 进入拍摄取景页面

#### Scenario: Cancel from camera
- **WHEN** 用户在拍摄页面取消或返回
- **THEN** 返回名片夹且不产生任何名片

### Requirement: Capture and import
系统 SHALL 支持通过相机拍摄名片以及从相册导入名片图片，两种来源 SHALL 进入同一套识别流程。

#### Scenario: Capture with camera
- **WHEN** 用户在取景页面拍摄一张标准名片
- **THEN** 该照片进入名片区域检测与后续识别流程

#### Scenario: Import from album
- **WHEN** 用户从相册选择一张名片图片
- **THEN** 该图片进入与拍摄一致的识别流程

#### Scenario: Retake
- **WHEN** 用户在拍摄或检测阶段选择重拍
- **THEN** 返回取景页面，之前的临时图片被丢弃

### Requirement: Card boundary detection
系统 SHALL 检测图片中名片的区域并据此裁剪；对于倾斜拍摄的名片 SHALL 进行方向或透视校正；当自动检测结果不可靠时 SHALL 允许用户手动调整或重拍。

#### Scenario: Detect card on plain background
- **WHEN** 拍摄一张背景干净的名片
- **THEN** 系统给出覆盖名片主要区域且不含大块背景的检测框

#### Scenario: Detect tilted card
- **WHEN** 拍摄一张倾斜的名片
- **THEN** 系统对检测到的名片区域进行摆正或透视校正后再交付识别

#### Scenario: Detection fails
- **WHEN** 图片中无法确定名片区域
- **THEN** 提示用户重拍或手动调整，不直接把整张图片当作名片

### Requirement: Optical character recognition
系统 SHALL 对校正后的名片图像进行文字识别并产生原始文本结果；识别过程中 SHALL 提供进行中反馈；识别失败 SHALL 提示重试或转为手动录入。

#### Scenario: Recognize a standard card
- **WHEN** 对一张标准测试名片执行识别
- **THEN** 系统产生与该名片文字对应的原始识别文本

#### Scenario: OCR failure
- **WHEN** 图像严重模糊导致无法识别出有效文字
- **THEN** 提示识别失败并提供重试或手动录入，而不是保存空名片

### Requirement: Structured field extraction
系统 SHALL 把原始识别文本结构化为名片的各个字段；姓名与公司 SHALL 区分而不是互相替代；多个电话号码 SHALL 按手机、固话、传真分别归入对应字段；无法确认归属的字段 SHALL 保持为空值，系统 SHALL NOT 依据语义补全名片上不存在的信息。

#### Scenario: Classify core fields
- **WHEN** 识别结果中包含姓名、公司、职位、手机与邮箱
- **THEN** 这些内容分别落入姓名字段、公司字段、职位字段、手机字段与邮箱字段

#### Scenario: Company is not a person name
- **WHEN** 名片仅有公司名而未给出人名
- **THEN** 系统不把公司名填入姓名字段

#### Scenario: Absent field is not invented
- **WHEN** 名片上没有网站字段
- **THEN** 结构化结果中网站字段为空值，不生成任何网址

#### Scenario: Multiple phone numbers
- **WHEN** 名片同时包含手机、固话与传真号码
- **THEN** 三个号码分别进入手机、固话与传真字段

#### Scenario: Bilingual card
- **WHEN** 名片为中英文混排
- **THEN** 姓名字段保留名片上原有的语言，不做翻译或音译

### Requirement: Human verification and save
识别与结构化结果 SHALL 先展示在可编辑的确认页面，用户 SHALL 能逐字段校正后再保存；未确认前 SHALL NOT 写入名片库；保存时姓名为空 SHALL 被拒绝。

#### Scenario: Confirm recognized card
- **WHEN** 用户确认识别结果并保存
- **THEN** 名片夹出现该名片，且后续打开详情可看到保存的全部字段

#### Scenario: Correct before saving
- **WHEN** 用户在确认页面修改识别错误的字段后保存
- **THEN** 保存的内容为修改后的内容

#### Scenario: Abandon recognition
- **WHEN** 用户在确认页面取消或返回
- **THEN** 名片库不新增任何名片

### Requirement: Permission and exception handling
相机或相册权限被拒绝时 SHALL 给出提示并引导到系统设置，且 SHALL 返回名片夹；任何异常路径 SHALL NOT 产生脏数据。

#### Scenario: Deny camera permission
- **WHEN** 用户拒绝相机权限后点击拍摄
- **THEN** 提示需要相机权限并引导到设置，不出现崩溃或空白取景页

#### Scenario: Deny photo permission
- **WHEN** 用户拒绝相册权限后点击导入
- **THEN** 提示需要相册权限并引导到设置

#### Scenario: Cancel mid flow
- **WHEN** 用户在拍摄、检测、识别或确认任一阶段取消
- **THEN** 返回名片夹，名片数量与内容保持不变

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
