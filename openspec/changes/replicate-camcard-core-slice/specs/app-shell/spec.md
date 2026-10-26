# App Shell Specification

## Purpose
规定名片夹复刻应用从启动到页面切换的原生应用行为，确认工程可以独立构建，并为名片夹、扫描与名片库能力提供稳定的导航契约与端到端验收依据。

## ADDED Requirements
### Requirement: Native application shell
应用 SHALL 以原生 SwiftUI App 启动并进入名片夹首页，支持 iOS 17 及以上的 iPhone，不要求登录、联网或预先授予权限。

#### Scenario: First launch
- **WHEN** 用户首次从系统启动应用
- **THEN** 直接进入名片夹首页，不出现登录页、会员页或权限申请弹窗

#### Scenario: Launch without cards
- **WHEN** 本地没有任何名片时启动
- **THEN** 名片夹首页显示空状态，而不是空白页面或错误页

### Requirement: Root navigation
应用 SHALL 使用单一导航栈管理页面切换，并 SHALL 支持进入名片详情与进入扫描流程两条路由；返回 SHALL 回到上一级且不产生脏数据。

#### Scenario: Enter card detail
- **WHEN** 用户点击名片夹中的一张名片
- **THEN** 进入该名片详情页，返回后回到名片夹并保持原有列表与筛选状态

#### Scenario: Enter scanner
- **WHEN** 用户在名片夹首页点击扫描入口
- **THEN** 进入扫描流程页面

#### Scenario: Cancel from scanner
- **WHEN** 用户在扫描流程中未保存即返回
- **THEN** 返回名片夹，名片数量与内容不变

#### Scenario: Return to root
- **WHEN** 用户从详情或扫描流程返回名片夹
- **THEN** 导航栈回到名片夹首页，不残留中间页面
