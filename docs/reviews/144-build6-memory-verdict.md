# 144 build6 稳态内存三轮回测（ADR-263）

## 条件

- 已装 build6（执行 `21f5b05b…`，main `299d8f8`），本轮未换包。
- 环境：loadavg 2.2–6.2，`vm.swapusage` 5.1–5.3G/6.1G，无 xcodebuild。
- 三轮均为**新启动宿主** + marker 先行 + 六词 + 静置 8s；切回 ABC 用 `selsrc` 自动完成，宿主按精确路径退出。

## 结果

| 轮次 | 稳态 physical | 高水位 peak | 私有已提交（resident+swapped） | trace p95 / max |
|---|---|---|---|---|
| 144 | 28.8M | 29.6M | 9.8 + 15.5 = **25.3M** | 11.33 / 83.23ms |
| 144b | 28.3M | 31.8M | 11.4 + 13.2 = **24.6M** | 10.81 / 33.66ms |
| 144c | 28.0M | 31.9M | 15.2 + 9.8 = **25.0M** | 12.00 / 43.65ms |

- 三轮稳态 physical 28.0–28.8M、私有已提交 24.6–25.3M，**均 ≤30MiB**。
- 高水位 29.6–31.9M 单独列出，按 ADR-263 不用于关闭门禁（首次装表/首次布局的一次性峰值）。
- 时延：p95 10.81–12.00ms（<16ms），每轮仅冷首键 1 次 ≥16ms（33–83ms，随 loadavg 波动）。
- 六词（含 xi'an）与 steady 键全部实际读回通过；config 语义与字节 SHA `3bc1117c…` 未变。

## 判定

**build6 候选满足 30MB 口径**（稳态 physical 与私有已提交同时 ≤30MiB，3/3 轮）。
但按门禁纪律：**最终 RC 必须用同一协议复测**后才正式关闭；本报告只关闭 build6 这一候选的证据缺口，不替代同 RC 验收。

## 收尾

- marker 删除、源已自动还原 ABC、宿主 `29312` 精确退出；生产包/生产数据/开发 config 未变，开发词库仅正常学习变化（`b0469498…`）。
- 无效轮（loadavg 54）与前置条件见报告 143；自动化边界：只能自动切回 ABC，进入开发源仍需用户手动。

## 证据

`platforms/macos/build/acceptance-144{,b,c}/`：`10-memory-cold-vm.txt`、`11-memory-early.txt`、`13-memory-settled.txt`、`14-memory-late.txt`、
`perf-144*/trace.jsonl`、`98-cleanup.txt`、`sample-144*.sh`。
