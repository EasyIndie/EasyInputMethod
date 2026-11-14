# HANDOFF — 当前状态

## 0. 元信息

- 更新：2026-11-15 / Claude Code（**air 本机**）。阶段：**已发布 1.3.0 / build 43**（tag `v1.3.0`，Release、站点已上线）；
  air 与 pro 均已装发版产物（执行 `9cb738c9…`），30/30 样本、性能、内存、IT-22 A 档 / N1–N5 全部 PASS。
- 分支：`main` = `7b95ba6`（PR #314 86 专注 + 标准变体、PR #315 D2 字形别名均已合入）；`dev` = `8aa77f4`（与 origin 同步）。
- 版本：`Cargo.toml` = **1.3.0**、`packaging/build-number` = **43**；最新 tag **`v1.3.0`**。**下次正式发版前必须重新绑定候选身份。**
- 最近验证：`make verify` PASS（538 产物零网络符号）、`make macos-offline-tests` **67 文件 / 336 例 PASS**、`validate_b0.py` PASS（1,000 条）、
  `build.sh --strict` PASS、`tools/check-level3-codes.py` PASS（3,362 条）。
- 1.2.1 身份：提交 `168115e`、ZIP `102f4928…`、DMG `a6f4bdbd…`、更新程序 `b04049e3…`、appcast `40`、包内执行 `3eeeb0aa2ae4be0facd0120c854ea822ad1ba749dd3a22611f39a97db6fc32d9`（`docs/releases/1.2.1.md`）。
- 1.2.0 候选身份：提交 `31fdbcd`、ZIP `64eeb90f…`、源码 `3dc6f717…`、宿主执行 `ef25e92ba085ea3f556e12d477fb1b6a6cd08ebbc3b74897fdb7b2d9f6eead64`（`docs/releases/1.2.0.md`）。

## 1. 设备与数据

| 设备 | 已装包与执行 SHA | 数据 / 输入源 | 恢复点 |
|---|---|---|---|
| **air**（arm64 / macOS 27.2 / Xcode 27，用户 `joker`；本会话已有辅助功能/事件投递权限） | **1.3.0 / build 43**（2026-11-13 装机，报告 270），ZIP `a191b60d…`，宿主执行 `bda6f0903f95e07f9800577083eee452d46b0b9f3ca9520caab23d298a790df9`（U1-4 候选 `b8dd20f`，2026-11-14 装机；
备份 `updates/install-backup-20261114T084240Z/`）；输入源 `Lampyris.default` 已启用并选中；**`mode=wubi`** | 2026-11-15 01:19 采集：config `888ed018…`（mode=wubi / punctuation=chinese / full_width=half / chinese_variant=simplified，显式 hotkey 8 项）、词库 2046 行 `182ee41c…`；与 2026-11-14 样本时的 `3aea2bca…`/1838 行不同，属用户日常使用，非本轮改动 | build 42 `5d75e2fd…` 在 `updates/install-backup-20261113T051338Z/`；build 41 `aa040adc…` 在 `updates/install-backup-20261113T044337Z/`；`main` 候选 `2610d1f` 在 `updates/install-backup-20261113T041111Z/` |
| **pro**（Intel / macOS 13.7.8，用户 `bot`，SSH 别名 `pro`） | **1.3.0 / build 43**，宿主执行 `9cb738c9…`（2026-11-13 用户经 `upgrade.py` 从 1.2.0/39 升级） | config `b8c7a351…` 未变、词库 963 行（962→963，真实键入；`show_wubi_learning=true` 是用户有意设置） | `updates/upgrade-2026-11-13T11-40-50Z-AE6D4E61/`；更早备份见 `updates/` |

## 2. 本轮完成

### 2.1 结构库 / corpus 线（2026-11-06，报告 240–246）

| 范围 | 结果 |
|---|---|
| **corpus 第二阶段需求清单** | 新增 `docs/结构库第二阶段需求.md`：把缺口拆成 N1 字根字形身份库 / N2 笔画笔顺 / N3 结构标注 / N4 完整拆字，写清准入规格、已否决路线、四道验收门槛（3,000 字 ≥98%、许可齐全、运行资源 ≤512 KiB、离线查询 p95 ≤5ms）与 M2-1～M2-4 里程碑。**体积按现状 558 B/字 外推会超标 3 倍**，已写成第二阶段必做项。 |
| **D3 许可更正（报告 246 / ADR-310）** | 上游 `NOTICE.md` 明确 `wubi86_chaizi.txt` 与 `HeiTiZiGen.ttf` **未附带任何版权声明**；登记从「MIT/低风险」改为「未声明/高风险/仅构建期 oracle」。B0 不再用 D3 作组件来源（`full` 737→735，8 条 D2 漏拆如实标 partial），新增门禁「产物不得出现 D3 来源」。 |
| **字体路线关闭（报告 246；2026-11-14 复核 qingg）** | WindInput / D3 字体无许可；D2 的 etmon 字体仍未声明，不能进产物。qingg 2019 版 `98WB-2.otf` 经复核为 **OFL 1.1**（Source Han Sans 派生、已改保留字名），仅作构建期字形参考，不随包分发；2024 版 `98WB-3.otf` 无许可记录，未采用。另记两条已证伪路线：私有区等价类传递、IDS 叶数投票。 |
| **B0 schema v5 + D19（报告 245）** | 登记 `yi-bai/ids`（MIT，下载不入库）；`ids`/`idsStructure` 作结构参考（与识别码结构 559/619=90.3% 一致，不覆盖），严格条件补占位 23 条。 |
| **B0 schema v4（报告 244）** | 查明 D2 是「每码位一形」：末位私有区=识别码槽、其余=占位字根；组件数↔码长 100% 对齐，识别码 622；41/42 成字字根有笔画（D14 补 了/也/上）。 |
| **B0 schema v3（报告 243）** | 占位组件 `null` + 键位推断；修掉 D3 字根按字符解析（空格混入组件、BOM/CRLF）缺陷。 |
| **13% 结构不一致归因（报告 242）** | 66/512 是两套**分类口径**差异（独体字判杂合、拆法不同、包围），不是数据错误；处置=五笔识别码为权威、IDS 只作校验、差异归档。 |
| **corpus 数据来源调研（`docs/research/corpus-data-sources.md`）** | 主选 `yi-bai/ids`（MIT）+ Unihan 交叉校验；**不采用** Make Me a Hanzi 的 Arphic 图形、Hanzi Writer、KanjiVG、字典抓取。 |
| **B0 现状（schema v7，2026-11-15）** | 1,000 字：`full` **928** / `partial` **68** / `unknown` **4**。3,000 字：`full` **2,614** / `partial` **232** / `unknown` **154**；运行时同。标准 v1（ADR-358）+ D2 字形别名归一化（ADR-359）下 `full` 必须通过标准字根/键位校验；98/新世纪仅预留 profile，不实现；报告 280–285。 |

### 2.2 发布线（2026-11-05，1.0.0 → 1.1.0/build 38）



