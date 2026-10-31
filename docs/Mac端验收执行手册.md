# Mac 端验收执行手册

> **本手册是待执行清单，不是已执行记录。** 下面所有步骤在本机（Windows）都没有运行过——本机没有 macOS 与 Xcode，编译与单元测试一直由 GitHub Actions 的 `macos-15` runner 代跑。手册中的「预期」来自 CI 已通过的结论与源码，**具体数字以 Mac 上实际输出为准**；执行结果须回填到 `docs/UI验收清单.md`、`docs/验证报告.md` 与 `openspec/changes/replicate-camcard-core-slice/tasks.md`，不得直接照抄这里的预期值。

本手册覆盖拿到 Mac 之后从环境就绪到归档（6.5）的全部步骤，以及每一步要产出的证据。

---

## 0. 前置条件

| 项 | 要求 | 说明 |
| --- | --- | --- |
| Mac 或可远程控制的 Mac | ToDesk 等远程桌面可行 | 见下方「远程连接的硬边界」 |
| Xcode | 15 及以上（含 iOS 17 SDK 或更高） | 工程 `IPHONEOS_DEPLOYMENT_TARGET = 17.0` |
| iOS 模拟器 runtime | 至少一个 iPhone 机型 | 首次使用需下载，数 GB |
| 真 iPhone（可选但部分项必需） | + Apple ID 配 Personal Team 签名 | 免费个人团队可行，证书 7 天过期需重装 |
| 网络 | 能 `git push` 到 `pomletusgo/AI-Native-Mobile-Application-Engineering` | 证据随仓库走，不靠远程桌面传文件 |

### 远程连接的硬边界

用 ToDesk 远程连 Mac 可以做：编译、跑单测、模拟器 UI 验收、录制 UI 基线。但有两处绕不过：

1. **被控端要开权限**：系统设置 → 隐私与安全性 → 给 ToDesk 打开**屏幕录制**与**辅助功能**，否则只能看不能操作。需要管理员权限，做一次即可。
2. **模拟器没有摄像头**：所以下面这些项远程连 Mac 也解决不了，必须真 iPhone——
   - M04 的「拍摄」分支（「从相册导入」那半可以模拟）
   - M34 相机权限被拒（模拟器上 `AVCaptureDevice` 的授权状态表现与真机不一定一致，需实测确认）
   - T02 / T04 / T05 的端到端

### 关键标识（后续命令会用到）

```
工程文件         CamCardClone.xcodeproj
Scheme          CamCardClone
测试 target      CamCardCloneTests
App Bundle ID   com.example.camcardclone
```

---

## 1. 阶段 0：环境就绪

```bash
xcodebuild -version                          # 确认 Xcode 版本与 SDK
xcrun simctl list runtimes                   # 看有哪些 iOS runtime
xcrun simctl list devices available | grep iPhone
open CamCardClone.xcodeproj                  # 用 Xcode 打开工程
```

**记下你选定的「机型 + iOS 版本」**——这个值要填进 M01–M36 的「设备 / 系统版本」两列，也是 UI 基线绑定的环境（换机型或换 iOS 版本需重录基线）。

在 Xcode 里选 scheme `CamCardClone` + 一个 iPhone 模拟器，`Cmd+R` 跑起来。确认空状态页正常显示。

**两条常用重置命令**（验收权限类条目时反复用，不用重装 App）：

```bash
xcrun simctl uninstall booted com.example.camcardclone          # 清空 App 数据，回到首次启动状态
xcrun simctl privacy booted reset all com.example.camcardclone  # 重置全部权限，复现「首次询问」弹窗
```

---

## 2. 阶段 1：本机编译与全量单测

`Cmd+U`。

**预期**：340 个方法全部通过。其中 `UISnapshotGoldenTests` 的 3 条会因为 `testcards/ui-baselines/` 下还没有基线而 **`XCTSkip`**——这是设计如此，不是失败。

在终端里跑一遍更容易留证据：

```bash
xcodebuild test -project CamCardClone.xcodeproj -scheme CamCardClone \
  -destination 'platform=iOS Simulator,name=<你的机型>' \
  2>&1 | tee mac-local-tests.log
```

把日志里 `Executed N tests` 那一行保存下来。这条记录比 CI 更强——它是**本机 Xcode 编译 + 本机模拟器运行**，而 CI 只能证明远程 runner 上通过。

**回填**：`docs/验证报告.md` 新增一行「Mac 本机编译与全量单测」，写明机型 / iOS 版本 / 方法数 / 结果 / 证据路径。

---

## 3. 阶段 2：录制 UI 基线并完成真实比对（任务 5.4 收口）

工具是 `CamCardCloneTests/UISnapshotGolden.swift`，覆盖 `CardRowView` / `TagChipsView` / `EmptyCardHolderView` 三个组件级视图。基线目录：`testcards/ui-baselines/`。

### 3.1 录制基线

Xcode → **Edit Scheme** → Test → Arguments → Environment Variables，加一条 `RECORD_GOLDEN = 1`，然后只跑这一组：

