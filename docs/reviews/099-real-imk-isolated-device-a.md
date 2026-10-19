# 099 — 真实 IMK 验收（隔离数据根）A 机

2026-10-19，A（Intel / macOS 13.7.8），包 `07bbb2f`（执行 `681fb1c8…`）。
用 ADR-215 的私有数据根跑**已安装宿主**的真实 IMK 链路：打字/选字/取消/来源标注/状态芯片/配置热更新，
全程只用自己的 TextEdit 文档，用户真实 config/词库摘要未变。

## 结果

| 项 | 结果 | 证据 |
|---|---|---|
| 隔离数据根生效 | 宿主 `ps eww` 带 `LAMPYRIS_SUPPORT_DIR=/tmp/lampyris-imk-accept-…`；配置与词库全写入私有根 | `01-typing-guarded.txt`、`04-restore.txt` |
| A. `wq` + 空格 → 「你」 | **PASS** | `01-typing-guarded.txt` |
| B. `nihao` + 空格 → 「你好」 | **PASS**（追加到「你」后） | 同上 |
| C. Esc 取消组合 | **PASS**：文本不变、候选窗关闭（`windows: 0`） | 同上 |
| D. 候选头：输入码/页码/状态芯片 | **PASS**：`wq`、`1/12`、`混输`、`中文`、`半角`、`。` | 同上 |
| E1. 来源标注 | **PASS**：候选 `h=或 · 五笔`、`h=啊 · 拼`（五笔优先、拼音兜底各就位） | `02-source-annotation.txt` |
| E2. 配置热更新 | **PASS**：⌥T 后私有 config 写入 `chinese_variant=traditional`；外部改 `candidate.count 7→5`，页数 39 → **54**；改回 7 → **39** | `03-config-reload.txt` |
| 用户数据 | 真实 `config.toml` `3bc1117c…`、`user-dictionary.tsv` `d6054fc7…` 与装前**完全一致** | `04-restore.txt` |
| 还原 | 输入源 ABC、环境变量清空、宿主退出、执行 SHA 未变 | `04-restore.txt` |

## ⚠️ 事故与改进（同一轮内发生并已修）

首轮尝试时，我只在开头校验了一次焦点；中途 **QQ 抢到前台**，随后的 `w`/`q`/空格（选字上屏）可能落进 QQ 当时聚焦的输入框
（未发送 Return，不会外发；已请用户确认并清理）。随后立即停止发键、恢复输入源与环境变量。

改进已落地（`57eaf14`）：

- 新增 `tools/macos-probe/guard-focus.sh`：前台不是目标应用就 `exit 3`；
- 技能 `iterate-macos-ime` 写明**发键铁律**：每一批 `typekeys`/`keymod` 之前都必须过 guard，中途失焦立即终止并记 BLOCKED，
  不重试、不“抢回焦点”继续；本报告的 A–E 全部按该铁律重跑。

## 对 IT-01 的意义

- 「已安装宿主的真实 IMK 验收」现在**可以安全执行**：数据隔离（ADR-215）+ 焦点闸门 + 自建文档三件套；
- 本轮覆盖：输入/选字/取消/来源/状态/配置热更新；**仍未覆盖**：独有身份包注册与 TIS 枚举、Safari/Terminal 原生协议、
  完整剪贴板（多类型）恢复、微信隔离草稿（BLOCKED）、睡眠/唤醒与多屏矩阵。

## 收尾

`LAMPYRIS_SUPPORT_DIR` 已 `unsetenv`；宿主已退出；输入源 ABC；执行 SHA `681fb1c8…`；私有根保留在 `/tmp` 供复查（可用 `rm -rf` 清理）。
证据目录：`platforms/macos/build/acceptance-imk-a/`（本地，不入库）。