| 范围 | 结果 |
|---|---|
| **1.0.1（ADR-305 / 报告 225，build 35）** | `input.full_width` Bool → 枚举（半角/全角，标题「字符宽度」），⌥F 改为写配置与 ⌥P/⌥T 对齐，旧布尔配置只读兼容。 |
| **1.0.2（ADR-306 / 报告 226，build 37）** | `stopHost` 在自更新时把自己 SIGTERM 掉 → 已修；1.0.0→1.0.1 真机演练 + 1.0.2 复验闭环（回执 `payloadSHA256=732756e5…`、更新程序 bundle 被替换并备份、staging 清理、进程未自杀）。 |
| **B 基线采集（报告 227）** | `tools/eval/` 200 条样本（单字/两字词/三四字/混排长句/一级二级简码）+ `ime-eval` 评测器 + `baselines/1.0.2-build37.json` 入库，任意包可一键复跑。 |
| **1.1.0 代码（ADR-304 / 报告 228，build 38）** | D17 一级简码 25 条入表（`data/sources/wubi86-level1-codes.tsv` + `tools/check-level1-codes.py`）+ `personalize` 改「有界位次上移」（首选位保护、不跨精确/补全分块）。评测：`jianma1` 命中 56%→100%、首选 32%→100%，ALL 命中 92.0%→97.5%、首选 85.5%→94.0%，其余类别零劣化；5 条核心单测改动/新增。 |
| **air 装机** | 1.1.0/build 38 候选已装 air（执行 `d3c5a2ef…`），证据 `platforms/macos/build/acceptance-air-1.1.0-b38/`。 |
| **1.1.0 人工走查通过 + 验收可移植性（报告 234）** | 用户本机执行：A 档 10 项 + IT-25 四项全 PASS。按用户要求，验收改为**只依赖系统自带应用**：`client-matrix.sh` 必需=TextEdit/Safari、Chrome/Xcode 标 optional（缺装 SKIP）、Xcode 不再写死版本路径；新增 `client-matrix-verdict.py` 与 `test-acceptance-portability.py`（含清单检查）。 |
| **1.1.0 发布准备稿（docs/releases/1.1.0.md）** | 绑定候选身份（ZIP `448d3170…` / 源码 `e0b9536b…` / 执行 `d3c5a2ef…` / 提交 `393318c`）；写清唯一产品变更（AD-304 简码 + 有界位次上移）与评测对比；验收结果按「已完成 / 待办」分列；延迟按 ADR-307 写两个数（稳态 p95 6.71ms、冷首键 p95 25.77ms）。`docs/archive/发布说明-0.1.15.md` 标注为 0.1.15 历史底稿。 |
| **验收状态自归位（报告 232）** | 新增 `ime-state.sh`：轮前 `--snapshot` + `--ensure`（mixed/chinese/half/simplified），trap 里 `--restore` 再 cleanup；`acceptance-auto`/`quality-samples` 已接线。修掉「上一轮留下 ABC/繁体 → 本轮 8 个热键项 + 4 个质量样本连锁 FAIL、跑完还改用户偏好」的问题。 |
| **验收自清场固化（报告 231 §6）** | 新增 `platforms/macos/tests/test-probe-cleanup.py`：凡开窗口/拉应用的探针脚本必须接 `cleanup-windows.sh` + `trap EXIT/INT`，含反向自检；规则同时写进 `AGENTS.md` 铁律 11、`iterate-macos-ime` skill §7、`CONTRIBUTING.md` §5、探针 README 清单。上马时抓出并修好 `multi-display.sh`（从不清 TextEdit）与 `type-session.sh`（退出不收测速窗口）两处缺口。 |
| **验收收尾清理（报告 231）** | 新增 `cleanup-windows.sh`：按 URL/标题/未保存内容签名回收探针自己开的 Safari/Chrome 标签、Xcode 窗口、TextEdit 文档与 `imetype`/`keytopid` 进程；四个验收脚本都挂 `trap EXIT INT TERM`，失败/中断同样清理。`client-matrix.sh` 改为自建并关闭 TextEdit 文档。实测：连跑三次后 TextEdit 未运行、Safari/Chrome 0 标签、Xcode 仅剩用户自己的窗口。 |
| **验收提效（报告 230）** | 离线回归并行化（串行 166s → **34s**，`JOBS=N`）；删除腐烂的第二套 runner（`run-local-acceptance.py` 必失败 → `macos-local-acceptance` 改为 `macos-offline-tests` 别名）；`acceptance-auto` 增加 `FAST=1` 档（9 分钟 → **4.7 分钟**）；IT-22 从 65 项压到 **12 项（每次换包）+ 5 项（每版一次）**，映射见 `docs/tasks/T-ITER-22-coverage.md`；新增 `test-acceptance-map.py` 防文档腐烂，修掉 `test-preview-menu.py` 在有宿主运行时必挂的假 FAIL。 |
| **延迟门禁修复（报告 229 §7）** | `perf-session.sh` 从 `--self-post` 改为 **HID 投递 + `NSTextInputClient` 回调计时**（`imetype` 新增 `TimedTextView`），`type-session.sh` 输出 `latencies_ms`，`soak-session.sh` 同步换驱动并要求 `ime_rounds > 0`。1.1.0/build 38 首次实测：**160 键，p50 4.19ms / p95 14.64ms / max 24.68ms**，0 外联，RSS −0.1MiB。 |
| **自动探针（报告 229）** | 用户授权后跑 `acceptance-auto.sh`：热键/上屏 **8/8 PASS**、TextEdit 实键入 `你你好。` PASS、已装包=候选包与数据表 25 条简码 PASS；**性能门禁改判 BLOCKED**（自投递不计 IME，见 §3），Safari/Chrome/Xcode 回读为空 BLOCKED。工具链三处缺陷已修：相对 `OUT` 导致测速空结果、性能项排在客户端矩阵之后（矩阵结尾还原 ABC 会抢源）、终端项误投用户 shell。 |

## 3. 未决

剩余待办见 **`docs/待办与积压.md`**（2026-11-13 按 1.3.0 发布后对账）：

- **P0 · 已清零**：pro 升级与实键入确认均已由用户完成（2026-11-13，实打候选与切源正常）。
- **P1-U · 输入体验与学练闭环（ADR-324）**：15 项里 13 项已完成并真机复验；
  **U2-3 扩展词库真机 PASS**（ADR-348，报告 273）；**U3-5 符号 / emoji 真机 PASS**（ADR-349，报告 274）；
  **U2-5 分阶段解锁真机 PASS**（ADR-350，报告 275）；**宿主内完整引导真机 PASS**（ADR-351，报告 276）；
  **U3-1 整句模型已关闭**（ADR-352，报告 277/278）；**U3-4/N1-d 已接入（ADR-353，报告 279/280）**：
  初版清单误用 D3 BMP PUA，已更正为 D2 补充区；可定位 79 个 PUA，按 `(PUA, 键位)` 核验 66 条，
  状态 `verified 58 / partial 8 / unresolved 13`。B0 1,000 字 `full` 735→919；运行时 3,000 字 `full` 1,904→2,454；
  D3 不再作 `componentsSource`；未解决项仍以 `？:键` 占位，不猜。
- **P1 · 数据与方案**：corpus M2-1 调研 ✅、N1-d ✅、N2/N3/N4 ✅（ADR-355）、cjk-decomp 扩量 ✅（ADR-357）、标准 v1 ✅（ADR-358）、D2 字形别名 ✅（ADR-359）；覆盖已到许可数据上限（87.1%），P1-5 已关闭；余项仅 13 个语境歧义 PUA（可选）与多方案码表（TBD-2，98/新世纪暂不实现）。
- **P2 · 有证据才做**：排序观察期、位置记忆、冷首键、拼音后端评估、n-gram（均写触发条件）。
- **明确不做**：云/账号/广告/统计/剪贴板/语音；平台扩展单独立项，不与 macOS 同批。

建议：先在「产品可感 B」（U2-3 扩展词库 / U3-5 符号）与「数据地基 C」（P1-2 调研）之间选一条主线。

## 4. 下一步

| 步骤 | 内容 | 授权 |
|---|---|---|
| 1 | ~~批次 A/B/C、build 43、真机 30/30、性能/内存、人工走查、DMG 完成页~~ | ✅ 2026-11-13 |
| 2 | ~~tag v1.3.0 / Release / 站点部署~~ | ✅ 2026-11-13（报告 272；站点回读 `v1.3.0 · 构建 43`） |
| 3 | ~~pro 升级到 1.3.0~~ | ✅ 2026-11-13（用户手动执行，执行 `9cb738c9…`） |
| 4 | 文档对账 + `dev → main` PR | ✅ 2026-11-13（PR #286） |
| 5 | ~~U2-3 扩展词库真机复验~~：候选 `a725fff` 已装；`ybkl` 开→离别、关→原样；扩展档 48.0–48.2 MiB / 核心档 20.8–21.0 MiB | ✅ 2026-11-13（报告 273） |
| 6 | ~~U3-5 符号 / emoji 真机复验~~：候选 `d779186`（执行 `a184fc1e…`）⌥S 面板、反引号前缀、emoji 插入、零外联 PASS；核心 29/30（失焦项 AppleScript 挂起 BLOCKED） | ✅ 2026-11-14（报告 274） |
| 7 | ~~U2-5 分阶段解锁真机目视~~：候选 `13ec97b`（执行 `739bdf7a…`）私有根新进度仅字根 → 字根 30 字解锁一级简码 → 一级简码 25 字解锁二级简码 → 关闭开关六段全开 | ✅ 2026-11-14（报告 275） |
| 8 | ~~宿主内完整引导真机目视~~：候选 `b8dd20f`（执行 `bda6f090…`）菜单入口/翻页/首次自动弹窗 PASS；标记恢复、探针窗口与临时文档已清理 | ✅ 2026-11-14（报告 276） |
| 9 | ~~U3-1 整句模型~~：原型未达 +5pp，**已关闭**（ADR-352，报告 278）；不再投入 | ✅ 2026-11-14 关闭 |
| 10 | ~~U3-4/N1-d~~：已更正数据源并接入 66 条 `(PUA, 键位)` 核验；运行时 `full` 1,904→2,454，`partial` 876→326；剩余 13 个 PUA 保持占位 | ✅ 2026-11-14（报告 280） |
| 11 | ~~N2/N3/N4 数据地基~~：56 个成字字根真实笔顺、结构覆盖 2,766、8 个 D2 漏拆补齐；schema v6 | ✅ 2026-11-14（ADR-355，报告 281） |
| 12 | ~~标准 v1 + 86 专注~~：schema v7、241 条 root/key、98/新世纪仅留 profile | ✅ 2026-11-15（ADR-358/359，报告 284/285；PR #314/#315） |
| 13 | **集成验收（不发版）**：用当前 `main` 构建候选包，做自闭环验收（热键/上屏、TextEdit 实键入、性能/零外联、学习区数据回读），确认已合入改动无回归 | ⏳ 待授权换包 |

**发版决策（2026-11-15）**：功能迭代较多，**先不发版**，先做集成验收。
剩余开发项：86 覆盖率已到**许可数据上限**——3,000 字 `full` 2,614（87.1%）/ `partial` 232 / `unknown` 154；
继续提升需要 canonical 五笔根序数据（公开可用的没有），或接入 CDP（GPL-3，结构/笔数，不补根序）。
98/新世纪按用户要求暂不实现，只保留 `schemes/*.toml` 扩展点。整句模型已关闭。

## 4.1 换到 air 后怎么开工

| 项 | 值 |
|---|---|
| 系统 / 架构 | macOS 27.2 / arm64，用户 `joker`，SSH 别名 `air` |
| 仓库 | `~/Documents/EasyInputMethod`（先 `git fetch origin --prune && git switch dev && git merge --ff-only origin/main`） |
| 已装包 | **1.3.0 / build 43**（发版产物，宿主执行 `9cb738c9…`），输入源在用，不要重装 |
| 证据目录 | `platforms/macos/build/acceptance-air-1.3.0-release/`（发版产物与安装记录）；更早候选目录保留作历史 |

