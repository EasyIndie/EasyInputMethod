# 134 build4 原生验证与词典加载内存收敛

## 当前结论

B（arm64/macOS 27.0.1）从已合并 main `0f913492b9a0e27ab32bba95462cfcf4291e1625` 统一构建固定开发包
0.1.0/**build4**（隔离公证 run 39770165333），静态核验安装后，用户只切一次开发源完成本轮原生采样：

- ZIP `b3b38bb4ac664305164b8bedbdd454e403d0bcfd0ae13328604717aa011380d2`，
  执行 SHA `49a49a2a7f47de895e282754a66e35c8d90403c723a7ce471b95a7de25d4a3ef`，
  身份 `cn.jokerhub.inputmethod.LampyrisIMKTest.d4fcecfb-…`，arm64，Developer ID 2N62934Y28，
  `spctl` accepted、`stapler validate` 通过；包内四份数据表 SHA 见 `134-evidence/package-data-sha.txt`。
- 内嵌计时 **schema2**（新增 `hideUs`）100 键全部落在自建 TextEdit 文稿，逐键源/窗口/路径/焦点守卫：
  首轮 50 键 total **p95 10.770ms / max 37.299ms**（仅冷首键 1 次 ≥16ms），暖态（2–50）p95 10.620ms/max 11.685ms，
  engine p95 1.114ms；附加 50 键 p95 11.154ms/max 16.900ms。
  相对 build2 的 22.124ms/58.039ms，**p95 已低于 16ms 门禁**，但仍按「单一候选样本」记录，不提前关闭最终 RC 门禁。
- `hideUs` 16 次提交 p50 0.849ms / p95 1.222ms / max 1.222ms；`commitUs` p95 7.016ms。
  130 中「提交后 10–17ms 未归因」在 build4 已被分段解释，隐藏本身不再是长尾来源。
- 功能：首轮六词与八项附加（混输数字/方向/退格/Esc/Enter、五笔空格/数字、拼音三词含 **xi'an**、最终 mixed）
  全部实际读回通过；config 语义恢复且字节 SHA 未变。
- 内存：同进程采样后 physical 37.8MiB / peak 40.3MiB，malloc 活跃 17.4M、碎片 12.0M（41%）、换出 18.7M；
  冷启动宿主仅 8.9MiB。**30MB 门禁仍未关闭**，但已把主因定位到词典加载期分配器碎片并完成 ADR-255 最小修复，
  离线峰值 24.4–25.4MiB → **15.8MiB**；原生复验须等下一次统一签名包。

## 安装与数据边界

- 用户保持 ABC 时用 `scripts/macos-imk-dev.py install --app … --stop-host` 换包：旧 build2 自动备份到
  固定根 `replacement-p57rjckg/previous.app`，换包前后输入源集合完全一致，运行中宿主 `50615` 按精确路径退出。
- 生产包 `17053e1`/执行 `535d546f…`、生产 config `3bc1117c…`、生产个人词库 `74f76e92…`（29 行）全程未变；
  开发 config 仍为 `3bc1117c…`（mixed、8 个显式快捷键）。
- 开发私有词库按正常学习变化：14 行，SHA `c96801b7…` → `8b7084e4…`（仅本轮提交词）。
- 手工文稿「萤火虫性能验收-115.txt」未触碰；未清库、未 purge、未改 `UserDefaults`/HIToolbox、未自动切源。
- 收尾：marker 在 ABC 前删除；宿主 `66727` 在 ABC 后按精确路径 SIGTERM 退出；冷启动基线宿主 `69241` 只读测量后同样精确退出，
  最终输入源 ABC、开发宿主 0 个。

## 冷首键分段

| 阶段 | 134 build4 | 130 build2 |
|---|---|---|
| total | 37.299ms | 58.039ms |
| content | 15.678ms | 8.709ms |
| status | 7.362ms | 29.372ms |
| preedit | 6.723ms | 10.050ms |
| window | 3.800ms | 4.431ms |
| caret | 2.903ms | 3.653ms |
| engine | 0.721ms | 1.710ms |

冷首键仍是唯一 ≥16ms 的样本：`status` 的 29ms 未复现，剩余成本集中在首次内容排版（15.7ms）。
暖态无 ≥16ms 样本，故本轮不据此新增预热或缓存改动（ADR-253 已否决以预热掩盖根因）。

## 内存：ADR-255（TSV 加载去碎片）

134 原生宿主采样后 malloc 活跃 17.4M 却有 12.0M 碎片，明显与 2.5MB 数据量不符。
`ime-table::Table::from_tsv` 原先把每行构造为 `String`+`Vec<Entry>` 再整体重打包，48k 行会产生同量临时小分配；
拼音字/词表与简繁映射同样逐行 `Vec<&str>`、重复 `String` 插入。

修复（ADR-255）后离线 `mem_probe`（`MEM_PROBE_HOLD`，四表全加载，各 3 次）：

| 指标 | 修复前（HEAD） | 修复后 |
|---|---|---|
| 峰值 physical | 24.4–25.4MiB | **15.8MiB**（3/3 一致） |
| 稳态 physical | 15.0–16.1MiB（8.4–12.4M 已换出） | 13.0–15.8MiB（0–11.8M 换出） |
| malloc 活跃 | 10.9M | 10.9M（语义不变） |
| malloc 碎片 | 3.2–4.4M（2.5s 采样曾达 11.8M） | 1.2–4.1M |

宿主 8.9MiB 基线 + 修复后约 16MiB 峰值，已接近但尚未证明 30MB 门禁；
稳态 physical 受系统换出影响不稳定，报告同时列换出量，不用 RSS 替代、不忽略 swap。

## 回归与门禁

- `make verify` 全绿零诊断（fmt/lint/test/deny/verify-no-network，204 个产物隐私检查）。
- `make macos-offline-tests` 全部 PASS；`./platforms/macos/build.sh --strict --universal` 双架构严格构建通过。
- 未运行 `cargo fuzz`（本机未装 `cargo-fuzz`，历史记录同）；解析错误路径/行号/排序/重复行语义由既有单测与真实词表回归覆盖。
- 无 tag / 无正式 Release；升级闭环、App Store 可行性、同 RC A/B、五日门禁与完整客户端矩阵仍未完成。

## 证据

- `134-evidence/package-pre-state.txt`、`package-data-sha.txt`、`install.json`：换包前后 SHA 与安装器结果。
- `134-evidence/native-trace.jsonl`（100 行 schema2）、`native-trace-summary.txt`、`native-round-state.json`。
- `134-evidence/native-host-memory.txt`、`native-host-fresh-baseline.txt`、`native-final-state.txt`。
- `134-evidence/mem-probe-before.txt`、`mem-probe-after.txt`：ADR-255 前后各 3 次。
