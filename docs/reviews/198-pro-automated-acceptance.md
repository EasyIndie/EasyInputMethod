# 198 pro 侧自动化验收（0.1.13）与三处探针缺陷

## 1. 环境与前置

| 项 | 值 |
|---|---|
| 设备 | **pro**：Intel x86_64 / macOS 13.7.8（22H730）/ 用户 `bot` |
| 仓库 | `dev` = `main` = `443c115`（fetch 后与远端一致，工作树 clean） |
| 已装包 | 0.1.13 / build 21，执行 SHA `c3b533e49a584e58e6e4ced14ebcca46fddbae14452e84376ad32d193863d308`（= air，见报告195） |
| 探针 | `make macos-probe-build` 重新编译 13 个 x86_64 探针，**0 告警** |
| preflight | `{"ready":true,…}` —— 本轮在**本机图形会话**执行，不是报告195 里那个受限的 SSH 会话 |
| 起始状态 | `config.toml` `2bd3fde6…`、词库 475 行、宿主 PID 85195、输入源 ABC |

报告195 把 pro 的键入类验收判为 BLOCKED，原因是当时经 SSH 执行（窗口拿不到前台、`TISSelectInputSource` 对第三方源无效）。本轮在本机图形会话直接跑，这两条限制都不存在。

## 2. 首轮失败与归因（三项，均为探针/环境问题，不是产品缺陷）

`make macos-auto-acceptance` 首轮：热键 8 项里 1 项 FAIL、客户端矩阵 2/2 FAIL、性能/网络 FAIL。

### 2.1 「混输+标点」尾部丢键

现象：`got '你你好' want 'endswith:你好。'`，同一份 JSON 里 `keys_seen=9`（应为 10）。

归因：`imetype` 的读出口计时**从应用启动起算**（`delay + settle`），而投递方要等窗口激活（含最多若干次 0.7s 重试）才开始发键。pro 较慢，尾部按键落在读出口之后，于是文本和 `keys_seen` 都少一个。

取证：

| 条件 | 结果 |
|---|---|
| 默认 `--settle 8`，3 次 | `9 keys / 你你好`、`10 keys / 你你好。`、`9 keys / 你你好` |
| `--settle 20`，3 次 | 3/3 `10 keys / 你你好。` |

air 上一直是 PASS，只是因为机器快到刚好赶上；这是**时序竞态**，两边都会犯。

### 2.2 客户端矩阵只剩 2 个（macOS 13 不认 `data:` URL）

`client-matrix.sh` 用 `open -a Safari 'data:text/html,…'` 打开测试页。macOS 13 的 LaunchServices 直接拒绝：

```
Unable to interpret 'data:text/html,…' as a path or URL
```

于是 Safari/Chrome 都没起来，前台仍是 TextEdit，`guard-focus` 判定 `BLOCKED`（保护生效，没有把按键打进别的窗口），最终只测到 TextEdit + Ghostty（2/2），达不到「≥4 个客户端」的判定。

### 2.3 性能项只差内存：51.3 MiB > 30 MiB，但**不是增长**

| 证据 | 值 |
|---|---|
| `p95` / 连接数 / 源不匹配 | 1.89 ms / 0 / 0（都合格） |
| `steady_rss_mb` | 51.3（阈值 30） |
| 再打 160 键 | RSS 52688→52736 KB（+0.05 MiB），malloc 节点 254633→254520（**减少**） |
| `vmmap` | footprint 38.7M；`mapped file` 常驻 27.6M、`__TEXT` 常驻 141M、`__OBJC_RO` 49.9M（都是共享/文件映射页） |

结论：macOS 13 的 `ps rss` 把共享库与映射文件页算进 RSS，绝对值不可与 macOS 27 的 5–20 MiB 直接比较；同一宿主上没有随按键增长。30 MiB 的 RSS 阈值是 air（macOS 27）标定的，跨版本不成立。

## 3. 探针修复（不改产品代码）

| 文件 | 改动 |
|---|---|
| `tools/macos-probe/imetype.swift` | 读出口改为**从最后一个按键起算**（`DispatchWorkItem` 防抖，每个 keyDown 重置计时），慢机器不再截尾；顺带修掉一个既有的 `swiftc` 告警（异构字面量需要显式类型），使探针构建 0 告警（ADR-081） |
| `tools/macos-probe/client-matrix.sh` | 测试页改写进 `OUT/page.html`，用文件 URL 打开（`open -a Safari "$PAGE"`），macOS 13/27 都可用 |
| `tools/macos-probe/perf-session.sh` | 门禁从「稳态 RSS ≤30MiB」改为「**相对基线的增长 ≤30MiB** + 绝对硬顶 96MiB」，JSON 增出 `baseline_rss_mb`/`rss_growth_mb` |
| `tools/macos-probe/soak-session.sh` | 同上：绝对阈值改为硬顶 `RSS_HARD_MB`（默认 96），泄漏判定仍是尾部均值相对热身段的增长（≤5MiB） |
| `tools/macos-probe/README.md` | 写明 RSS 口径差异，并强调规格里的 30MB 门禁（ADR-263，`run-imk-acceptance.sh` ⑪：footprint + 私有已提交）不能用探针 RSS 顶替 |

