# 232 — 验收状态自归位：不再把用户偏好和后续用例一起带偏

- 日期：2026-11-06　｜　触发：报告 230/231 之后的一次全量验收出现**连锁失败**
- 关联：`tools/macos-probe/ime-state.sh`、`acceptance-auto.sh`、`quality-samples.sh`

## 1. 问题：一次时序抖动会把整轮验收带偏

2026-11-06 的一次 `acceptance-full` 结果（原始证据 `evidence/full2-20260702T070227Z`）：

| 现象 | 真因 |
|---|---|
| `前置 中文态 FAIL`、8 个热键项全 FAIL（`got ''`） | 上一轮矩阵结束把输入源还原成了 **ABC**，本轮开头没有归位 |
| 性能项 `invalid_rounds=2`、p95 29ms | 同上，键入没进 IME |
| `⌥T 切回简体 FAIL (got 學習)` | 一次 ⌥T 没切回来（时序），状态留在**繁体** |
| 质量样本 4 项 FAIL：`期望 中国，实得 中國`、`期望 中华人民共和国，实得 中華人民共和國` | 承接上一条：整轮跑在繁体模式下 |
| 结束后用户 config 被留在 `mode=pinyin` / `chinese_variant=traditional` | 验收没有还原用户偏好 |

也就是说：**验收依赖"操作者人工把状态摆正"，而且会改用户的真实偏好不还原**。这与"干净、可重复"直接冲突。

## 2. 修法

新增 `tools/macos-probe/ime-state.sh`：

| 命令 | 作用 |
|---|---|
| `--snapshot FILE` | 记录四项真实状态（`mode`/`punctuation`/`full_width`/`chinese_variant`） |
| `--ensure` | 归位到验收需要的 `mixed / chinese / half / simplified`，每项最多 4 次热键收敛 |
| `--restore FILE` | 按快照把四项切回去 |

- 归位用产品热键（⌥M/⌥P/⌥F/⌥T），经 `type-session.sh` 的独立测试窗口投递，**不直接改 config.toml**（配置唯一原则）。
- 任一项收敛不了就 `exit 78`（BLOCKED），不冒充 PASS/FAIL。
- `acceptance-auto.sh` 与 `quality-samples.sh` 都改成：开头 snapshot + ensure，`trap` 里 `restore → cleanup`。

## 3. 验证

| 场景 | 结果 |
|---|---|
| 故意把状态摆成 `pinyin` + `traditional` | `ime-state.sh --ensure` → `mixed/simplified`，config 四项符合预期 |
| 状态为繁体时直接跑 `quality-samples.sh` | **13/13 PASS**（以前这一轮是 4 项 FAIL） |
| 跑完后状态 | 还原成快照值，不再把用户偏好留在测试态 |
| 全量 `acceptance-full`（`SKIP_MEMORY=1`） | 热键 7/7、客户端 4/4、质量样本 13/13 PASS；**只剩性能项**（见 §4） |

## 4. 剩下的唯一红灯：性能 p95 贴线（产品信号，不是工具问题）

同一台 air（1.1.0 / build 38）连续 6 轮的实测：

| 轮次 | keys | p50 | p95 | max |
|---|---|---|---|---|
| fast3 | 64 | 3.92 | 15.27 | 17.06 |
| clean4 | 64 | 3.91 | 14.48 | 27.34 |
| full3 | 160 | 3.49 | **16.26** | 35.32 |
| soak 前的 perf-hid10 | 160 | 4.20 | 15.16 | 22.49 |
| perf-hid6 | 96 | 3.94 | 14.68 | 16.99 |
| 单轮 perf | 160 | 2.90 | 7.19（旧口径，已废） | — |

对 full3 的 160 个样本做拆分：

- **每轮第一个键**：p50 2.13ms / p95 2.68ms（不是冷启动问题）；
- **其余 150 个**：p50 3.74ms / p95 16.26ms，160 个样本里有 **8 个 ≥16.4ms**（top: 35.3 / 32.9 / 28.8 / 25.1 / 21.4 / 19.5 / 17.6 / 16.4）。

即：p95 恰好卡在 16ms 线上，是因为"5% 的样本落在 16–35ms"。下一步要决策（不建议偷偷放宽阈值）：

1. **先做归因**：这些长尾是否集中在「候选窗首次显示/候选翻页/提交上屏」这几类事件上（schema 里已有 phase 钩子，报告 138），
   或纯粹是系统噪声（本轮之前机器还在跑 `cargo build`/Swift 编译）。
2. **再定口径**：例如"安静机器上 3 轮取中位 p95"或"排除页面切换的第一键"，无论选哪种都要写 ADR 并同步发布说明。
