# Replicate CamCard Core Slice

## Why
当前项目只有一份 Week 1 的规格说明书和一套尚未被工程与规格约束的 SwiftUI 源文件。参考 App 名片全能王（CamCard）的「名片数字化与联系人管理」是一个端到端闭环：名片夹 → 拍摄/导入 → 区域检测与校正 → OCR → 字段结构化 → 人工校正 → 保存 → 详情 → 搜索/管理 → 重新打开 → 导出。课程要求在锁定版本与固定测试集内 100% 黑盒复刻该闭环的**可观察行为**，不接受「拍照 → OCR → 显示一段文字」的演示级实现，也不接受用一个 Prompt 生成整个 App。

因此需要把规格说明书落成可验收的 OpenSpec 契约，并给出一个真正可运行、可回归的工程增量。

## What Changes
- 建立 `app-shell`、`card-library`、`card-holder`、`card-scanner` 四个新能力的规格契约（本变更全部为 ADDED）。
- 提供可直接用 Xcode 打开的 `CamCardClone.xcodeproj`（含共享 Scheme）与 MVVM 源文件。
- 交付 Week 1（Specification：页面/状态清单、BusinessCard Schema、测试数据集与 Reference Test Suite）与 Week 2（架构 + 数据模型 + 名片夹 + 详情 + 扫描入口占位 + 首批单元测试）。
- 建立 `testcards/ground_truth.json`（30 张合成名片 + Ground Truth），作为概率性功能的量化评价基础。
- 建立 TRAE 与 OpenSpec 工程规范：`.trae/rules/project_rules.md`、`PROJECT_RULES.md`、`package.json`（锁定 openspec 1.13.2）、`docs/规格测试追踪表.md`、`docs/UI验收清单.md`、`docs/验证报告.md`。

## Capabilities
### New Capabilities
- `app-shell`: 原生启动、导航栈与根视图行为。
- `card-library`: BusinessCard 数据模型、仓储契约（CRUD / 搜索 / 标签）、本地持久化与联系人导出。
- `card-holder`: 名片夹首页与名片详情/编辑的可观察行为（列表、空状态、搜索、标签筛选、删除、字段外呼）。
- `card-scanner`: 拍摄/导入、名片区域检测与校正、OCR、字段结构化与人工校正保存。

### Modified Capabilities
- 无。本工程为全新工程，没有既存主规格需要 MODIFIED。

## Impact
- 新增 `openspec/`、`docs/`、`.trae/`、`CamCardClone.xcodeproj/`、`testcards/`。
- App 目标只做增量开发：Week 3 引入相机与 `OCRService`、Week 5 引入持久化实现时，**不得修改** `BusinessCard` 与 `BusinessCardRepository` 的既有接口。
- 每次修改必须保证既有单元测试继续通过（Regression Protection）。

## Out of Scope
用户注册、会员、订阅支付、广告、云同步与多设备同步、团队名片库、Salesforce/CRM 同步、企业权限与组织、数字名片设计与模板、QR 名片交换、Email Signature、Virtual Background、AI 企业情报/公司分析/财务分析/商务建议、会议录音与总结、销售漏斗。

## Delivery Split
本变更跨越六个周次，`tasks.md` 用勾选状态区分：Week 1–2 的交付物在本次提交中完成；Week 3–6 的相机、OCR、字段抽取、持久化、导出、全量回归与归档留待后续提交，未完成项不得预先勾选。
