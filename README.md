实现参考：名片全能王（CamCard）「名片数字化与联系人管理」切片复刻；主规格处于归档前状态。

用 Xcode 打开 `CamCardClone.xcodeproj` 并选择同名 Scheme `CamCardClone`。

- 规格来源：`docs/规格说明书.md`
- 变更契约：`openspec/changes/replicate-camcard-core-slice/`
- 测试数据：`testcards/ground_truth.json`（30 张合成名片 + Ground Truth）
- 工程规则：`PROJECT_RULES.md`、`.trae/rules/project_rules.md`
- 追踪与验收：`docs/规格测试追踪表.md`、`docs/UI验收清单.md`、`docs/验证报告.md`

当前进度：Week 1–6 的规格、骨架与功能切片均已完成（相机接入与相册导入、区域检测与透视校正、OCR、字段结构化抽取、持久化、联系人 / VCF 导出、标签管理页、UI Golden 基线、字段级准确率量化）；M01–M36 人工 UI 验收已于 2026-11-03 在 Mac mini M4 / `iPhone 17` 模拟器（iOS 27.0）上完成——**33 项通过、3 项部分通过**（M04 拍摄分支、M10 电话/邮箱、M16 VoiceOver 音频均受模拟器环境限制）。`openspec/specs/` 仍为空，主规格处于**归档前**状态。剩余项仍依赖物理 iPhone 与实物名片（M04 拍摄分支、真实名片照片复核、`isReliable()` 阈值标定 T06），其阻塞清单与归因见 `docs/Mac端验收执行手册.md` §6.0。

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