```sh
cd ~/Documents/EasyInputMethod && git fetch origin --prune && git switch dev && git merge --ff-only origin/main
git log --oneline -1                        # 记下这个提交
./scripts/handoff-status.sh --for=device    # 重采已装包执行 SHA / config / 输入源 / 词库行数
make verify                                 # cargo 门禁
make macos-offline-tests
```

**air 已知平台差异（别当 bug）**

- `q ` = 「多」（五笔一级简码），首个按键常被窗口激活吞掉 → 探针串看起来像「多你好。」。**1.1.0 起一级简码 25 字都是 1 键首选，探针串开头会多出简码字，属预期。**
- Safari/Chrome/Xcode 自动化已移除（2026-11-14）；TextEdit 焦点属性读不到时回退窗口文本区。
- VoiceOver 掉 ABC 已复测**不可复现**（报告 215）；日志里 `Refusing connection name` 来自搜狗，与萤火虫无关。
- 内存口径用**私有已提交**（ADR-292），`footprint` 只作参考。
- 键入类验收必须在**本机图形会话**，不能 SSH。
- `launchctl setenv` 传不进 launchd 拉起的宿主，诊断开关用文件 `~/Library/Application Support/Lampyris/hud-diag`。

**air 验收命令（本机终端）**：`make macos-auto-acceptance`、`./tools/macos-probe/quality-samples.sh`、`./tools/macos-probe/memory-gate.sh`（会重启宿主，需授权）、`MINUTES=5 ./tools/macos-probe/soak-session.sh`。

## 5. 边界

- 核心零网络/零遥测；配置只经 `ime-config`；不手改 `config.toml`、不写 UserDefaults、不动 HIToolbox，不清用户数据。
- **未经授权不换包、不切输入源、不重启宿主、不创建 tag/Release**。装包/卸载/重启都要单独授权，且先读 `.agents/skills/iterate-macos-ime/SKILL.md` 记录 ZIP SHA + 执行 SHA。
- **卸载只允许**：隔离 drill 构建（私有根）、或用户明确授权后对生产位执行；删真实安装前先确认回滚备份存在。
- 改系统工具链（重装 CLT）需用户授权。
- 发键前必须 `guard-focus`（报告189 事故）；`--hid` 面向当前前台应用。
- `show_wubi_learning=true` 在 pro 上是用户有意设置，不要「还原」。
- 只用自建文档与自有会话；失败即停并保留证据。

## 9. 会话日志（最近）

- 2026-11-15 / Claude Code（air）：**快速 UI 回路修复（报告 286）**。`make macos-ui-snapshots` 因
  `CandidateWindow` 新增 `CaretPlacement`/`LearningHints` 依赖而编译失败；补全源码清单，新增
  `test-ui-snapshots.py` 防清单漂移。离线回归 68 文件/337 例 PASS；快照可重新产出（候选 6 / 面板 14 / HUD 6）。
  日常 UI/功能验收优先 `make macos-ui-snapshots` + `make macos-dev`，不必每次换包。
- 2026-11-15 / Claude Code（air）：**PR #314、#315 已合入 main（`7014346`、`7b95ba6`）**。PR #314 = 86 专注 +
  标准变体（240→241 条 root/key，98/新世纪仅留 profile）；PR #315 = D2 字形别名（ADR-359，报告 285）。
  当前 B0 3,000 `full` 2,614（87.1%）/ `partial` 232 / `unknown` 154；1,000 `full` 928。CI 全绿后均为 merge commit。
- 2026-11-15 / Claude Code（air）：**D2 字形别名归一化（ADR-359，报告 285）**。逐条复查标准 v1 的
  73 条 `positionMismatch`，把 D2 用假名/注音符号代替部件的同形写法归一化（`リ→刂`、`ㄗ→卩`、`ク→夕`），
  另补 `彑`（X）到标准字根清单、`ノ` 作撇笔画。B0 1,000 字 `full` 916→**928**、`partial` 80→**68**；
  3,000 字 `full` 2,578→**2,614**、`partial` 268→**232**；运行时同，**零降级**（36 条 partial→full）。
  剩余 partial 多为 D2 视觉拆法（如 `交` 记 `亠八乂`，86 取 `六乂`），需 canonical 根序数据，不猜。
- 2026-11-15 / Claude Code（air）：**PR #313 已合入 main（343ce01）**。统一拆字标准 v1 落地；
  B0 3,000 字 `full` 2,578 / `partial` 268 / `unknown` 154；1,000 字 `full` 916。
  98/新世纪复用校验逻辑，但需各自的字根/码表 profile。
- 2026-11-15 / Claude Code（air）：**统一拆字标准 v1（ADR-358，报告 284）**。新增
  `docs/standards/wubi-decomposition.md` 和 237 条标准字根清单；B0 schema v7 增加
  `scheme`/`standardVersion`，`full` 必须无标准字根/键位不符。3,000 字 `full` 2,554、
  `partial` 292、`unknown` 154；1,000 字 `full` 910。98/新世纪复用校验逻辑，但需各自字根/码表数据。
- 2026-11-14 / Claude Code（air）：**PR #312 已合入 main（a4f6a9c）**。cjk-decomp 覆盖 64→83 条；
  B0 3,000 字 `full` 2,759、`unknown` 154；运行时 `full` 2,602。新增 `--all-codes` 为全量 27,823 做准备。
- 2026-11-14 / Claude Code（air）：**Academia Sinica 数据获取受阻**。官方 `cdp.sinica.edu.tw` 仍返回
  Access Restricted/证书过期；Wayback 暂离线且无 `cdphanzi.mdb` 快照；未找到公开镜像。
  `cjkvi-ids` 的 `ids-cdp.txt`（GPLv2，CDP PUA IDS）只增加约 1,077 个键位匹配候选，不足以覆盖 27,823。
  需要用户提供 CDP 数据/镜像，或等官方站点恢复；在此之前不能宣称全量 canonical 拆字完成。
- 2026-11-14 / Claude Code（air）：**PR #311 已合入 main（2887c87）**。D24 cjk-decomp（Apache-2.0）
  覆盖拆字 64 条；B0 3,000 字 `full` 2,740、`unknown` 172；运行时 `full` 2,583。无付费数据。
- 2026-11-14 / Claude Code（air）：**PR #310 已合入 main（8d8fb27）**。覆盖扩量后 B0 1,000 字
  `full` 955、3,000 字 2,676、运行时 2,519；剩余 220 unknown 多为繁体/生僻字，未用 D3 批量补数。
- 2026-11-14 / Claude Code（air）：**PR #309 已合入 main（6aa8a91）**。N2/N3/N4 数据地基 CI 全绿后合并；
  正式发版产物未变，下一次构建才会带上 schema v6 数据。
- 2026-11-14 / Claude Code（air）：**D24 cjk-decomp 覆盖（ADR-357，报告 283）**。引入 Apache-2.0 的
  cjk-decomp，树切分 + 码位键位/IDS 校验，生成 64 条覆盖拆字；B0 3,000 字 `full` 2,676→2,759、
  `unknown` 220→154；运行时 `full` 2,519→2,602。未使用付费数据。
- 2026-11-14 / Claude Code（air）：**N1-d 覆盖扩量（ADR-356，报告 282）**。新增 62 条 `*` 兜底、3 条 D2 BMP PUA、
  34 条逐字语境；B0 1,000 字 `full` 927→955、`partial` 65→37；3,000 字 `full` 2,588→2,676；运行时 `full` 2,462→2,519。
  剩余 220 unknown 多为繁体/生僻字；未用 D3 作来源批量补数。
- 2026-11-14 / Claude Code（air）：**N2/N3/N4 数据地基完成（ADR-355，报告 281）**。D18 新增 56 个 B0
  成字字根的真实笔顺（Unihan kTotalStrokes 校验笔数）与 8 个 D2 漏拆字的完整拆字；B0 schema 升 v6，
  新增 `strokesSource`/`strokesKind`/`structure`/`structureSource`/`structureConflict`。结果：1,000 字
  `full` 919→927、`partial` 73→65；3,000 字 `full` 2,580→2,588；运行时 `full` 2,454→2,462；结构覆盖 2,766 条
  （识别码 1,525 / IDS 1,241，冲突 146）。仍未达第二阶段 ≥98% 覆盖门槛。
- 2026-11-14 / Claude Code（air）：**验收自闭环收敛**。按用户要求移除 Safari/Chrome/Xcode/VS Code/微信
  的自动化验收、探针、fixture 与 `client-matrix`；`acceptance-auto` 只保留热键/上屏 + 性能/网络，
  `cleanup-windows.sh` 只清 TextEdit/imetype，preflight 只查 TextEdit 多实例；正式验收 APPLICATIONS
  收敛为 TextEdit/Terminal。新增 `installed-probe-guards.py` 给 Terminal 共用保护；
  `test-acceptance-portability.py` 改为“第三方客户端不得回流”门禁（ADR-354）。目标：本地迭代不再依赖第三方安装。
  离线回归 67 文件/348 例 → **64 文件/323 例**；正式发版六客户端人工取证标准不变。
- 2026-11-14 / Claude Code（air）：**N1-d 更正并接入（ADR-353，报告 280）**。初版清单误把 D3 BMP PUA
  当成 D2 源（266/156/110 不正确）；更正为 D2 补充区后，3,000 字可定位 79 个 PUA，按 `(PUA, 键位)`
  核验 66 条（`verified 58 / partial 8 / unresolved 13`）。`build_b0.py` 新增 `--pua-supplementary`；
  B0 1,000 字 `full` 735→919、`partial` 257→73；运行时 3,000 字 `full` 1,904→2,454、`partial` 876→326；
  `componentsSource` 仅 D1/D2（D3 不再作来源）。产物无 PUA，未解决项保持 `？:键`。
