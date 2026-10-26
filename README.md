实现参考：名片全能王（CamCard）「名片数字化与联系人管理」切片复刻；主规格处于归档前状态。

用 Xcode 打开 `CamCardClone.xcodeproj` 并选择同名 Scheme `CamCardClone`。

- 规格来源：`docs/规格说明书.md`
- 变更契约：`openspec/changes/replicate-camcard-core-slice/`
- 测试数据：`testcards/ground_truth.json`（30 张合成名片 + Ground Truth）
- 工程规则：`PROJECT_RULES.md`、`.trae/rules/project_rules.md`
- 追踪与验收：`docs/规格测试追踪表.md`、`docs/UI验收清单.md`、`docs/验证报告.md`

当前进度：Week 1 规格与 Week 2 骨架已完成；相机、OCR、字段抽取、持久化与导出留待 Week 3–6。

## 推送后运行 CI

本机没有 macOS/Xcode 时，用 GitHub Actions 完成「编译 + 跑 42 个单元测试」。workflow 见 `.github/workflows/ios-ci.yml`。

首次推送（在本目录 `CamCardClone/` 下执行）：

```powershell
git init -b main
git add .
git commit -m "feat: CamCardClone Week1-2 (spec + SwiftUI skeleton)"
# 先在 GitHub 网页新建一个 public 空仓库（不要勾选 Add README/.gitignore），然后：
git remote add origin https://github.com/<你的用户名>/<仓库名>.git
git push -u origin main
```

推送成功后：

1. 打开仓库的 **Actions** 页，会看到 `iOS CI` 自动运行，含 `OpenSpec Validate` 与 `Build & Test (iOS Simulator)` 两个作业。
2. 运行结束后，在该次运行页面底部 **Artifacts** 下载 `ios-build-test-logs`：`build-for-testing.log` 是编译证据，`unit-tests.log` 是测试证据。
3. 把该运行页链接回填到 `docs/验证报告.md`，并把其中「iOS 编译」「42 个单元测试实际运行」两行改为「通过」。

其他说明：

- public 仓库的 macOS runner 不额外收费；private 仓库按分钟计费。
- macOS 运行较慢，首次构建通常需要数分钟。
- workflow 默认使用 `macos-15` + `iPhone 16` 模拟器。若 GitHub 更换镜像导致找不到该机型，改 `-destination` 里的机型名即可（运行日志的 `List available iPhone simulators` 步骤会列出所有可用机型）。
- 手动重跑：Actions 页选择 `iOS CI` → **Run workflow**（已配置 `workflow_dispatch`）。

