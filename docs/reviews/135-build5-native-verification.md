# 135 build5 原生复验（ADR-255 内存修复）

## 当前结论

B（arm64/macOS 27.0.1）从含 ADR-255 的 main `299d8f815605d7ff5ecd82c3217a1e5203035a19`
构建固定开发包 0.1.0/**build5**（隔离公证 run 39775362738），静态核验后安装，用户只切一次开发源：

- ZIP `b6f9536ace0f7c7ba1b61b217136789d2ea813c54f4be904dc745a54376dc763`，
  执行 SHA `aef8b7cc4e81f6ed3aa141ce03463b39eacc0696e5791a735412cbd4b649a68a`，
  身份/根/arm64/Team 2N62934Y28 与 build4 一致，`spctl` accepted、`stapler validate` 通过。
- 旧 build4 自动备份到固定根 `replacement-r__fdgwk/previous.app`；换包前后输入源集合一致，运行中孤儿宿主按精确路径退出。
- **加载器行为无回归**：六词、混输数字/方向/退格/Esc/Enter、五笔空格/数字、拼音三词（含 xi'an）、最终 mixed
  全部实际读回 PASS；config 语义恢复且字节 SHA `3bc1117c…` 未变。
- 性能与 build4 同量级：首轮 50 键 total p95 **11.569ms**/max 42.663ms（唯一 ≥16ms 为冷首键），
  暖态 p95 10.726ms/max 12.587ms；附加 45 键 p95 10.303ms/max 10.411ms（0 次 ≥16ms）；engine p95 1.122ms。
- **宿主内存首次落到 30MB 线下**：physical **29.5MiB** / peak **29.9MiB**（build4：37.8/40.3），
  malloc 活跃 17.2M、碎片 **5.7M（25%）**（build4：17.4M/12.0M/41%），换出 14.6M（build4：18.7M）。
  但当前系统 swap 已用 3.9GB、本进程换出 14.6M，因此记为**候选证据**，不宣布 30MB 门禁干净关闭。

## 采样细节

内嵌计时 schema2，95 行全部来自自建 TextEdit 文稿，逐键源/窗口/路径/焦点守卫，无失焦重试：

| 项 | build5 | build4 |
|---|---|---|
| 首轮 total p95 / max | 11.569 / 42.663 ms | 10.770 / 37.299 ms |
| 暖态 p95 / max | 10.726 / 12.587 ms | 10.620 / 11.685 ms |
| 附加 p95 / max | 10.303 / 10.411 ms | 11.154 / 16.900 ms |
| engine p95 | 1.122 ms | 1.114 ms |
| commit p50 / p95 | 3.251 / 6.428 ms | 2.723 / 7.016 ms |
| hide p50 / p95 / max | 0.784 / 3.370 / 3.370 ms | 0.849 / 1.222 / 1.222 ms |
| 冷首键 total | 42.663 ms | 37.299 ms |

冷首键分段（build5）：content 15.517、window 9.556、preedit 7.825、status 5.149、caret 3.709、engine 0.786ms。
两次冷首键差异主要来自首次窗口尺寸/内容排版；暖态稳定无 ≥16ms，本轮不新增预热或缓存改动。

## 内存前后对照（同一台机、同一进程角色）

| 指标 | build4（ADR-255 前） | build5（ADR-255 后） |
|---|---|---|
| physical / peak | 37.8 / 40.3 MiB | **29.5 / 29.9 MiB** |
| malloc 活跃 | 17.4M | 17.2M |
| malloc 碎片 | 12.0M（41%） | **5.7M（25%）** |
| 换出 | 18.7M | 14.6M |
| 冷启动宿主 | 8.9 MiB | 未重测（同代码路径，未改启动） |

离线 `mem_probe` 四表全加载峰值 24.4–25.4MiB → 15.8MiB 的结论（报告 134）在原生宿主上成立；
剩余 5.7M 碎片与 14.6M 换出属于下一轮可继续压缩的空间，但不再是「数据量 2.5MB 却有 12M 碎片」的结构性浪费。

## 收尾

- marker 在切回 ABC 前删除；宿主 `82125` 在 ABC 后按精确路径 SIGTERM 退出，最终 ABC、开发宿主 0 个。
- 生产包 `17053e1`/执行 `535d546f…`、生产 config `3bc1117c…`、生产词库 `74f76e92…`（29 行）未变；
  开发 config 字节未变；开发私有词库按正常学习变化（14 行，`0ccce15f…`）。
- 未清库、未 purge、未改 `UserDefaults`/HIToolbox、未自动切源，未触碰手工文稿「萤火虫性能验收-115.txt」。

## 边界

- 16ms 与 30MB 仍按「候选证据」记录：单轮样本、系统 swap 高压力；同最终 RC 的三模式/重启/客户端矩阵与低压力内存复测未完成。
- 升级闭环、App Store 可行性、A/B、安装升级恢复卸载、VoiceOver/多屏/真实睡眠、独立重建与五工作日仍未完成；无 tag、无正式 Release。

## 证据

- `135-evidence/00-pre.txt`、`01-install.log`、`01b-installation.json`、`05-final-state.txt`：换包/收尾 SHA。
- `135-evidence/native-trace.jsonl`（95 行 schema2）、`03-trace-summary.txt`、`04-round-state.json`。
- `135-evidence/02-memory.txt`：3 次 vmmap 采样与 swapusage。