- 2026-11-14 / Claude Code（air）：N1-d 初版清单（**后被上一条更正**）：3,000 字 partial 实际用到
  266 个 PUA（数据源误用 D3）；生成 `pua-inventory.tsv` 与 `tools/pua_inventory.py`，
  `test-pua-inventory.py` 守「不猜填」。
- 2026-11-14 / Claude Code（air）：**P1-2/U3-4 字根字形来源调研完成（ADR-353，报告 279），未下载数据**。
  结论：没有许可干净的五笔字根字体；N1 主候选 Academia Sinica「漢字構形資料庫」（GPL-3/GFDL/CC BY-SA 2.5 TW，
  1,324 字根/4,766 部件）+ cjk-decomp（MIT/Apache-2.0）与 cjkvi-ids/CHISE 交叉校验；剩余 251 个 PUA 字形
  需对齐或自绘。官方站点证书过期，需离线核对；**待用户批准 N1-a 开工**。
- 2026-11-14 / Claude Code（air）：**U3-1 整句模型关闭（ADR-352，报告 277/278），原型未合入**。
  下载中文 Wikipedia 2026-11-01 分片 1（SHA1 `a7094e62…`），生成 20 万条 bigram（2.7 MB，常驻 +4.8 MiB，
  p95 +0.03 ms）；在 `ime-pinyin` 里加临时词格 Viterbi 后，自编 PassageBank 100 句首选仍为 **27/100 与基线相同**，
  扩展词表也相同。主因是百科缺少口语句末虚词、错误主要来自未登录词/分词覆盖。工作区已还原、原 dump 已删除；
  是否继续取决于是否先补口语语料或扩词表。
- 2026-11-14 / Claude Code（air）：**宿主内完整引导真机目视完成（ADR-351，报告 276）**。PR #295–#298 合并（`main` = `b8dd20f`），
  最终候选 ZIP `a9bc1227…`、执行 `bda6f090…` 装 air。菜单入口/翻页/首次自动弹窗 PASS；首次触发从激活回调改到
  首个按键（`handle` + `inputText` 两条路径）。标记恢复原 SHA、`TextEdit`/`imetype`/`keytopid`/`caffeinate` 无残留、
  宿主窗口 0、输入源已选回；真实 `practice.tsv` 未变，词库因验收键入 1862→1904 行。
- 2026-11-14 / Claude Code（air）：**U2-5 分阶段解锁真机目视完成（ADR-350，报告 275）**。PR #293 合并（`main` = `13ec97b`），
  候选 ZIP `17ac399a…`、执行 `739bdf7a…` 装 air。私有根新进度仅字根可点；种入 30 条字根全对 → 一级简码启用；
  再 25 条一级简码全对 → 二级简码启用；关闭 `practice.staged_unlock` 后六段全开。真实 `practice.tsv` `2512f4…` 未变，
  私有根已删除、`LAMPYRIS_SUPPORT_DIR` 已还原。测试期间发现离屏渲染早于 `ime_config_init`，已加测试覆盖开关修正。
