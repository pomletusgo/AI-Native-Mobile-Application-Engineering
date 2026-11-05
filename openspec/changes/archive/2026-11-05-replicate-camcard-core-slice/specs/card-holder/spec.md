# Card Holder Specification

## Purpose
规定名片夹首页与名片详情、编辑页面的可观察行为，覆盖列表、空状态、搜索、标签筛选、删除与字段外呼，作为确定性功能 100% 验收的直接依据。

## ADDED Requirements
### Requirement: Card holder states
名片夹首页 SHALL 根据本地数据与用户输入呈现空、有名片、搜索中、标签筛选四种可区分状态，任一状态 SHALL NOT 显示空白页。

#### Scenario: Empty holder
- **WHEN** 名片库中没有任何名片
- **THEN** 显示空状态插图与引导文案，并提供扫描第一张名片的入口

#### Scenario: Non-empty holder
- **WHEN** 名片库中至少有一张名片
- **THEN** 显示名片列表，每行展示姓名与公司/职位等缩略信息

#### Scenario: Leave empty state
- **WHEN** 在空状态下保存第一张名片
- **THEN** 首页从空状态切换为有名片状态并显示该名片

### Requirement: Search in holder
名片夹 SHALL 提供搜索输入，输入后 SHALL 按关键字过滤列表；无匹配结果时 SHALL 显示无结果提示而不是空状态插图；清空关键字 SHALL 恢复完整列表。

#### Scenario: Filter by keyword
- **WHEN** 在搜索框输入与某张名片姓名或公司匹配的关键字
- **THEN** 列表仅显示匹配的名片

#### Scenario: No results
- **WHEN** 输入无法匹配任何名片的关键字
- **THEN** 显示无结果提示

#### Scenario: Clear search
- **WHEN** 清空搜索框
- **THEN** 恢复显示全部名片

### Requirement: Tag filtering
名片夹 SHALL 支持按标签筛选名片，并 SHALL 提供可用的标签集合；重复选中同一标签 SHALL 取消筛选。

#### Scenario: Filter by tag
- **WHEN** 用户选中某个已有标签
- **THEN** 列表仅显示带有该标签的名片

#### Scenario: Toggle tag off
- **WHEN** 用户再次点击当前已选中的标签
- **THEN** 取消筛选并恢复完整列表

#### Scenario: Search combined with tag
- **WHEN** 同时存在搜索关键字与已选标签
- **THEN** 列表同时满足关键字与标签两个条件

### Requirement: Card detail
名片详情页 SHALL 展示该名片已保存的全部字段；无值字段 SHALL NOT 显示为空行或占位文本；电话、邮箱与网站 SHALL 可点击并交给系统组件处理。

#### Scenario: Show saved fields
- **WHEN** 打开一张已保存的名片
- **THEN** 显示其姓名、公司、职位、电话、邮箱等已保存字段

#### Scenario: Hide absent fields
- **WHEN** 名片没有传真与网站
- **THEN** 详情页不显示传真与网站条目

#### Scenario: Tap phone or email
- **WHEN** 用户点击电话或邮箱条目
- **THEN** 系统以拨号或邮件方式处理该字段

### Requirement: Card editing
详情页 SHALL 支持进入编辑态修改字段并保存；保存成功 SHALL 立即反映到详情与列表；取消 SHALL 丢弃未保存的修改；姓名被清空时 SHALL 拒绝保存。

#### Scenario: Edit and save
- **WHEN** 修改名片姓名或公司后保存
- **THEN** 详情页与名片夹列表显示修改后的内容

#### Scenario: Cancel editing
- **WHEN** 进入编辑态修改字段后取消
- **THEN** 详情页恢复为修改前的内容

#### Scenario: Reject empty name
- **WHEN** 编辑时把姓名清空或改为空白后保存
- **THEN** 系统拒绝保存并停留在编辑态

### Requirement: Card deletion
名片夹 SHALL 支持删除名片；删除后 SHALL 立即从列表消失；删除最后一张名片后 SHALL 回到空状态。

#### Scenario: Delete one card
- **WHEN** 删除列表中的某张名片
- **THEN** 该名片从列表消失，其余名片保持不变

#### Scenario: Delete last card
- **WHEN** 删除名片库中唯一的名片
- **THEN** 首页切换回空状态
