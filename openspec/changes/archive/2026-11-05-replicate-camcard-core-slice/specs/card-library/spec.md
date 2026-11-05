# Card Library Specification

## Purpose
定义名片数据模型、名片库读写契约、本地持久化与联系人导出的可观察行为，作为后续引入相机、OCR 与磁盘存储时的稳定接口，确保各周次增量不破坏既有数据契约。

## ADDED Requirements
### Requirement: Business card schema
系统 SHALL 以统一的名片结构存储联系人信息，其中姓名是唯一必填字段；公司、职位、手机、固话、传真、邮箱、网站、地址、邮编、部门、备注在名片上不存在时 SHALL 保持为空值，系统 SHALL NOT 依据语义推测或补全这些字段。

#### Scenario: Save a complete card
- **WHEN** 保存一张包含姓名、公司、职位、手机与邮箱的名片
- **THEN** 重新打开时五个字段值与保存时一致

#### Scenario: Absent field stays empty
- **WHEN** 名片上没有网站字段
- **THEN** 该名片的网站字段为空值，而不是空字符串或推测出的网址

#### Scenario: Name is required
- **WHEN** 姓名缺失或仅含空白字符时尝试保存
- **THEN** 系统拒绝保存并保持当前编辑状态

#### Scenario: Multiple phone numbers
- **WHEN** 名片上同时存在手机、固话与传真
- **THEN** 三个号码分别存入对应字段，不互相覆盖也不合并为一个字段

### Requirement: Card repository contract
系统 SHALL 通过统一的名片库接口提供读取全部、按标识读取、新增、更新、删除、关键字搜索与按标签筛选能力；接口 SHALL 与存储实现解耦。

#### Scenario: Add and fetch
- **WHEN** 向名片库新增一张名片后读取全部
- **THEN** 结果包含该名片且数量增加 1

#### Scenario: Update existing card
- **WHEN** 修改已存在名片的公司字段并保存
- **THEN** 按标识读取时返回修改后的公司，名片总数不变

#### Scenario: Delete card
- **WHEN** 删除一张已存在的名片
- **THEN** 按标识读取返回空，读取全部不再包含该名片

#### Scenario: Newest first
- **WHEN** 依次新增多张名片并读取全部
- **THEN** 结果按创建时间从新到旧排列

#### Scenario: Empty repository
- **WHEN** 名片库中没有任何名片时读取全部
- **THEN** 返回空列表而不是错误

### Requirement: Search and tag query
名片库 SHALL 提供大小写不敏感的搜索，匹配范围覆盖姓名、公司、职位、电话与邮箱；关键字为空白时 SHALL 返回全部名片；按标签筛选 SHALL 大小写不敏感。

#### Scenario: Search by name
- **WHEN** 以姓名片段搜索
- **THEN** 仅返回姓名匹配的名片

#### Scenario: Search by company or phone
- **WHEN** 以公司名或电话号码片段搜索
- **THEN** 返回对应名片

#### Scenario: Case insensitive search
- **WHEN** 以不同大小写输入同一关键字
- **THEN** 返回结果一致

#### Scenario: Blank keyword
- **WHEN** 搜索关键字为空或仅含空白字符
- **THEN** 返回全部名片

#### Scenario: Tag query
- **WHEN** 按某个标签筛选
- **THEN** 仅返回包含该标签的名片，且标签匹配不区分大小写

### Requirement: Card persistence
系统 SHALL 在应用重新启动后恢复已保存的名片及其字段、标签与备注；持久化实现 SHALL 通过名片库接口提供，SHALL NOT 要求上层页面改动。

#### Scenario: Relaunch keeps data
- **WHEN** 保存名片后完全退出并重新启动应用
- **THEN** 名片夹仍显示该名片，字段、标签与备注与保存时一致

#### Scenario: Relaunch keeps edits
- **WHEN** 编辑名片后退出并重新启动
- **THEN** 详情显示编辑后的内容

### Requirement: Contact export
系统 SHALL 支持把名片导出为系统联系人条目或 VCF 文件，字段映射 SHALL 保持一一对应。

#### Scenario: Export phone and email
- **WHEN** 导出一张含手机与邮箱的名片
- **THEN** 生成的联系人条目中手机与邮箱与名片一致

#### Scenario: Export absent fields
- **WHEN** 导出一张缺少传真字段的名片
- **THEN** 生成的联系人条目不含传真内容，不写入占位值