- 2026-11-14 / Claude Code（air）：**U3-5 符号 / emoji 真机复验完成（ADR-349，报告 274）**。PR #289–#291 合并（`main` = `d779186`），
  最终候选 ZIP `02fec3fe…`、执行 `a184fc1e…` 装 air。⌥S 面板：`xiao`→205、`heart`→159、`grinning`→10，插入 `≤`/`♥`/`😀`；
  反引号 `` `11 ``→`，`、`` `42 ``→`→`、`` `7 `` 开面板；零外联 0 socket；核心样本 29/30（失焦项 TextEdit AppleScript 挂起 BLOCKED）。
  真实数据根测试使词库 1838→1862 行、config 恢复取值后重写（SHA 变化、值不变）；备份 `updates/install-backup-20261114T015521Z/`。
- 2026-11-13 / Claude Code（air）：**U3-5 符号 / emoji 代码与数据完成（ADR-349，报告 274）**。
  ⌥S 面板（分类 + 中英文搜索 + 表格）+ 反引号候选前缀（7 类 → 分页；emoji 跳面板）；`fh` 因是「直」的码且有 304 条前缀被弃用。
  数据：项目自编 277 符号 + Unicode 16.0/CLDR-47 派生 3,781 emoji（缺中文名 0）；Unicode License V3。
  `make verify`（504 产物）、离线 65 文件/342 例、`build.sh --strict`、预览冒烟全绿；**待授权换包做真机插入与零外联复验。**
- 2026-11-13 / Claude Code（air）：**U2-3 扩展词库完成并真机复验（ADR-348，报告 273）**。PR #287 合并（`main` = `a725fff`）→
  CI 验收包 ZIP `1b0ab3c7…`、执行 `01f32c51…` 装 air。`dict.extended` 开：`ybkl` → 离别；关：恢复原样字母。
  扩展档 3 轮稳态存活堆 **48.0–48.2 MiB**（`LIMIT_MB=64` PASS），核心档 **20.8–21.0 MiB**（`LIMIT_MB=24` PASS）；
  真实 config/词库/练习 SHA 未变。全量 341k 拼音仍不随包（ADR-031）。
- 2026-11-13 / Claude Code（air）：**1.3.0 发布后文档对账 + pro 核验**。用户手动把 pro 升到 1.3.0/43
  （执行 `9cb738c9…`，config `b8c7a351…` 未变、词库 962→963）并确认实键入正常；更新 `docs/待办与积压.md`（版本抬头、P0/P1-U 完成项、下一版套餐）、
  `ROADMAP.md`（1.3.0 发布与 pro 升级勾选）、`docs/README.md`；文章跟打任务卡归档到 `docs/archive/tasks/`。
  PR #286 已合并（`main` = `f4fbea0`），`dev` 已快进同步。
- 2026-11-13 / Claude Code（air）：**1.3.0 发布完成（报告 272）**。tag `v1.3.0`（`d9ca1b4`）→ Release run `43413483494` success；
  ZIP `66b01c64…`、源码 `9f068f18…`、DMG `fef49e86…`（公证）、更新程序 `28e4a327…` 1.3.0、appcast `43`；
  Pages `43414150031` → 站点回读 `v1.3.0 · 构建 43`。发版产物 `9cb738c9…` 与早先候选 SHA 不同，已重新装机并重跑 30/30 样本、性能/内存 PASS。
  期间 Apple 公证因协议过期 403，用户签署后恢复。air 已装发版产物；pro 由用户升级。
- 2026-11-13 / Claude Code（air）：**人工验收全部 PASS**。用户口述 IT-22 A 档 10/10、可选 Chrome、1.3.0 新增行为 N1–N5 全通过（报告 271）；
  剩余只有 DMG 完成页目视与 tag/Release/站点（需单独授权）。
- 2026-11-13 / Claude Code（air）：**1.3.0/build 43 装机复验 30/30 PASS（报告 270）**。build 41→42→43 修掉三个真实缺陷：
  私有根相对路径被忽略（宿主仍用真实数据）、练习/薄弱字路径不跟随私有根、切模式后未重建引擎（双拼/薄弱字连锁失败）。
  build 43：30 条隔离样本全 PASS，真实 config `3aea2bca…` / practice `2512f4…` 前后不变；性能 p95 6.28ms、0 外联；
  内存存活堆 19.5–19.6 MiB PASS。用户词库因早期隔离失效与门禁键入学习 1784→1838 行，mode 已恢复 `wubi`。
  剩余：IT-22 A 档人工走查、DMG 完成页、tag/Release/站点（需授权）。
- 2026-11-13 / Claude Code（air）：**PR #278 合并 + 1.3.0/build 41 候选**。`main` = `938eeb0`；
  run `43362795540` success：ZIP `1eb480e3…`、源码 `a5887a10…`、执行 `aa040adc…`，universal、公证通过；air 已覆盖安装并核对数据未变。
- 2026-11-13 / Claude Code（air）：**1.3.0/build 41 装机复验：27/30 PASS，抓到 1 个真实隔离缺陷**。双拼、薄弱字、失焦三项 FAIL：
  双拼手动复跑 PASS（样本配置写入太快）；失焦疑似抖动；**薄弱字/练习进度路径没有跟随 `LAMPYRIS_SUPPORT_DIR`**，私有根复验仍写真实目录，
  导致样本判定失败且用户词库 `pinyin zhuang 装` 计数 +1。已修 `PracticeProgress.defaultURL` / `WeakChars.defaultURL`，
  `quality-samples.sh` 改为停全部宿主、逐进程校验私有根、配置写入后加延迟；**build 43 待出包重装**。
- 2026-11-13 / Claude Code（air）：**批次 C + 1.3.0 版本号（报告 269，PR #278）**。练习「文章跟打」：100 条自编短句、
  独立窗口、逐字判定、会话内统计（ADR-347）；`Cargo.toml` 升 1.3.0（build 41 → 42），ROADMAP 发布列车与 `docs/releases/1.3.0.md` 草稿同步。
  CI 首次红是 `wubi.auto_phrase` 未进设置页「五笔与拼音」分组、离屏 UI 探针的固定 Swift 源列表缺 PassageBank/PassageWindow，
  已修复并全绿本地。
- 2026-11-13 / Claude Code（air）：**批次 B 完成（ADR-341…346，报告 268）**。五笔连续单字造词（`wubi.auto_phrase` 默认关）、
  日期/时间/星期候选（`riqi`/`shijian`/`xingqi`，Dynamic 来源不学习）、首次启用上手提示（`onboarding-done`）、
  练习进阶建议（30 字 + 90%）、三级简码入表（D17-ter 3,362 条，核心表 714,176 B）。高频字拆解给出受阻证据：
  876 条 partial 里 738 条缺 D2 补充区私有字根身份，无许可来源，未猜填。边界 ADR-346 列出清理候选。全部未换包。
- 2026-11-13 / Claude Code（air）：**批次 A 合并（报告 267，PR #277 / `6a9c587`）**。安装器三条新分支回归、离线回归共享
  Swift 模块缓存（并发 6，62 文件/332 例 35s）、`perf-session` 失焦不再崩、真机样本默认私有数据根（ADR-340）、
  CI `runner` 可选、以词定字跟随高亮（ADR-339，新增 `ime_session_set_highlight`）。`make verify` 与 `build.sh --strict` 全绿。
- 2026-11-13 / Claude Code（air）：**ADR-337 候选 `2610d1f` 装机复验全 PASS（报告 266）**。CI 打包前两次排队 15 分钟未分到 macOS arm64 运行机被取消（GitHub 容量），第 3 次成功；ZIP `a4b56509…`、执行 `975a4b04…`，装机后用户数据不变。`12:30`/`？`/`：` 真机正确；五笔码提示在混输下真机出现（148×36 浮层，外接屏），**用户当前 `mode=wubi`（21:26 本地自行切换），五笔/拼音模式按设计不提示**。26/26 样本 PASS；内存 ADR-338 口径稳态存活堆 21.0–21.2 MiB PASS。已装 `2610d1f`，`mode` 已恢复 `wubi`。剩余：升版本号 1.3.0 → 再出包复跑 → IT-22 A 档 → DMG 完成页 → tag/Release（需授权）。
- 2026-11-13 / Claude Code（air）：**内存口径已定（ADR-338）**。`memory-gate.sh` 改以稳态存活堆 `heap_live_mb` 判定，门槛 24 MiB，不再按学习区分档；「私有已提交」与 footprint 只作参考；新增 `ANALYZE_ONLY=1` 复核旧快照。对报告 265 的 5 组快照（23 轮）重判全部 PASS（20.1–21.2 MiB）。取代 ADR-263/292/312 的口径与门槛。**发版阻塞里的内存一项已解除**；剩余：PR #274（ADR-337）未合并、其两项修复未实机确认，升版本号，DMG 完成页。本条与上一条文档提交都在本地 `dev`，等 #274 合并后再推。
- 2026-11-13 / Claude Code（air）：**重启后内存重测（报告 265 §4.3）：无回归，门禁口径失效**。swap 0、负载 1–4，新旧包各 5 轮：稳态「私有已提交」新 37.4 / 37.3、旧（1.2.1 发布版）37.5 / 37.3，两者都 5 轮全超 34 MiB；存活堆都是 20.1–20.2 MiB。该口径随内存压力反向变化（swap 满时 31–34，swap 空时 35–37.6），量的是系统状态。**待用户裁定**：把判定口径换成 `heap_live_mb`（需 ADR）。已装回新包 `3e428b7`。PR #274（ADR-337）CI 全绿（首跑 `macos` 是没分到运行机被取消，重跑通过），**未合并、等用户授权**；本条文档提交暂留本地，等 #274 合并后再推，免得重跑 CI。
- 2026-11-12 / Claude Code（air）：**用户实机反馈两处缺陷 → ADR-337**。① `12:30` 得到 `12；30`：带 Shift 的标点到核心时是未加 Shift 的字符 → 宿主改用 `typedScalar`（按键码 + Shift 重算）。② 拼音上屏后五笔码提示不出现：探针复现属实（宿主无浮层变化、诊断日志无取光标记录），进程内重放逻辑通过，**根因未定位**；改为上屏前候选快照并给提示路径每个分支加诊断日志。用户确认练习「字根」「词组」题型正常。四道检查全绿，新增 3 条真机样本（共 26 条）。**两项修复都未在真机确认**：等本批 PR 合并出包后装机，先看 `lampyris-hud-diag.log` 里的 `hint skip=/show=`。内存门槛按用户决定：重启电脑后重测再定。DMG 完成页仍未验证。
- 2026-11-12 / Claude Code（air）：**首键 +4.6 MiB 归因完成（报告 265 §4.2），不改产品代码**。读 `vmmap` 的 MALLOC ZONE 存活分配：首键时点只有两种状态——5.2 MiB（无会话存活，数据已随 `Weak` 缓存释放）或约 19 MiB（有会话存活）；新包 8 轮里 3 轮撞上后者、旧包 5 轮 0 轮（偶然概率约 20%），无会话的轮次新旧完全相同。稳态存活堆新包 +0.5 MiB（21.0 vs 20.5）。`memory-gate.sh` 新增参考字段 `heap_live_mb` / `heap_allocations`。副产结论：冷首键 ~30 ms 很可能来自「最后一个会话释放后重新读盘解析」，与本批无关，是否常驻数据需 ADR。PR #273 待合并；已装仍是 `3e428b7`。
- 2026-11-12 / Claude Code（air）：**内存新旧包 A/B（报告 265 §4.1）**。新→旧（1.2.1 发布版）→新，各经 `install.sh` 覆盖安装。稳态私有中位数：`six-words` 新 31.8 / 旧 33.0，`idle-8s` 新 31.6 / 旧 31.0 → **稳态无回归**；但学习区开启时两者都贴 34 MiB 门槛（旧包最高 33.7，新包 11 个样本 2 个超限，同包三次运行 FAIL/PASS/FAIL）。**新发现：首键时点新包 +4.6 MiB（27.8 vs 23.2），未归因。** 结束状态：已装新包 `f38e4e1a…`（`3e428b7`）、输入源萤火虫、config 未变；`updates/` 多出两份 A/B 产生的备份（`…T105406Z`、`…T110001Z`）未删。待用户裁定：门槛是否重测调整、首键内存是否发版前归因。
- 2026-11-12 / Claude Code（air）：**报告 265：延迟 PASS、内存门禁 FAIL（未定性）**。PR #272 已合并，`dev`=`main`，无开放 PR、无多余分支。补 `;` 选第二候选真机样本（PASS；`keytopid` 加命名键 `semicolon`），`12:30` 与五笔码浮层探针测不了。`perf-session`：稳态 p95 7.33 ms / 0 外联（2 轮失焦，汇总脚本崩溃，按原始数据重算）。`memory-gate`：学习区开、门槛 34 MiB，稳态私有 31.0–34.6 MiB，1/6 样本超限；当时 load 12–41、swap 10.2/11.3 GB。**下一步：对新旧包做同条件内存 A/B（旧包在 `updates/install-backup-20261112T060612Z/`），结论出来前不升版本号、不发版。** 已装仍是 `3e428b7`，输入源已选回萤火虫。
- 2026-11-12 / Claude Code（air）：**P1-U 真机键入复验 22/22 PASS（报告 264 §3.1）**。用户为代理会话的责任进程（`~/Library/Application Support/Claude/claude-code/<版本>/…/claude.app`，不是 `/Applications/Claude.app`）授了辅助功能权限后复跑 `quality-samples.sh`：原 13 条 + ADR-325…336 的 9 条全过。跑后 `config.toml` 取值还原但多出两行显式默认值（SHA `88651507…`→`52af2b90…`）；词库 1713→1715 行（含样本副作用 `pinyin zhuang 装 1`）。**未验证**：`;`/`12:30`、五笔码浮层、练习新题型、设置页新开关、DMG 完成页（需人工目视）；内存门禁与延迟未复测。PR #272（报告与探针工具）待合并。
- 2026-11-12 / Claude Code（air）：**P1-U 候选 `3e428b7` 装机 PASS、真机键入复验 BLOCKED（报告 264）**。PR #271 已合并；从 CI 验收包（run `43163118879`，ZIP `8e7aece7…`，Notarized）覆盖安装：切 ABC → 停宿主 → `install.sh`，装后执行 `f38e4e1a…` = 包内，config/词库/练习进度 SHA 不变，宿主跑新二进制。**键入复验一条都没跑成**：本会话进程 `AXIsProcessTrusted=false`，合成按键被系统丢弃。已给 `quality-samples.sh` 加 9 条 ADR-325…336 样本，并让 preflight 能识别「无事件投递权限」（`keytopid --check-access`）。**下一步：用户在已授权终端跑报告 264 §4 的一条命令，再按 §5 目视 5 类项**；通过后才谈升版本号与发版。
- 2026-11-12 / Claude Code（air）：**P1-U 第三批（ADR-333…336）+ 前两档已合入 main**。PR [#269](https://github.com/EasyIndie/EasyInputMethod/pull/269)（第一档）与 [#270](https://github.com/EasyIndie/EasyInputMethod/pull/270)（第二档）均已用合并提交并入（`c882c06`、`2f8ee06`），**下面一条日志里「第二档未推送」已过时**。第三批：按应用记住中英状态（仅内存）、练习「词组」题型（随包码表前 800 词）、薄弱字清单（`practice.collect_weak_chars` 默认关，`weak-chars.tsv`）、小鹤双拼（`pinyin.scheme`，仅拼音模式；425 个音节 419 个可达）。Schema 27→30。四道检查全绿、评测 98.2%/86.4% 与基线一致。**三批改动全部未装机**，复验清单见 `docs/待办与积压.md` P1-U；P1-U 剩余 8 项都需用户先定口径或授权取数据（同处有表）。仓库已开启 auto-merge。
- 2026-11-12 / Claude Code（air）：**P1-U 第二档可直接做的部分完成（ADR-330…332）**。U2-1 拼音分段选词（`Candidate.consumed`、`Session::preedit`、`IME_SELECT_PARTIAL`，整句学成用户拼音词）；U2-4 混输下拼音上屏后提示五笔码（`candidate.hint_wubi_code`，Schema 26→27）；U2-5 练习新增「字根」题型并排最前。第一档 PR [#269](https://github.com/EasyIndie/EasyInputMethod/pull/269) 已开（首跑 `macos` 红：预览冒烟写死设置项 23 → `7e37dba` 修）。**第二档提交只在本地 `dev`，未推送**——同一个 `dev → main` 只能有一个 PR，要等 #269 合并后再推并开第二档 PR。四道检查全绿（`make verify`、离线 62/328、预览冒烟、`build.sh --strict`），**均未装机**。教训：离线回归不含预览冒烟与宿主编译，改设置项数量或 `InputController.swift` 后必须另跑这两项。剩余 U2-2 五笔造词 / U2-3 扩展词库 / U2-5 分阶段与跟打都需用户先定口径。
- 2026-11-12 / Claude Code（air）：**P1-U 第一档全部完成（ADR-326…329）**。U1-2 拼音没打完给补全（`nih`→你好，补全不拦五笔自动上屏，评测与基线一致 98.2%/86.4%）；U1-3 `;`/`'` 选二三候选、`[`/`]` 以词定字（两个开关默认开，Schema 24→26）；U1-5 练习按错题加权出题（文件格式不变）；U1-4 安装完成页加上手提示（窗口高 300→340，**版式未目视确认**）。`dev` 领先 `main` 7 个提交（`df2019c`…），`make verify` PASS、离线 62 文件 / 328 例 PASS。**未推送、未开 PR、未换包；六项行为都待装机实键复验**（清单见 `docs/待办与积压.md` P1-U 末尾）。下一步：第二档 U2-1 → U2-4 → U2-2。
- 2026-11-12 / Claude Code（air）：**U1-1 数字后标点（ADR-325）代码完成**。组合外数字后紧跟的 `.` / `:` 保持半角（`3.14`、`12:30`），新增 `input.digit_punctuation`（默认开，Schema 23→24）；核心单测覆盖开/关、全角、标记消耗、选词数字。`make verify` PASS、离线 62 文件 / 328 例 PASS。**未提交、未换包；装机实键待复验。** 已知限制：数字后用方向键/鼠标移光标不消耗标记。
- 2026-11-12 / Claude Code（air）：**「学·练·用一站式」差距分析 + ADR-324（已采纳）**。只读实测（`ime-cli` + 打包同源码表）：不完整拼音无候选、长拼音仅 1 条且不能分段选、打包词量各 2 万、混输 `wo` 的「我」在第 6 位、`.` 无数字上下文（代码推断未实键）、练习纯随机出题、「是」拆解为 partial。用户批准五条：定位扩为核心输入 + 本地学练闭环、「打字统计」边界、拼音升为可主用、可选资源不动默认门禁、仅约束 macOS。积压新增 P1-U 15 项；AGENTS §1/§3/§11、README、技术方案定位句同步。**仅文档，未改代码、未换包、未提交。**
- 2026-11-09 / pi（air）：**1.2.1 发布完成（报告 263）**。P0 三项（安装器旧宿主/输入源、练习页 VoiceOver、回归并发）、零引用代码与资源清理、文档状态标注一并入 `168115e`；期间 `main` 两次 CI 红灯查为 `install-action` 下载 `cargo-deny` 资产 504，改自建 `scripts/install-cargo-deny.sh`（重试 + crates.io 回退）。`git tag -s v1.2.1` → Release `42583547089` success，ZIP `102f4928…` 与验收包逐字节一致、DMG `a6f4bdbd…` 公证、更新程序 1.2.1、appcast `40`；air 用发布包覆盖安装（执行 `3eeeb0aa…`，安装器回读「已注册到输入源」，无需重加输入源）；Pages `v1.2.1 · 构建 40`。**pro 由用户自行升级。**
- 2026-11-09 / pi（air）：**1.2.0 发布完成**。`git tag -s v1.2.0 31fdbcd`（SSH 验签通过）→ 首次 Release 失败于"checkout 把 tag 建成轻量引用"，补 `git fetch --force` 后 `workflow_dispatch` 重跑成功。回读：ZIP `64eeb90f…`（与候选逐字节一致）、源码 `3dc6f717…`、DMG `ffa1a65c…`（staple+spctl Notarized）、更新程序 `332d98b1…`（1.2.0 已公证）、appcast `sparkle:version=39`；包内执行 `ef25e92b…` = 已装机版本。随后完成 Pages 部署（站点回读 `v1.2.0 · 构建 39`）与 pro 升级（1.1.0/38 → 1.2.0/39，验签通过、config 与 962 行词库未变、旧包已备份、宿主重启）。**1.2.0 发布闭环完成。**
- 2026-11-09 / pi（air）：**1.2.0 候选通过验收 + 发版材料**。候选 `31fdbcd`（执行 `ef25e92b…`）全绿（`make verify` 232 产物零网络、离线 62 文件 / 328 例、CI 四项）；用户确认练习页四题型/四位输入格/键位点亮与位次/口诀/工具栏/亮暗外观均可。写 `docs/releases/1.2.0.md`（候选身份、行为变更=二级简码 598 条、学习区与练习、键位图与口诀、工程项、已知限制），ROADMAP/HANDOFF 对账。**等待用户授权 tag/Release/Pages/pro 升级**。
- 2026-11-06 / pi（air）：**1.2.0（B4+B5）候选装机（报告 259）**。PR #232 → CI 包（`exec 28e24d26…`）装 air；稳态 p95 **5.80 ms**（三段 5.12–5.97）、冷首键 28.86/33.39、0 外联、memory-gate 私有 **28.5–28.8 MiB**（限 30）PASS。待用户走查：⌥K 练习窗口（A/C 两种题型）、⌥L 学习区默认关、practice.tsv 生成与重置。
- 2026-11-06 / pi（air）：**1.2.0/build 39 装机 + 首轮体验数据（报告 254）**。PR #227 合并 → CI 验收包 → 装 air：版本/执行 SHA `b152a001…`/公证全部核对，config 与 1225 行词库未变。评测 ALL 命中 98.2%/首选 86.4%（jianma2 100%/100%）；三段延迟稳态 p95 6.7–8.3 ms；**冷首键 27–40 ms，比 1.1.0 的 16–26 ms 高**（待查是否学习区布局所致）；soak 3 分钟 17 轮 0 外联、footprint 38.5 MiB（比 1.1.0 高约 5 MiB，待单独归因）。
- 2026-11-06 / pi（air）：**B3 学习区实现（报告 253）**。`WubiLearningView` 改两行布局（完整码+简码 / 字根格+识别码两行），候选窗零改动；新增 `LearningHints`（读 `B0-runtime.tsv`，缺失退回 D14）；词组按输入码位置映射到字（KWWL → 中K 华W 人W 国L）。`wubi-learning.swift` 扩到可注入资源并生成亮/暗实拍；离线回归全绿。
- 2026-11-06 / pi（air）：**B2 数据地基（报告 252 / ADR-311）**。B0 扩到 3,000 字并预渲染成 `B0-runtime.tsv`（287,310 B ≈ 96 B/字，预算 512 KiB 反而有余量；B0.json 同规模是 1.62 MiB），登记 derived `b0-runtime`，新增 `test-b0-runtime.py` 守体积/格式/无 PUA/消费契约。ADR-311 定装载方式（bundle 内只读文件、宿主查表、Rust 不参与）。
- 2026-11-06 / pi（air）：**1.2.0 B1 批完成（报告 251）**。D1 签名 tag 改 SSH key（白名单 `packaging/git-allowed-signers`，本地已验签）；D2 CI 取 D2 拆字数据 + D17 简码表入库，B0 独立重算不再 skip；D5 perf/soak 绝对硬顶改 vmmap footprint；D6 站点改占位符 + `tools/stamp-site.py` + Pages 盖章；D4 延迟统计加 long-code/paging 两段；E2 soak 30 分钟档。未换包、未改输入行为；离线 61 文件 / 323 例 PASS。
- 2026-11-06 / pi（air）：**1.2.0 迭代计划（`docs/archive/迭代计划-1.2.0.md`）**。按"除平台扩张外全部收口"排成 6 批：B1 工程收口 → B2 数据地基 → B3 L3 提示 → B4 L4 练习 → B5 质量项（有证据才做）→ B6 数据扩张；只换一次包。原则：低风险先行、依赖链不打断、无证据的项明确关闭并写触发条件。可立即开始 B1 与 C1（互不阻塞）。
- 2026-11-06 / pi（air）：**下一版积压梳理（`docs/待办与积压.md`）**。把 ROADMAP 未勾项、ADR 待定项、报告遗留与已知限制收成 A–G 七类，每项给证据/成本/依赖/授权；给出 1.2.0 三套套餐（A 工程收口+教学地基 / B 质量与门禁最小版 / C 平台扩张），推荐 A。需要用户拍三件事：套餐、签名 tag 是否启用、Windows spike 是否启动。
- 2026-11-06 / pi（air）：**1.1.0 闭环 + air 输入源故障收尾**。用户在 pro 确认候选/切源正常；air 报「萤火虫不能用」经查是**被移出已启用输入源**（包、宿主、签名均健康），用户重新添加后恢复。把排查命令与「TIS 后台启用不持久化」写进 `docs/故障恢复.md` §4.1，HANDOFF 同步。
- 2026-11-06 / pi（air）：**1.1.0 发布收口**。HANDOFF 发布列车改为「1.1.0 已发布 → 下一站 1.2.0」；ROADMAP 三条发布任务全部勾掉（自用豁免、tag/Release、站点、pro 升级），新增「1.2.0 候选」与「pro 本机实键入确认」。当前：main `730d894`、最新 tag `v1.1.0`、站点 `v1.1.0 · 构建 38`、air/pro 同包。
- 2026-11-06 / pi（air）：**1.1.0 站点 + pro 升级（报告 250）**。站点版本行是硬编码，先改 `site/index.html` 再经 PR #226 合入 main（CI 前两次红灯：预览冒烟 `zz` 撞五笔通配、B0 测试在 CI 缺下载数据——都不是产品回归，已修并留报告 249/补 skip 逻辑），dispatch Pages 后回读 `v1.1.0 · 构建 38`。pro 经更新程序 1.0.0/34 → 1.1.0/38（执行 `d3c5a2ef…`），config 与 959 行词库未变，更新程序同步升到 1.1.0；`--verify-payload` 独立验签通过。
- 2026-11-06 / pi（air）：**1.1.0 发布（报告 248）**。用户授权 tag → `git tag -a v1.1.0 393318c` 推送，Release run `42225134493` success；回读：ZIP `448d3170…` 逐字节一致、DMG staple+spctl 通过、appcast `sparkle:version=38`、更新程序 1.1.0 已公证、包内执行 `d3c5a2ef…`/universal/38 全对。站点未部署（等授权），pro 仍 1.0.0。
- 2026-11-06 / pi（air）：**用户豁免 1.1.0 的「自用 3 天」**。豁免事实与替代证据（报告 229 久用、报告 234 人工走查）写进 `docs/releases/1.1.0.md` §3 与报告 247 §2；**尚未执行 tag/Release/Pages/换包**，等下一步授权。
- 2026-11-06 / pi（air）：**1.1.0 发布预检（报告 247）**。候选 `393318c` 全项核对：版本/构建号、CI 双绿、ZIP 与本地逐字节一致、站点仍 v1.0.2·37、无 v1.1.0 tag、`release.yml` 会产出 ZIP/DMG/更新程序/appcast。**缺口：自用 3 天 0/3 + 四处授权**；发布稿两处「待补」确认就是 Release 产物，不是缺陷。未执行任何 tag/Release/Pages/换包动作。
- 2026-11-06 / pi（air）：**corpus 第二阶段需求清单（`docs/结构库第二阶段需求.md`）**。把缺口拆成 N1 字根字形身份库 / N2 笔画笔顺 / N3 结构标注 / N4 完整拆字，写清准入规格、四条已否决路线、四道验收门槛与 M2-1～M2-4；同时算出体积隐患（558 B/字 × 3,000 ≈ 1.6 MiB，超 512 KiB 预算 3 倍），定为第二阶段必做项。ROADMAP/docs 索引/HANDOFF 同步。
- 2026-11-06 / pi（air）：**字体路线调研（报告 246）+ ADR-310**。查出 D3 许可登记错误：上游 NOTICE 明确拆字数据与字体「未附带任何版权声明」；两款候选字体都无许可，且 D3 字体不含 U+F00xx → 路线关闭。D3 降级为构建期 oracle，B0 组件来源改为 D1/D2（full 735），校验与测试加「产物不得出现 D3 来源」防线。
- 2026-11-06 / pi（air）：**B0 schema v5 + D19（报告 245）**。登记 yi-bai/ids（MIT，2 MB 下载不入库），给 `ids`/`idsStructure` 结构参考，并严格条件补占位 23 条（full 714→737、占位 272→249）。查清天花板：IDS 粒度粗，220 条叶数不等；私有区等价类传递法已证伪。校验器/测试/文档全同步。
- 2026-11-06 / pi（air）：**B0 schema v4（报告 244）**。全做报告 242 的 B 类与 D 类：① 成字字根笔画由全码反推（41/42），D14 补 了/也/上；② 查明 D2「每码位一形」，末位私有区=识别码槽、其余=占位字根，合体字组件数↔码长 100% 对齐，识别码 525→622。full 759→714 是有意的（56 条中间含未识别字根不再判 full）。「码驱动搜索」被证明不需要。
- 2026-11-06 / pi（air）：**B0 schema v3（报告 243）**。占位组件 + 码位推键位，产物无 PUA；full 753→759、识别码 514→525、192 条占位（380 个）。查出并修掉 D3 字根按字符解析的缺陷（空格混入组件、BOM/CRLF 未清），校验器新增 4 项拦截，测试补占位契约用例。
- 2026-11-06 / pi（air）：**13% 结构不一致归因（报告 242）**。66 条全部是口径差异（独体字/拆法/包围），且全部满足「组件数+1=码长」，不是错误；处置为五笔权威、IDS 校验、差异归档。同时把 partial 239 条拆成三类：PUA 占位 54（可救）、缺笔画 52（D18）、D2 漏拆 133（码驱动搜索，实测 173/176 组件键序列是码的子序列）。
- 2026-11-06 / pi（air）：**corpus 数据来源调研（未改仓库数据）**。结论：不需要 Arphic 衍生的笔顺图形；结构用 `yi-bai/ids`（MIT）+ Unihan 交叉校验，字根笔画自编 130 条。可行性实测：IDS 覆盖 992/1000、partial 236/238、与识别码结构一致 446/512（87.1%），13% 不一致需先定口径。ADR-309 已追加来源结论，约 1 周工作量。
- 2026-11-06 / pi（air）：**落地方案 A + 立项方案 C（报告 241 / ADR-309）**。B0 消费契约写进 spec §6（full 完整 / partial 必带「拆解待核验」/ unknown 只说缺资料），新增 `tools/b0_query.py` 参考实现与两条校验不变量（unknown 不带组件/识别码、识别码条目组件数=码长-1）；顺手修两处数据问题（`〇` 是占位字形不算笔画、缺拆字时组件不应是自身）。ADR-309 立项自建 corpus（字根字形 + 笔画/笔顺 + 结构标注），验收=高频 3,000 字 ≥98% 可解释。离线 61 文件/315 例全绿。
- 2026-11-06 / pi（air）：**PUA 字根解码（报告 241 / B0 schema v2）**。对齐 6,191 字学出 184 个 PUA→字根映射；但 D3 组件序列不可靠（混识别码/笔画），覆盖率未提升，反而暴露 B0 v1 的 BMP PUA 校验漏洞（18 条）→ v2 修正为 full 754 / partial 238 / unknown 8，并新增 `componentsSource` / `keys` 字段与严格的 PUA 拦截。建议 A 接受 76%（partial 降级表述）之外，另可 B 人工核验高频 partial、C 启动自建 corpus。
- 2026-11-06 / pi（air）：**B0 结构事实库试点落地（报告 240 / ADR-308）**。在 `modules/hanzi-structure/` 写出 schema v1、派生生成器（输入输出显式传参）、1,000 高频字产物（363 KB）、独立复核器与 provenance；覆盖 full 760 / partial 232 / unknown 8，513 条可解释识别码来源。离线回归新增 `test-hanzi-structure-b0.py`。
- 2026-11-06 / pi（air）：**三级简码评估（报告 239）**。新增样本类 `jianma3`（40 条，只打 3 码）与 `tools/eval/simulate-level3.py`；模拟 4,400 条三级简码：首选 75.0%→97.5%，但按键 4.25→4.03、表 +53 KB、582 处撞码（四码字 64% 本就自动上屏）。**结论：暂缓**，改由教学提示解决「少记识别码」；新基线 `tools/eval/baselines/1.2.0-build39.json`（280 条样本）。
- 2026-11-06 / pi（air）：**二级简码落地 + 评测口径修正（报告 238）**。取 D9（rime-wubi）2 码条目做 oracle，发现规则推导与官方表 **429/616（70%）选字不同**，故放弃规则推导，改用公开 86 版表逐条转写 598 条（排除极爽新增 17 码位与 2 条前缀不符项），登记 D17-bis；`jianma2` 首选 32.5%→100%、键 3.58→3.00，`prefix2` 按官方简码优先后 40%（预期）。版本进 1.2.0/build 39（1.1.0 tag 仍在 393318c）。
- 2026-11-06 / pi（air）：**二级简码频度来源对照（报告 237）**。新增 `tools/eval/compare-level2-sources.py`：两种来源各生成一版 2 码行注入临时表跑评测——624 个码位只有 5 个选字不同（全是生僻扩展字），jianma2 首选 93.3%→100%、按键 3.07→3.00；决定采用全码权重（D3），并发现 `cx` 码位没有单字归属（规则推导只能得 624 条）。
- 2026-11-06 / pi（air）：**五笔原理与学练用评估（研究文档）**。梳理 86 取码/识别码/简码/词组规则与 98/新世纪/郑码差异；评估当前实现：规则与识别码正确（GB1 99.98%），但二级简码 625、三级简码 4,400+ 均未入表，且简码行复用全码权重、词频非输入语料；提出以结构事实库为唯一数据源的「学·练·用」L0–L5 规划（禁练习成绩污染排序、禁热路径教学计算）。
- 2026-11-06 / pi（air）：**文档全面梳理（报告 236）**。活文档死链 29→0（`docs/迭代计划.md` 早已不存在却被 8 处引用）；62 张已完成任务卡 `git mv` 到 `docs/archive/tasks/`（69→4 张活跃卡）；`发布说明.md` 归档并改用 `releases/` 索引；新增 `docs/archive/README.md`、`docs/research/README.md`，重写 `docs/README.md`（含 5 条文档卫生规则）；新增 `test-docs-hygiene.py`（索引/死链/任务卡/归档登记）。离线 60 文件/312 例全绿。
- 2026-11-06 / pi（air）：**RC-UI-01 结案（报告 235）**。按用户裁定 A：该卡要求的「模式行右对齐 + 模式切换」已由 ADR-206 换方案落地（系统菜单只投递顶层命令 ⇒ 取消子菜单、恢复单行点击循环 + 自绘右对齐，三选一留在设置页/⌥M），关于与复制诊断经 IT-22 §7 与报告 071/074/217/234 验证；历史过程保留在 ROADMAP 同一行。ROADMAP 未勾项 23 → 22。
- 2026-11-06 / pi（air）：**ROADMAP 对账收口**。把 6 处「已完成但没勾」补齐（最终 RC 人工项、P1-M5/IT-15、I2/I3/I4、IT-25、UI04-05、2026-10-15 的冻结候选两项），MVP 标准抬头改为「已由 v1.0.0 关闭」，新增「当前发布列车：1.1.0」三条任务与 P2 的 D17-bis/冷首键，并写死「发布对账」三步防止复发。未勾项只剩 P2–P6 / TBD-2 / 拆字教学 / 结构库 / RC-UI-01（待裁定）。
- 2026-11-06 / pi（air）：**合并 PR #225**（1.1.0 发布稿 + 报告 234 走查结果 + 只依赖系统自带应用的验收整改）。main = `e43ee55`，`dev` 已快进同步；1.1.0 只剩自用 3 天、tag/Release、pro 升级三件事。
- 2026-11-06 / pi（air）：**人工走查通过（报告 234）**。用户本机跑完 A 档 10 项 + IT-25 四项全 PASS，无 FAIL/BLOCKED；并按用户裁定**验收只依赖系统自带应用**——VS Code / 其它 App（微信）从清单移除，Chrome/Xcode 降为 optional 且缺装 SKIP，Xcode 不再写死 `Xcode-27.0.0.app`；新增 `client-matrix-verdict.py`、`test-acceptance-portability.py` 两个门禁，A 档人工从 12 项降到 10 项。
- 2026-11-06 / pi（air）：**按用户决定，走查通过后再提 PR**。写好人工走查执行单 `docs/reviews/234-1.1.0-walkthrough.md`（A 档 12 项 + IT-25 四项 + 取证命令 + 空结果列），并写明后续：结果回填 → 补结论 → 与 1.1.0 发布稿同一个 PR；两份文档都留在 dev，暂不合并 main。
- 2026-11-06 / pi（air）：**合并 PR #224 + 起草 1.1.0 发布稿**。main `d816953`，dev 已快进同步；`docs/releases/1.1.0.md` 绑定候选身份与 ADR-307 两个延迟数，并把待办（IT-25/IT-22 A 档、3 天自用、tag/Release、pro 升级）列清；`docs/archive/发布说明-0.1.15.md` 标为 0.1.15 历史底稿（此前与实际版本不一致）。
- 2026-11-06 / pi（air）：**延迟长尾归因（报告 233 / ADR-307）**。给 imetype 加逐键归因（key/kind/pos），发现 160 个样本里的慢样本 100% 是每轮首键（14.6–27.1ms），稳态 p95 6.08ms；两组对照排除候选窗，定位为「新输入上下文首次建立」。门禁拆为稳态 p95（6.71ms PASS）+ 冷首键记录（15.88/25.77ms），并更正报告 232 §4 的错误结论（当时用的是排序后数组）。
- 2026-11-06 / pi（air）：**验收流程优化收口 + PR #224**。四份报告（229 真延迟口径 / 230 提效 / 231 自清场 / 232 状态自归位）全部落地；离线 57 文件/300 例、`make verify` 全绿；`acceptance-full（SKIP_MEMORY=1）` 除性能 p95 外全过。PR #224 的 dco 首跑失败 → `--signoff` 重写 + 新增本地 `commit-msg` hook，四门禁现全绿，待授权合并。config 回到原值 `5d4271fb…`（mixed/chinese/half/simplified），验证了 restore 是字节级还原。
- 2026-11-06 / pi（air）：**验收状态自归位（报告 232）**。新增 `ime-state.sh`（snapshot/ensure/restore，走产品热键、不直接改配置），接进 `acceptance-auto` 与 `quality-samples` 的 trap。修掉一次真实连锁失败：上一轮留下 ABC/繁体 → 8 个热键项 + 4 个质量样本全 FAIL，且结束时把用户 config 留在 pinyin/traditional。复跑 quality 13/13 PASS、全量仅剩性能 p95 16.26ms 贴线（唯一红灯）。
- 2026-11-06 / pi（air）：**把「验收自清场」固化成门禁（报告 231 §6）**。`test-probe-cleanup.py` 扫描探针脚本：开窗口却不接 `cleanup-windows.sh`/`trap` 直接 FAIL，并有反向自检防止空转；规则同步进 AGENTS 铁律 11、skill §7、CONTRIBUTING §5、README 清单。上马即抓出 `multi-display.sh` 与 `type-session.sh` 两个缺口并修好。离线 **57 文件/300 例** 全绿。
- 2026-11-06 / pi（air）：**验收跑完自动清场（报告 231）**。新增 `cleanup-windows.sh` + 四个脚本的 `trap`：只回收自己开的窗口（URL/标题/未保存内容签名），浏览器永不退出，`--quit-app` 仅对本轮启动且已无窗口的 App 生效；`client-matrix` 改自建并关闭 TextEdit 文档。实测三次连跑后无残留；`FAST=1 acceptance-auto` PASS（p95 14.48ms）。踩坑记录：`tell application` 会拉起应用、AppleScript 混用 and/or 必须加括号、未保存文档 `path` 是空串而非 missing value。
- 2026-11-06 / pi（air）：**验收提效（报告 230）**。离线回归并行（166s→34s）；删掉必失败的第二套 runner，`macos-local-acceptance` 改成离线回归别名；`acceptance-auto` 加 `FAST=1`（9 分钟→4.7 分钟）；IT-22 65 项压到 12+5 项并加 `T-ITER-22-coverage.md` 映射；新增 `test-acceptance-map.py` 防腐烂；修 `test-preview-menu.py` 有宿主时必挂的假 FAIL（宿主重写词库 → SKIP）。`make verify` + 56 文件/295 例全绿。
- 2026-11-06 / pi（air）：**键间隔可配 + soak 定版复跑（报告 229 §7.5）**。`type-session` 加 `KEY_HOLD`/`KEY_INTERVAL`（soak 120/250），soak 修掉 chunk 计数 off-by-one（`shijian` 段此前从未跑过）、新增 `truncated_rounds` 截尾门禁与 `WARMUP` 基线热身。5 分钟结果：30 轮全部走 IME、0 截尾、365 键、0 外联、footprint 31.5→33.5MiB、词库 1146 行重启一致。遗留：`ps rss` 在 macOS 27 计入共享页，硬顶 96MiB 贴近误判边缘。
- 2026-11-06 / pi（air）：**久用按新驱动重跑（报告 229 §7.4）**。5 分钟 18 轮全部走 IME、0 外联、RSS 增长 0.0MiB、词库 1145 行重启一致、宿主重启后执行 SHA 不变并还原输入源。注意新驱动 5 分钟只有 ~290 键（旧驱动 ~1.7k），需要同音量时用 `MINUTES=15`。
- 2026-11-06 / pi（air）：**延迟门禁按方案 A 修好（报告 229 §7）**。`imetype` 新增 `TimedTextView`（在 `setMarkedText`/`insertText` 打时间戳），`perf-session`/`soak-session` 改 HID 投递、`type-session` 输出 `latencies_ms`。首次真实数据：160 键 p50 4.19ms / p95 14.64ms / max 24.68ms、0 外联、RSS −0.1MiB；`make verify` + 离线 56/303 全绿。soak 待授权重跑。
- 2026-11-06 / pi（air）：**1.1.0 装机跑自动探针（报告 229）**。热键 8/8 与 TextEdit 实键入 PASS；性能门禁改判 **BLOCKED**——`--self-post` 不计 IME（ASCII 直通被当成 p95 7.19ms），历史 p95 需复核；客户端 Safari/Chrome/Xcode 回读为空。修工具链三处（相对 OUT、性能在矩阵前、终端项不再往用户 shell 打字）。输入源/config 已还原 `5d4271fb…`。
- 2026-11-06 / pi（air）：**交接对齐现实**。HANDOFF 原停在 1.0.0，实际已走到 1.1.0/build 38（1.0.1 ADR-305、1.0.2 ADR-306 自更新闭环、B 基线报告 227、C 简码+位次上移报告 228）。air 已装 38（`d3c5a2ef…`）、pro 仍 1.0.0/build 34；站点 `v1.0.2 · 构建 37`。下一步 = 1.1.0 装机复验 → tag/Release（§4）。
- 2026-11-05 / pi（air）：**1.1.0 代码入库（ADR-304 / 报告 228，build 38）**。一级简码 25 条（D17）+ 有界位次上移；`jianma1` 56%→100% 命中、首选 32%→100%，其余类别零劣化；PR #223 → main `393318c`，air 已装候选。
- 2026-11-05 / pi（air）：**B 基线采集（报告 227）**。200 条样本集 + `ime-eval` 评测器 + `1.0.2-build37` 基线 JSON 入库，改排序前后可一键对比。
- 2026-11-05 / pi（air）：**更新器自更新闭环（ADR-306 / 报告 226，1.0.2/build 37）**。`stopHost` 自杀缺陷修复后在真机复验通过，回执、备份、staging 清理全部核对。
- 2026-11-04 / pi（air）：**MVP 正式发布 `v1.0.0`**（tag → Release `41888742821`，ZIP `a7f89ee1…` 与候选逐字节一致，DMG staple/spctl 通过，appcast `sparkle:version=34`，Pages 上线 `v1.0.0 · 构建 34`）。
