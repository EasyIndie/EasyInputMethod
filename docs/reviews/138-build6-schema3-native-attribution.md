# 138 build6 schema3 原生归因（冷首键与内存固定时点）

## 结论

B（arm64/macOS 27.0.1）从含 ADR-258 的 main `2b34d0f31552f192e08dda304aff1b131fdad30d`
构建固定开发包 0.1.0/**build6**（隔离公证 run 39787338801，执行 `21f5b05b…`，ZIP `6b964216…`），
静态核验、ABC 换包（旧 build5 备份 `replacement-aygw7un1`）后，用户只切一次开发源完成采样与收尾。

**冷首键终于可分段归因**（唯一 ≥16ms 的样本，total 42.657ms）：

| 阶段 | 冷首键 | 稳态 p50 |
|---|---|---|
| contentLayout | **9.043ms** | 1.91ms |
| contentMeasure | **6.302ms** | 0.75ms |
| contentSet | 0.124ms | 0.01ms |
| contentState | 0.050ms | 0.14ms |
| content 合计 | **18.347ms** | 2.87ms |
| status | 8.189ms | — |
| preedit | 9.388ms | — |
| window | 4.077ms | — |
| caret | 1.806ms | — |
| engine | 0.738ms | — |

- `contentLayout` 的首次 9ms 对应一次真实窗口尺寸同步（ADR-253 已证明同尺寸才跳过；首键尺寸必然不同）；
  `contentMeasure` 的 6.3ms 是首次文本测量（CoreText/字体/属性解析）。两者都是**每进程一次**的成本，不是每键成本。
- 稳态 content 2.87ms（layout 1.91 + measure 0.75），与报告 136 的离屏结论一致：本项目渲染路径本身没有整体性浪费。
- 结论：冷首键 = 首次布局同步 + 首次文字测量 + 首次状态/预编辑叠加的一次性成本；**不做预热掩盖**（ADR-253 已否决），
  按「已知一次性成本」记录，16ms 门禁仍以 p95 判定（本轮 p95 10.56ms、暖态 9.97ms）。

## 性能与功能

- 首轮 total p95 **10.56ms** / max 42.66ms；暖态 p95 9.97ms / max 12.21ms，除冷首键外无 ≥16ms。
- engine 0.738ms；`candidateData` 0.006ms。
- 47 条 trace 全部 schema3；六词（含 xi'an）与 steady 键实际读回通过；config 语义与字节 SHA `3bc1117c…` 未变。

## 内存（固定时点，同进程）

| 时点 | physical | peak | 换出 |
|---|---|---|---|
| 冷态（首键前） | 30.0M | 30.0M | 17.8M |
| 首键后 | 32.6M | 32.8M | 16.6M |
| 六词后 | 33.7M | 34.5M | 14.9M |
| 静置 8s | 33.6M | 34.5M | 15.4M |

系统 `vm.swapusage` 4071M/5120M、load 2.4–5.5。与 build5（29.5–34.8M）一致：
**30MB 门禁在压力环境下仍不能关闭**，需要低压力环境同协议复测；本期不把「首键前 30.0M」当作验收值。

## 收尾

- marker 在切回 ABC 前删除；宿主 `20138` 在 ABC 后按精确路径 SIGTERM 退出；最终 ABC、开发宿主 0 个。
- 生产包/执行 SHA、生产 config/词库、开发 config 均未变；开发私有词库仅正常学习变化（`a49098be…`）。
- 未清库、未 purge、未改 `UserDefaults`/HIToolbox、未自动切源。

## 证据

- `138-evidence/native-trace.jsonl`（47 行 schema3）、`10/11/13/14-memory-*.txt`、`04-round-state.json`、`05-final-state.txt`。
- 安装与换包：`01-install.log`、`01b-installation.json`、`00-pre.txt`。
- 采样脚本：`platforms/macos/build/acceptance-137/sample-137.sh`（沿用 136 的逐键守卫，去掉会冻结进程的 `sample`）。