```bash
xcodebuild test -project CamCardClone.xcodeproj -scheme CamCardClone \
  -destination 'platform=iOS Simulator,name=<你的机型>' \
  -only-testing:CamCardCloneTests/UISnapshotGoldenTests
```

跑完 `testcards/ui-baselines/` 下会生成三个 PNG：`card-row.png` / `tag-chips.png` / `empty-card-holder.png`。

> 本轮 3 条用例会**故意报红**（录制模式下走 `XCTFail`，提示「已录制基线，重跑一次以执行比对」）。这是设计如此，不是失败。也可以直接在 Xcode 里 `Cmd+U` 后看这三个文件是否生成。

### 3.2 执行真实比对

把 `RECORD_GOLDEN` 那条环境变量**删掉**，再跑一次同样的命令。这次才是真正的逐像素比对，3 条必须 green。

**任务 5.4 只有到这一步才能勾选**：`tasks.md` 的 5.4 目前保持未勾选，理由是「骨架已就绪，截图对比本体未执行」——这一步做完即可改为勾选。

### 3.3 提交基线并观察 CI

先本地 green，再提交推送（别录完直接推）：

```bash
git add testcards/ui-baselines
git status --short          # 确认只有三个 PNG
git commit -F <临时信息文件>
git push origin main
```

**然后看 CI 结果**，有两种可能：

- **green** → `macos-15` runner 的 iOS 版本与你那台一致（或渲染差异在 1% 容差内），什么都不用改。
- **`mismatched`** → 这就是跨环境渲染差异（系统字体栅格化随 iOS 版本变化）。把失败 run 号交给 AI，把 `UISnapshotGolden` 改成「基线文件名带环境」（如 `card-row-ios17.png`），环境不匹配时自然落到 `baselineMissing` 而跳过，CI 即恢复稳定。

### 3.4 环境变量传参备选

若不想改 Scheme，也可以在命令行前置 `TEST_RUNNER_` 前缀（`xcodebuild` 会把该前缀去掉后透传给测试进程）：

```bash
TEST_RUNNER_RECORD_GOLDEN=1 xcodebuild test -project CamCardClone.xcodeproj ...
```

该前缀的透传行为随 `xcodebuild` 版本略有差异，**没生效就回到 3.1 的 Scheme 方式**，那是无歧义的。

---

## 4. 阶段 3：M01–M36 人工验收

对照 `docs/UI验收清单.md` 逐条走。每项要填 **设备 / 系统版本 / 执行日期 / 结论 / 证据路径**。

### 4.1 证据采集

截图与录屏**不用手动截**，命令行直接落文件，不依赖远程桌面画面流畅度：

```bash
mkdir -p docs/evidence
xcrun simctl io booted screenshot docs/evidence/M01-空状态.png
xcrun simctl io booted recordVideo docs/evidence/M36-四角拖拽.mp4
xcrun simctl launch booted com.example.camcardclone            # 直接拉起 App
```

命名建议 `M<编号>-<简述>.png / .mp4`，全部提交进仓库。

**规则**：静态页面截一张；有动作、有中间状态、或考验手感的，录一段。以下三条**必须录屏**，文字描述说不清：

- M22 手动调整边界（进入调整态 → 使用此区域 / 取消调整）
- M36 四角拖拽手柄（跟随、夹回边界、点击不跳位、非法框被拒）
- M21 / M03 取消与返回（确认「不产生新名片、不残留产物」）

### 4.2 建议执行顺序

按权限状态分三轮走，每轮开始前用重置命令回到干净状态，能少跑很多遍：

| 轮次 | 起始状态 | 覆盖条目 |
| --- | --- | --- |
| 第一轮 | `uninstall` 后全新安装 | M01–M03、M05–M14、M17 |
| 第二轮 | 相机 / 相册 / 联系人权限**全部允许** | M04、M18–M22、M26–M33、M36 |
| 第三轮 | 相关权限**全部拒绝**（`privacy reset all` 后拒绝） | M32、M34、M35 |

M15（小屏 + 较大机型各一次）与 M16（VoiceOver）需要额外准备，建议单独安排。

M17（保存后完全退出并重启）用 `xcrun simctl terminate` + `launch`，或直接杀掉模拟器里的 App 再重开，确认数据仍在。

### 4.3 必须真机的条目

- **M04 的「拍摄」分支**、**M34 相机权限被拒**、**T02 / T04 / T05 的端到端**——模拟器没有摄像头。
- 真机需 Apple ID 配 Personal Team：Xcode → Signing & Capabilities → Team 选个人团队，Bundle ID 可改为 `com.example.camcardclone.dev` 避免冲突。证书 7 天过期，过期后需重新连接设备构建。

---

## 5. 阶段 4：真实数据量化（4.4 与 T06）

这两项是全表唯一还是空白的数字，也是唯一需要「造数据」的阶段。

### 5.1 4.4 字段级准确率

需要三样东西：

**① 30 张名片图片**

