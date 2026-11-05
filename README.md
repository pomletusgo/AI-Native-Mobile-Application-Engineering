实现参考：名片全能王（CamCard）「名片数字化与联系人管理」切片复刻；主规格已归档。

用 Xcode 打开 `CamCardClone.xcodeproj` 并选择同名 Scheme `CamCardClone`。

- 规格来源：`docs/规格说明书.md`（附录 C 为参考 App 观察记录）
- 变更契约：`openspec/changes/archive/2026-11-05-replicate-camcard-core-slice/`
- 测试数据：`testcards/ground_truth.json`（30 张合成名片 + Ground Truth）
- 工程规则：`PROJECT_RULES.md`、`.trae/rules/project_rules.md`
- 验收与推进：`docs/验证报告.md`（附录 A UI 验收清单 / 附录 B 规格测试追踪表 / 附录 C 能力边界分析）、`docs/工作推进记录.md`（附录 A 最终演示材料 / 附录 B Mac 端验收执行手册）
- AI 协作记录：`docs/AI协作记录.md`（附录 A TRAE 提示词模板）

当前进度：Week 1–6 的规格、骨架与功能切片均已完成（相机接入与相册导入、区域检测与透视校正、OCR、字段结构化抽取、持久化、联系人 / VCF 导出、标签管理页、UI Golden 基线、字段级准确率量化）；M01–M36 人工 UI 验收已于 2026-11-03 在 Mac mini M4 / `iPhone 17` 模拟器（iOS 27.0）上完成——**36 项全部通过**。`openspec/specs/` 已生成 app-shell / card-library / card-holder / card-scanner 四份主规格，`openspec validate --all --strict` 为 `4 passed, 0 failed`；两个变更已归档至 `openspec/changes/archive/2026-11-05-*`。归档前置项的复核结论见 `docs/工作推进记录.md 附录 B` §6.0。

## 推送后运行 CI

本机没有 macOS/Xcode 时，用 GitHub Actions 完成「规格校验 + 编译 + 单元测试 + 无头 UI 测试」。workflow 见 `.github/workflows/ios-ci.yml`，含三个作业：`OpenSpec Validate`、`Build & Test (iOS Simulator)`、`UI Tests (XCUITest, headless)`。单元测试为静态统计 363 个方法（模型 / 仓储 / 视图模型 / 扫描 / 导出 / 字段评估 / UI 快照等），CI 侧以实际 `Executed N tests` 行为准。

本仓库已创建并推送主线（首批提交为 Week 1–2 的规格与骨架）。若需在新机器上重建远端：`git init -b main` → `git add .` → `git commit -m "..."` → `git remote add origin https://github.com/<你的用户名>/<仓库名>.git` → `git push -u origin main`（在 GitHub 网页先建一个 public 空仓库，不要勾选 Add README/.gitignore）。

推送成功后：

1. 打开仓库的 **Actions** 页，会看到 `iOS CI` 自动运行，含 `OpenSpec Validate`、`Build & Test (iOS Simulator)` 与 `UI Tests (XCUITest, headless)` 三个作业。
2. 运行结束后，在该次运行页面底部 **Artifacts** 下载 `ios-build-test-logs`（`build-for-testing.log` 编译证据、`unit-tests.log` 单测证据）与 `ios-ui-test-logs`（`ui-tests.log`）。
3. 把该运行的结论回填到 `docs/验证报告.md` 的对应行（编译 / 单元测试 / UI 测试），只按实际结果写；失败时用**免登录**的 `repos/<owner>/<repo>/check-runs/<check_run_id>/annotations` 端点读回关键错误行。

其他说明：

- public 仓库的 macOS runner 不额外收费；private 仓库按分钟计费。
- macOS 运行较慢，首次构建通常需要数分钟。
- workflow 使用 `macos-15`，运行时从可用设备里挑**第一个** iPhone（不写死机型名），镜像换机型也无需改 `-destination`（运行日志的 `Pick an available iPhone simulator` 步骤会打印可用机型列表）。
- 手动重跑：Actions 页选择 `iOS CI` → **Run workflow**（已配置 `workflow_dispatch`）。