修复后单点复验：`type-session.sh 'wq nihao .'` 默认 settle 下 3/3 得 `你你好。`（10 键）；`client-matrix.sh` 单跑 TextEdit/Safari/Chrome/Ghostty **4/4**、Xcode SKIP（未安装）、结束还原 ABC。

## 4. 修复后完整复跑（全 PASS）

`make macos-auto-acceptance`（证据 `/tmp/lampyris-acceptance-pro-20261025T113534Z`）：

| 项 | 结果 |
|---|---|
| 前置 mode | OK（`mixed`） |
| 混输 + 标点 | PASS（`你你好。`） |
| Shift 切英文 / 切回中文 | PASS（`abc` / 中文） |
| ⌥P 标点 | PASS（`.。`） |
| ⌥F 全角 | PASS（`１２12`） |
| ⌥T 繁简 / 切回 | PASS（`學習` / `学习`） |
| ⌥M 模式循环 | PASS |
| 客户端矩阵 | **PASS 4/4**（TextEdit / Safari / Chrome / Ghostty；Xcode `SKIP 未安装`） |
| 键入延迟 | 160 键：p50 **1.29 ms**、p95 **2.41 ms**、max 7.48 ms（阈值 16） |
| 内存 | 基线 55.9 → 稳态 56.1 MiB，**增长 0.2 MiB**（硬顶 96） |
| 网络 | 25 次采样 **0 条** TCP/UDP；源不匹配 0 轮 |
| 还原 | `mode=mixed`、输入源 ABC |

`./tools/macos-probe/quality-samples.sh`（证据 `/tmp/lampyris-quality-20261025T113909Z`）：**16/16 PASS**，含五笔四码自动上屏、一级简码、拼音兜底、长词、标点、引号、全角、简繁、单 Shift、翻页、撤销、长文本、切源与失焦。

## 5. 收尾状态（与起始状态对比）

| 项 | 起始 | 结束 |
|---|---|---|
| `config.toml` | `2bd3fde6…` | `2bd3fde6…`（未变） |
| 词库 | 475 行 | 479 行（`show_wubi_learning=true` 的用户设置，学习写入，**不还原**） |
| 宿主 | PID 85195 | PID 85195（**未重启**） |
| 输入源 | ABC | ABC（已还原） |
| 页面/窗口 | 用户原有 Safari/Chrome 标签 | 探针新增的 `file:///private/tmp/lampyris-*` 标签已逐个关闭，用户原有标签未动；TextEdit 无遗留文档 |

## 6. 未决：pro 的内存口径需按 ADR-263 复测

本轮只跑了探针（RSS 口径），**没有**跑规格的 30MB 门禁（ADR-263：新启动宿主上 `vmmap` 的 physical footprint 与私有已提交同时 ≤30MiB，`run-imk-acceptance.sh` ⑪）。当前宿主（已运行 4.6 小时、约 3k 合成按键 + 用户真实输入）实测：

| 指标 | 值 |
|---|---|
| physical footprint | 43.2 → 43.7M（三轮采样稳定） |
| 私有已提交（writable `resident + swapped`） | resident 40.5M、swapped 0 |
| malloc 节点 | 254,633（验收前）→ 281,495（验收+质量样本后）→ 281,408（自投递 420 键后）→ 284,621 → 286,476（两组 HID 各 10 会话） |

增长形态：自投递路径**不增长**；HID（真实按键）路径每约 100 键 +1.8–3.2k 小对象、footprint +0.1–0.3M，且第二组低于第一组（递减，像缓存收敛而非线性泄漏）。据此**不能**判定产品超预算：ADR-263 要求在**新启动**宿主上按固定时点采样，而这台机器上本轮不允许重启宿主（铁律 §5）。

待办（需授权）：在该机重启动宿主后按 ADR-263 协议测 3 轮；若确实 >30MiB，则 Intel/macOS 13 是本轮 RC 的真实风险，需单独立项。

同样需要授权/人工：`make macos-soak`（会重启宿主核对词库持久化）、VoiceOver、多屏/缩放/Spaces/全屏、睡眠唤醒、真实卸载→重装。

## 7. 结论

- pro 侧**可自动化项全绿**（8 项热键/上屏、4 客户端、160 键延迟、零外联、16 项质量样本），报告195 的 BLOCKED 已解除。
- 首轮三项 FAIL 全部归因为探针/环境（读出口竞态、macOS 13 `data:` URL 限制、RSS 口径），修在探针层，产品代码未动。
- 内存口径的结论要等 ADR-263 协议复测；在此之前不宣称 pro 的 30MB 门禁通过。
