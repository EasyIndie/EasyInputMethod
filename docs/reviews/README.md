# 验收与评审报告索引

> 报告是**证据**，不是结论摘要：每份记录当时的包身份（SHA）、场景、结果与差异。
> 规则只写新增结论 + 证据路径 + 与上一份的差异，模板见 [TEMPLATE-report.md](TEMPLATE-report.md)。
> **旧报告一律不改**（历史不重写）；新结论写进新报告，并在其中指明取代了哪一份。

## 1. 编号与状态口径

- 编号三位递增：`001`…`224`；日期在正文首行。
- 判定只用 **PASS / FAIL / BLOCKED / SKIP / PARTIAL**，不写"基本正常"。
- 报告里引用的包路径（`platforms/macos/build/acceptance-*`、`packaging/out/*`）属**本机证据目录**，不入库、会被清理；
  结论与 SHA 必须写在报告正文里，不能只依赖磁盘文件。2026-11-03 已清理到只剩 `acceptance-air-1.0.0-b34`
  （1.0.0 候选 + IT-23 试用取证），更早的候选/源码副本已删除，可按报告里的提交号重建。

## 2. 当前有效（1.0.0 相关，按主题）

| 主题 | 报告 |
|---|---|
| 更新链路与首次发布 | [213](213-updater-ships-with-package.md)、[214](214-0115-release-and-real-upgrade.md) |
| 1.0.0 锁定候选 / 门禁分工 | [217](217-1.0.0-freeze.md)（截图、IT-22 受查清单、IT-15 配方、双机基线） |
| IT-15 独立重建 | [218](218-it15-independent-rebuild.md) |
| IT-22 演练与正式 | [216](216-it22-rehearsal.md)、[T-ITER-22](../tasks/T-ITER-22.md) |
| 候选窗定位 | [219](219-caret-follows-focus.md)、[220](220-hud-stale-process.md) |
| 组合态切换不丢字 | [221](221-switch-keeps-composition.md)、[222](222-switch-paths-in-host.md) |
| 候选窗中英芯片 | [223](223-drop-language-chip.md) |
| 候选排序与个人化诊断 | [224](224-candidate-order-and-learning.md) |
| VoiceOver 复测 | [215](215-air-voiceover-recheck.md) |

## 3. 按阶段回溯（不是当前状态）

| 阶段 | 编号范围 | 主要内容 |
|---|---|---|
| 立项与架构评审 | 001–010 | 拼音 spike、性能、公开就绪、缺口评审、多角色审计 |
| 核心与引擎收口 | 011–020 | 核心完整性、组合编辑边界、多音读音、UI 工程 |
| UI 与菜单 | 021–070 | 候选窗迭代、菜单方案（v2/v3/v4）、控件间距 |
| 学习区与教学 | 071–110 | 学习区上下对应、长词、紧凑学习区、拆字说明 |
| 安装/更新/卸载 | 111–200 | 安装器、更新程序、自卸载、配置恢复 |
| 1.0.0 收尾 | 201–224 | 见上表 |

## 4. 常见查找

- **"这个行为当初为什么这样定"** → 先查 [决策记录](../决策记录.md)（ADR 是冻结决策，报告是过程证据）。
- **"某版包到底是什么"** → 查该版 `docs/releases/*.md` 与对应报告里的 ZIP/执行 SHA。
- **"现在还差什么"** → `ROADMAP.md` + [macos-release-checklist](../macos-release-checklist.md) + `HANDOFF.md`，**不要**从报告里推断当前状态。
