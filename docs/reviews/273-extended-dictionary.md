# 273 — 可选扩展词库（U2-3，ADR-348）

> 2026-11-13，air（arm64 / macOS 27.2）。代码与数据完成并已换包复验（候选 `a725fff`，ZIP `1b0ab3c7…`，
> 宿主执行 `01f32c51…`）；扩展档真机切换与内存门禁 PASS。

## 1. 做了什么

- 新增 `dict.extended`（默认关闭）。开启时整包切换到：
  - `wubi86-extended.tsv`：全量单字 27,823 + 全量 jieba 词组 337,344 + D15/D16 + D17 三级简码，365,167 行 / 6,209,535 字节；
  - `pinyin-extended.tsv`：全量拼音词表按 jieba 词频取前 50,000（含 D15/D16），50,162 行 / 1,105,067 字节。
- 关闭时仍装载 `wubi86-core.tsv` + `pinyin-core.tsv`，行为与 1.3.0 完全一致。
- 切换时机：设置页写配置后，不在组合中立即重建会话；组合中延迟到当前组合结束后的下一个空闲按键，不丢编码。
- 文件缺失时整体回退核心档并在宿主显示数据错误；不装载半套数据，也不会反复重试。
- `build.sh` 打包两份扩展文件；`test-extended-dictionary.py` 守体积、覆盖、报告 SHA 与「不新增私有区字形」。
- 第三方词库导入沿用现有「设置 → 词库 → 导入用户词库」（本地 TSV，只写用户词库，不改内置表）。

## 2. 内存实测（`ime-cli` + `vmmap -summary`）

| 档位 | 数据 | 存活堆 | footprint |
|---|---|---|---|
| 核心（现状） | 20k 五笔词组 + 20k 拼音词 | 13.6 MiB | 17.0 MiB |
| 扩展五笔 + 核心拼音 | 全量单字 + 337,344 词组 | 25.7 MiB | 26.5 MiB |
| **扩展档（本次）** | 上述 + 50,162 拼音词 | **40.4 MiB** | **43.1 MiB** |
| 扩展五笔 + 全量拼音 | 上述 + 340,960 拼音词 | 约 160 MiB | 约 196 MiB |

结论：扩展五笔边际成本约 12 MiB；再加 50k 拼音约 15 MiB；全量 341k 拼音不可接受，继续按 ADR-031 不随包。
扩展档门禁建议 `LIMIT_MB=64`（实测 40.4 MiB，给宿主 UI/分配器留余量）；核心档维持 ADR-338 的 24 MiB。

## 3. 数据与许可

- 未引入新来源；均由既有 D3/D4/D5/D10/D15/D16/D17 派生，许可 CC-BY-SA-4.0。
- `data/sources.toml` 新增 `wubi-extended-v1`、`pinyin-extended-v1`；同时修正 `wubi-core-v2` 的陈旧 SHA
  （旧登记 `20779a…`，实际 `342d03…`，1.3.0 三级简码入表后未同步）。
- `docs/数据来源与许可.md` 新增「U2-3 可选扩展词库」小节。
- 生成命令：
  - `cargo run -p wubi-encoder --example generate_core -- <单字> <词组> data/generated/wubi86-extended.tsv <报告> 0 0`
  - `python3 tools/prepare-pinyin-core.py data/generated/pinyin-words.tsv data/generated/pinyin-extended.tsv 50000 2000000`
- `prepare-pinyin-core.py` 的默认参数保持 20000/800000；核心输出逐字节未变（SHA `c9541cf4…` 复跑一致）。

## 4. 验证

| 项 | 结果 |
|---|---|
| `make verify` | PASS（502 产物零网络符号） |
| `make macos-offline-tests` | **63 文件 / 337 例 PASS**（新增 5 例） |
| `build.sh --strict` | PASS（扩展文件已进 `Contents/Resources`） |
| 默认生成物回归 | 核心五笔 `342d03…`、核心拼音 `c9541cf4…` 与改动前一致 |
| CI（PR #287） | `check` / `fuzz` / `macos` / `dco` 全 PASS |
| 真机：开关关 | `ybkl` → 原样字母 `ybkl`（核心表无此码） |
| 真机：开关开 | `ybkl` → **离别**（扩展表独有） |
| 真机：关闭后 | `ybkl` → 恢复 `ybkl` |
| 扩展档内存 | **PASS**：3 轮稳态存活堆 **48.0–48.2 MiB**（`LIMIT_MB=64`） |
| 核心档内存 | **PASS**：3 轮稳态 **20.8–21.0 MiB**（`LIMIT_MB=24`） |
| 用户数据 | 真实 `config.toml` `3aea2bca…`、词库 `8fa18a7d…`、练习 `2512f4…` 前后不变 |

候选身份：ZIP `1b0ab3c7…`、源码 `c8061008…`、执行 `01f32c51…`、universal、Developer ID + 公证；
安装备份 `updates/install-backup-20261113T140802Z/`。证据在 `platforms/macos/build/acceptance-air-u2-3-287/`。

## 5. 已知限制与后续

- `weixin → 微信` 不在全量拼音表中，扩展档也解决不了；需 D16 补充或用户词库导入，另行处理。
- 扩展档会带来更多重码与位次变化，这是数据本身的效果，不改变排序/简码规则。
- 全量 341k 拼音词表要等拼音后端降低多索引内存后再评估（另写 ADR 改判 ADR-031）。
- 「组合中切换延迟到空闲按键」的代码路径已实现，但设置面板打开时会先取消组合，**未单独构造组合中切换的实键场景**。
- 复验期间沿用机器上已有的 `/tmp/lampyris-diag` 私有数据根（真实数据未被改动）；结束后已 `launchctl unsetenv LAMPYRIS_SUPPORT_DIR`
  并重启宿主，当前输入源已选回萤火虫。

## 6. 真机复验记录（已完成）

1. 从 `main` `a725fff` 的 CI 验收包安装 air，执行 `01f32c51…`；扩展文件在 `Contents/Resources`。
2. 设置 → 输入 → 五笔与拼音 → 打开「扩展词库」；`ybkl` 上屏「离别」；关闭后恢复原样字母。
3. `LIMIT_MB=64` 扩展档 PASS（48.0–48.2 MiB）；关闭后 `LIMIT_MB=24` 核心档 PASS（20.8–21.0 MiB）。
4. 真实 `config.toml` / 用户词库 / 练习进度 SHA 前后不变；输入源已还原为萤火虫。
