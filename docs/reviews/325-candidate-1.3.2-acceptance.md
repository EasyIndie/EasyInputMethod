# 325 — 1.3.2 / build 45 候选真机验收（air，2026-11-19）

> 候选来自 main `93df6cc`（PR #339 合入后）的 `macOS Acceptance Package` run `44638834487`。
> 结论：**装包身份一致、学习区根序与识别码按新数据显示、质量样本 30/30、热键 8/8、零外联**；
> 性能门禁的**粗粒度 footprint tripwire 在验收脚本内越界一次（44.1 > 44.0）**，归因见 §6，非产品回归。

## 1. 候选身份

| 项 | 值 |
|---|---|
| 提交 | `93df6ccc9a54ceed5aac3b1445488af92790bf07` |
| 版本 / 构建 | 1.3.2 / 45 |
| ZIP（universal） | `906761b982d935c4f22a8f3cad67903acaf3e7d7265cb43a5e9b251736d3a776` |
| 包内宿主执行 SHA-256 | `46cc4d7b6f7a8ef36b77e0f39c041983321cae9de14617a2514507ad8d701dd5` |
| 源码包 | `Lampyris-1.3.2-source.tar.gz` = `1c1ebc8077b0bccf58467ea9c07dadbe3cabaaefc0a5c73ded8228b0eb1b39bb` |
| 签名 | Developer ID Application: Zhizhou Wang (2N62934Y28)，`spctl` → Notarized Developer ID |

## 2. 装机

- 前置：输入源已由用户移除（API 不能移除，报告 095）；旧宿主 `94064` 由 `--stop-host` 收掉。
- 安装：`make macos-fast-reinstall APP=…/Lampyris.app ARGS="--stop-host --keep-data"`；
  安装器回读 `accepted`，`spctl` Notarized。
- 装后回读：`exec = 46cc4d7b…`（= 包内），`CFBundleShortVersionString/BundleVersion = 1.3.2 / 45`。
- 用户数据保留：`config.toml` = `52af2b90f28a280c…`（未变）、`user-dictionary.tsv` 2,477 → 2,487 行（验收读写产生）。
- 回滚备份：`~/Library/Application Support/Lampyris/uninstalled/bundle.GNGiIb`（1.3.1/44）。

## 3. 学习区（本版的实际变化）

装机包内 `Contents/Resources/B0-runtime.tsv`：5,021 行，`full` **4,993** / `partial` **28** / `unknown` 0。

题池（`Practice.bank` 口径，按装机数据统计）：

| 题库 | 数量 | 1.3.1（`f9cede3`） |
|---|---|---|
| 完整码 | **5,021** | 5,021 |
| 三级简码 | **3,362** | 3,362 |
| 二级简码 | **598** | 598 |
| 一级简码 | **25** | 25 |
| 识别码 | **2,739** | 2,714（+25） |
| 字根 | **4,991** | 4,967（+24） |

真机键入（`tools/macos-probe/type-session.sh`，HID 投递，回读上屏文本）：

| 键入 | 上屏 | 说明 |
|---|---|---|
| `eevk` | 貂 | 本版新增 full（`爫+𠂢+刀+口`） |
| `gdnu` | 忝 | 本版新增 full（`一+大+心` + 识别码 U） |
| `siwh` | 榉 | 双读法新增（`木+丷+八` + H） |
| `aveu` | 茛 | 双读法新增（`艹+彐+衣` + U） |
| `dcg` / `xgu` / `j` | 码 / 母 / 是 | 回归对照 |

学习区面板（实拍 `/tmp/panel3.png`、`/tmp/panel4.png`）：

- `eevk`：`完整码 EEVK`、`简码 三 EEV`、字根 `爫 E` `𠂢 E` `刀 V` `口 K`。
- `gdnu`：`完整码 GDNU`、`简码 三 GDN`、字根 `一 G` `大 D` `心 N`、**识别码：捺·上下结构 U**。
- 两例都**没有**橙色「拆解待核验」角标 —— 这正是本版把 447 条 `partial` 转 `full` 后用户能看到的变化。

## 4. 质量样本（`quality-samples.sh`，隔离私有根）

**30 项样本 30/30 PASS，0 FAIL**：五笔四码自动上屏、一级简码、混输拼音兜底、全拼双字词、拼音长词、中文标点（句/逗/引号）、
翻页不破坏输入、撤销回空态、长文本不丢字、数字后句点半角等。

## 5. 热键与输入法行为（`acceptance-auto.sh`）

Shift×2 英文/中文、⌥P 标点、⌥F 全角、⌥T 繁简往返、⌥M 模式循环 **全部 PASS**。
`source_mismatch_rounds = 0`，`max_connections = 0`（全程零 TCP/UDP）。

## 6. 性能与内存（含一次越界的归因）

| 采样 | p95 稳态 | footprint steady | heap live |
|---|---|---|---|
| 验收脚本内（第 2 次） | **7.04 ms** | 44.1 MiB（硬顶 44.0，**FAIL**） | 21.3 / 24 PASS |
| 装后首跑（第 1 次） | 33.4 ms（冷首键） | **57.3 MiB** | — |
| 单跑复测 ×3 | 6.84 / 6.99 / 6.75 ms | **42.6 / 36.5 / 36.5 MiB** | — |
| 独立一次 | 7.04 ms | **35.9 MiB** | — |

归因（与报告 305 §4.2 同一现象）：

- 同一份二进制 6 次采样，footprint 落在 **35.9–57.3 MiB**：装后首跑最高、随后稳定在 35.9–42.6。
  真值（干净 A/B 口径）= **35.9 MiB**，与 1.3.1 的 34.1 相差 **+1.8 MiB / 字表 +34%**，早前已在 ADR-379 定案。
- 验收脚本内的 44.1 是「脚本内状态放大 + 2 次测量里较高的一次」，只越界 0.1 MiB；硬门禁 `heap live ≤ 24` 稳定（21.3–21.7）。
- **处置**：不改阈值、不为凑绿重跑到过为止。把现象记在这里并提单：footprint 采样应固定「预热一轮 → 静置 → 再测」，
  否则同一二进制会有 20 MiB 的抖动；在协议固定前，验收以 `heap live` 为硬门禁、footprint 只作粗粒度参考（ADR-379 原文）。

## 7. 状态与还原

- 最终状态：输入源 `cn.jokerhub.inputmethod.Lampyris.default` 选中，宿主运行中，`exec = 46cc4d7b…`。
- 还原：输入源切回 ABC 即可；旧包仍在 `uninstalled/bundle.GNGiIb`。
- 复核命令：

```sh
shasum -a 256 ~/Library/Input\ Methods/Lampyris.app/Contents/MacOS/Lampyris
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" ~/Library/Input\ Methods/Lampyris.app/Contents/Info.plist
make macos-acceptance-full OUT=/tmp/acc-1.3.2b
```
