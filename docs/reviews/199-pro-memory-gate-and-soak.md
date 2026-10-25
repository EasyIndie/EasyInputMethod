# 199 pro 内存门禁（ADR-263）、久用与探针回归

## 1. 范围

报告198 在 pro 上跑通了自动化验收，但只用了探针的 RSS 口径；规格的 `常驻内存 ≤30MB`（ADR-263）没测。本报告补上这项、补跑久用验收，并记录过程中发现并修掉的**探针回归**（报告198 的第一版修改有三处不成立，产品代码仍然未动）。

环境：pro（Intel x86_64 / macOS 13.7.8 / 用户 `bot`），0.1.13 build 21，执行 SHA `c3b533e4…`，`config.toml` `2bd3fde6…`，词库 482 行，swap 0。宿主重启已获用户授权。

## 2. ADR-263 内存门禁：PASS（3 轮，新启动宿主）

新增 `tools/macos-probe/memory-gate.sh`：每轮重启宿主 → marker 先行（`wq `）→ 四个固定时点采样 `vmmap -summary` → 记录 loadavg 与 `vm.swapusage`。判定按 ADR-263：**physical footprint** 与**私有已提交**（`Writable regions` 的 `resident + swapped_out`）在稳态时点同时 ≤30MiB。

| 轮次 | 冷态 footprint / 私有 | 首键后 | 六词后 | 静置 8s | result |
|---|---|---|---|---|---|
| 1 | 2.9 / 1.8 | 21.5 / 20.4 | 23.1 / 21.7 | **23.0 / 21.7** | PASS |
| 2 | 2.9 / 1.7 | 21.4 / 20.3 | 22.1 / 23.2 | **22.0 / 23.1** | PASS |
| 3 | 2.9 / 1.8 | 21.5 / 20.3 | 21.6 / 22.7 | **21.4 / 22.6** | PASS |

- 稳态 footprint 21.4–23.1M、私有已提交 21.7–23.2M，**均 ≤30MiB**；peak 单独记录（22.0M 左右）。
- 冷态仅 2.9M，说明报告198 里看到的 43.2–43.7M 是**长会话累积**（当时宿主已跑 4.6 小时、约 3k 合成按键 + 用户真实输入），不是新启动宿主的口径。
- 结论：**ADR-263 在 Intel/macOS 13 上不违反**；报告198 §6 的悬案关闭。

**仍待解释的观察**（不阻塞，但记一笔）：长会话里 footprint 会从 ~21M 涨到 ~43M；本轮验收中途测得 27.9M（一轮 acceptance 后）→ 28.1–29.1M（再加 16 项质量样本后）→ 30.1M（第三轮 acceptance 后），malloc 节点 6.4k（冷态）→ 24.6 万（首次加载字典后）→ 25.8 万。增长主要发生在字典装载与窗口/应用切换，久用 5 分钟连续键入只有 +0.1–0.2MB。要判定“长会话是否会无限增长”，需要**带 footprint 采样的长时 soak**（现有 soak 只采 RSS），留作后续。

## 3. 久用与持久化：PASS

`./tools/macos-probe/soak-session.sh`（`MINUTES=5`，pro）：

| 项 | 值 |
|---|---|
| 轮次 / 采样 | 114 轮（约 1.1k 键）/ 262 次采样 |
| 网络 | 全程 **0 条** TCP/UDP |
| RSS | 38.1 → 稳态 38.8 MiB，**增长 0.1 MiB**（阈值 5） |
| 词库 | 482 → 482 → **重启后仍 482**（`learned_delta=0`，这批合成词早已学过） |
| 用户数据 | `config.toml` 仍 `2bd3fde6…`；结束输入源还原 ABC |

## 4. 探针回归（报告198 的第一版修改不成立，已修）

做§2 的过程中发现报告198 的“修复”有几处根本没生效，记下来避免后人重踩：

| # | 现象 | 真因 | 现在怎么做 |
|---|---|---|---|
| 1 | 改了读出口仍会截尾（`keys_seen=9/10`） | **`DispatchWorkItem.cancel()` 不会阻止已排队的 `asyncAfter` 块执行**，防抖从未生效；“settle 20 就正常”只是把固定期限推后了 | 改成**静默检测轮询**：0.25s 检查“距最后一键是否已静默 settle 秒”，另有 `settle+30s` 上限兜底，按键连续不断也一定会落盘 |
| 2 | 测试窗口不退出、抢前台，后续会话全 BLOCKED | `NSApp.terminate` 在 macOS 13 上卡在 `NSQuietSafeQuit`（`sample` 可见），进程不退 | 落盘后 0.8s（给在途按键留落点）直接 `exit(0)` |
| 3 | 重建 `bin/imetype` 后行为没变 | `acceptance-preflight.sh` **只在 `/tmp/lampyris-imetype.app` 目录缺失时**才重建，包内仍是旧二进制 | preflight 增加“二进制比包内新就重建”；报告198 里几次“复验通过”的其实还是旧包，本次已重跑 |
| 4 | 上屏被重复（32/40 键）或永远 BLOCKED | `type-session.sh` 原逻辑“回读没出现就重发整串按键”：既重复上屏，又让读出口被不断重置（死锁）；被打断的运行还会留下仍在投递的 `keytopid` | 只在 keytopid **退 3（前台不是测试窗口）**时重试；开头发一次 `pkill keytopid`；`trap` 保证退出时杀掉在途 keytopid；keytopid 未结束但回读已落地时立即停发 |
| 5 | 客户端矩阵的 Ghostty 窗口残留（`cat` 不退） | `ctrl+d` 对这些窗口不总能生效，残留窗口占着前台，吞掉下一次投递 | 按本次独有的 `CAT_FILE` 精确 `pkill`，最多等 5s |

修复后逐项复验：`type-session.sh 'wq nihao .'` 在 `--settle 3` 与默认 `--settle 8` 下各 3–4 次全部 `keys_seen=10`、文本 `你你好。`（此前 3 次里有 2 次是 9）；连续两轮 `make macos-auto-acceptance` 全 PASS；`quality-samples.sh` 16/16；结束后 imetype/keytopid/Ghostty 残留均为 0。

## 5. 最终状态（本轮结束时）

| 项 | 值 |
|---|---|
| 宿主 | 新 PID 22911（soak 收尾重启），冷态 footprint 2.9M |
| 验收 | 两轮 acceptance 全 PASS（客户端 4/4、p95 2.03–2.61 ms、0 外联、RSS 增长 0.0–0.2 MiB）；质量样本 16/16；ADR-263 门禁 PASS；soak PASS |
| 数据 | `config.toml` `2bd3fde6…` 未变；词库 482 行（学习写入，不还原） |
| 输入源 | ABC |
| 残留 | 无 imetype / keytopid / Ghostty 测试窗口 |

## 6. 结论与后续

- pro 侧**内存门禁（ADR-263）、久用、自动化验收、质量样本全部通过**；报告195 的 BLOCKED 与报告198 §6 的悬案都已关闭。
- 本轮所有改动都在探针/脚本层，产品代码未动；0.1.13 的执行 SHA 全程未变。
- 仍待做：**人工项**（VoiceOver、多屏/缩放/Spaces/全屏、睡眠唤醒、真实卸载→重装）；以及“长会话 footprint 增长”的定性（建议长时 soak 加 footprint 采样）。
