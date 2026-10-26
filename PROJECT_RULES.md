# 项目规则

1. 复刻对象限定为名片全能王（CamCard）的「名片数字化与联系人管理」闭环：名片夹 → 拍摄/导入 → 检测校正 → OCR → 字段结构化 → 人工校正 → 保存 → 详情 → 搜索/管理 → 重新打开 → 导出。
2. 只做增量开发，禁止用一个 Prompt 生成整个 App。当前提交只覆盖 Week 1（规格）与 Week 2（骨架），后续周次通过新的任务项推进。
3. 先读 `docs/规格说明书.md` 与 `openspec/` 下的现行契约，再动代码。
4. 现有工程没有既存主规格；新能力 app-shell、card-library、card-holder、card-scanner 一律用 `## ADDED Requirements`，归档前主规格保持为空。
5. 模块边界稳定：Week 3 引入相机与 OCRService、Week 5 引入持久化实现时，不得修改 `BusinessCard` 与 `BusinessCardRepository` 的既有接口。
6. 分层约束：Model 是不依赖 SwiftUI 的值类型；ViewModel 用 `@MainActor` + `@Published`；View 只转发用户意图，业务规则不得写进 View。
7. 硬约束：AI 不允许补全名片上不存在的信息，无法确认的字段必须为 nil，禁止虚构网站、传真、地址等字段。
8. 确定性功能（UI、导航、状态、保存、编辑、删除、搜索、标签、导出）必须对齐 Reference Test Suite T01–T20；概率性功能（OCR、字段抽取）用固定测试集 + Ground Truth 量化评价，不得把准确率包装成「通过」。
9. 首版 `ScannerEntryView` 是扫描入口占位，用模拟识别结果验证 T02/T12；不得把它当作真实 OCR 交付。
10. 真实运行的测试和构建才能勾选任务；本机（Windows）无法编译的部分必须在 `docs/验证报告.md` 中标记「待执行」，受阻项不得预先勾选，也不得提前归档。
