# 字段级准确率报告（改规则后）

来源：GitHub Actions `iOS CI` → 作业 `Build & Test (iOS Simulator)`，check-run `125116046722`，
提交 `d74450e`（2026-11-02）。本机（Windows）经免登录的
`check-runs/<id>/annotations` 端点读回，报告行以 `FIELDRPT` 前缀分块发出。

「改规则前」的同一报告见 `docs/evidence/mac-2026-11-01/mac-field-accuracy.log`
（提交 `04f8082` 之前的 2026-11-01 租机运行）。

## 字段级准确率

- 参与评价：30 张名片 / 270 个字段
- 字段级准确率：57.8%（正确 156 / 总计 270）
- 缺失字段误报率：1.9%（虚构 2 / 本应为空 105）

| 字段 | 正确 | 参与 | 准确率 |
|---|---|---|---|
| 姓名 | 29 | 30 | 96.7% |
| 公司 | 25 | 30 | 83.3% |
| 职位 | 28 | 30 | 93.3% |
| 手机 | 23 | 30 | 76.7% |
| 固话 | 12 | 30 | 40.0% |
| 传真 | 4 | 30 | 13.3% |
| 邮箱 | 19 | 30 | 63.3% |
| 网站 | 5 | 30 | 16.7% |
| 地址 | 11 | 30 | 36.7% |

### 错误明细

| 名片 | 字段 | 判定 | ground truth | 抽取结果 |
|---|---|---|---|---|
| TC07 | 手机 | invented | — | +1-555-0307 |
| TC07 | 固话 | missed | +1-555-0307 | — |
| TC12 | 邮箱 | mismatch | david@abc.example.edu | david@abc.example.eau |
| TC13 | 姓名 | mismatch | Emily Zhang | Global Vision Lta. |
| TC13 | 公司 | missed | Global Vision Ltd. | — |
| TC15 | 公司 | missed | 康泰医疗器械 | — |
| TC20 | 邮箱 | missed | hejing@example.com | — |
| TC21 | 手机 | invented | — | +1-555-0821 |
| TC21 | 固话 | missed | +1-555-0821 | — |
| TC26 | 邮箱 | missed | anna.white@example.com | — |
| TC28 | 公司 | missed | Apple | — |

合计 11 条错误（`invented` 2 / `missed` 7 / `mismatch` 2）。