`testcards/ground_truth.json` 里有 30 张卡的字段真值，ID 为 `TC01` … `TC30`。该文件 meta 已注明「全部为虚构 / 合成数据，不含真实个人敏感信息」，因此照真值渲染出 30 张合成名片图片即可，**这一步在 Windows 上就能做完，不必等 Mac**。

**② 30 个 OCR 原文**

约定位置在源码里已定死（`FieldExtractionEvaluator.ocrTextURL(cardID:repositoryRoot:)`）：

```
testcards/ocr/TC01.txt … TC30.txt
```

目前 `testcards/ocr/` 目录还不存在。生成方式是**新增一小块代码**：一个测试用例，用 `OCRService` 对每张图片跑识别并把文本写成 txt。这块代码尚未编写，需要在动工前单独确认。

> **必须写进报告的局限**：由「渲染图片 → 跑 OCR」得到的准确率，会比真实拍摄的照片**偏乐观**——渲染文字比拍照干净，没有反光、没有透视畸变、没有污损。结论须注明这一限制，不能当成真实场景的准确率。

**③ 跑评价**

只要 `testcards/ocr/` 下 30 个 txt 齐了，现有用例 `FieldExtractionEvaluatorTests.testFieldAccuracyOnCorpusIsPendingUntilOCRTextsExist` 会**自动从 skip 转为真跑**：

- 它会 `print` 出字段级准确率报告（含「| 姓名 | 1 | 1 | 100.0% |」这类逐字段行与错误明细）
- 它断言 `results.count == cards.count`，缺文件会当场失败

**这一步不需要新代码**，`Cmd+U` 就有结果。把报告贴进 `docs/`。

### 5.2 T06 `isReliable()` 阈值标定

当前阈值（面积 0.12 / 0.98、长宽比 1.15…3.6）是常见名片比例下的**初值**，从未在真实照片上复核。

用真实拍摄的照片跑检测，逐张比较 `CardQuad.isReliable()` 的判定与你肉眼判断是否一致：

- 判定「可靠」但明显不是名片 → 阈值过松
- 判定「不可靠」但其实是合格名片 → 阈值过严

调完后同步更新两处措辞（这两处现在都写着「初值 / 未标定」）：

- `docs/验证报告.md`
- `docs/能力边界分析.md`

---

## 6. 阶段 5：归档（6.5）

只有前面全部绿了才做。

```bash
npm run spec:validate      # 预期 1 passed, 0 failed
git status --short         # 工作区必须干净
openspec archive replicate-camcard-core-slice
```

归档前先把 `openspec/changes/replicate-camcard-core-slice/tasks.md` 的 6.1 / 6.4 按实际结果勾上。归档后四个 ADDED 能力（app-shell / card-library / card-holder / card-scanner）合并为主规格。

---

## 7. 产物清单

| # | 产物 | 位置 | 阶段 |
| --- | --- | --- | --- |
| 1 | Mac 本机编译 + 全量单测通过记录 | `docs/验证报告.md` 新增行 | 1 |
| 2 | UI 基线 3 个 PNG | `testcards/ui-baselines/` | 2 |
| 3 | 真实比对通过的 CI run 号 | `docs/验证报告.md`、`tasks.md` 5.4 | 2 |
| 4 | M01–M36 回填（36 行全部有实际记录） | `docs/UI验收清单.md` | 3 |
| 5 | 截图与录屏 | `docs/evidence/` | 3 |
| 6 | 30 张名片图片 | `testcards/images/`（需新建） | 4 |
| 7 | 30 个 OCR 原文 | `testcards/ocr/TC01–TC30.txt`（需新建） | 4 |
| 8 | 字段级准确率报告（含精度局限说明） | 贴进 `docs/` | 4 |
| 9 | `isReliable()` 标定结论 | `docs/验证报告.md`、`docs/能力边界分析.md` | 4 |
| 10 | 归档后的主规格 | `openspec/specs/` | 5 |
| 11 | 归档后新增的协作轮次 | `docs/AI协作记录.md` | 5 |

---

## 8. 注意事项

1. **先本地验证再推送**：阶段 2 的基线录完先在自己机器上跑通比对，再 push。否则一旦 CI 报红，分不清是跨环境渲染差异还是真实改动。
2. **证据随 git 走**：那台 Mac 能上网就 `git push`，仓库里留下痕迹比远程桌面传文件、存本地文件夹都可靠。
3. **不把预期当结论**：本手册里的方法数、CI run 号都是本机 CI 的历史结论；Mac 上的实际输出若与预期不同，以实际为准并如实记录差异。
4. **勾选状态只按实际证据更新**：截图、录屏、日志齐了才勾，缺证据的项保持未勾选。
5. **保持 CI 常绿**：每次推送后确认 `iOS CI` 的 `OpenSpec Validate` 与 `Build & Test (iOS Simulator)` 两个作业均 success；失败时用 `repos/pomletusgo/AI-Native-Mobile-Application-Engineering/check-runs/<job_id>/annotations` 免登录取失败原因。
