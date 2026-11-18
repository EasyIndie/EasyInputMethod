# 报告 300：达标反馈改为常驻横幅（ADR-373）

日期：2026-11-18 / pi（air）· 分支：`dev`

## 1. 真机反馈（第 8 项）

其余 7 项通过；第 8 项「正确率达标 + 进度满」时没有任何反馈。

## 2. 根因

ADR-369 的庆祝只在"**新**解锁题型"时出现：`submitCode` 前取 `unlockedKinds()`，判分后取差集，非空才写文案。
而 `unlockedKinds()` 把「自己已经尝试过（`attempts > 0`）」的题型也算解锁——用户的进度里一级简码早已练过，
所以判分前后集合相同 → 差集为空 → 永远不会显示。等于把"历史进度"当成了"没有新解锁"。

## 3. 修复

| 位置 | 改动 |
|---|---|
| `PracticeWindow.updateStats()` | 每次刷新统计时按 `Practice.isMastered`（进度满 + 正确率 ≥90%）写入常驻横幅：`🎉 已达「字根」目标：已练 30 字 · 正确率 100% · 已解锁「一级简码」`；未达标清空 |
| `finish(masteredBefore:)` | 只在"本轮刚达标"时把横幅一起 VoiceOver 播报，避免每题重复念 |
| 删除 `celebrateUnlock` | 差集判定不再参与展示 |

## 4. 验证

| 检查 | 结果 |
|---|---|
| `make verify` | PASS（542 产物零网络符号） |
| `make macos-offline-tests` | **69 文件 / 340 例 PASS** |
| `build.sh --strict` / `dev-preview.sh --smoke-test` / `make macos-ui-snapshots` | PASS |
| 断言 | 未达标无文案 / 达标文案含本级与下一阶段 / 换题后仍显示（常驻） |

## 5. 待真机复验

- 已达标的题型打开就有「🎉 已达…目标」这一行；未达标的题型不显示。
- 刚刚达标的那一题会额外播报一次。
