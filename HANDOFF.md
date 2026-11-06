# HANDOFF — 当前状态

## 0. 元信息

- 更新：2026-11-06 / pi（**air 本机**）。阶段：**1.1.0 候选（build 38）已装 air，等「自用 3 天 → tag/Release」；dev 已进 1.2.0 线（build 39），结构库 B0 走到 schema v5**。
- 分支：`dev` @ 本轮提交；`main` = `e43ee55`（PR #224/#225 已合并），开放 PR **0 个**；`dev` 领先 main 未合并的提交均为结构库/文档工作。
- 版本：`Cargo.toml` = **1.2.0**、`packaging/build-number` = **39**；**1.1.0 的 tag 仍应打在冻结候选 `393318c`**；站点仍 `v1.0.2 · 构建 37`（1.1.0 未发布）。
- 最近验证：`make verify` PASS（203 产物零网络符号）、`make macos-offline-tests` **61 文件 / 320 例 PASS（6 并发 ~70s）**。1.1.0 候选身份：ZIP `448d3170fdcb…`、源码 `e0b9536b2994…`、宿主执行 `d3c5a2efd1ae…`。

## 1. 设备与数据

| 设备 | 已装包与执行 SHA | 数据 / 输入源 | 恢复点 |
|---|---|---|---|
| **air**（arm64 / macOS 27.2 / Xcode 27，用户 `joker`；pi 跑在 Background 会话，驱动不了 GUI 点击） | **1.1.0 / build 38**（候选），宿主执行 `d3c5a2ef…`，宿主 PID 59867；输入源 `Lampyris.default` 在用 | config `5d4271fb…`（`full_width=half` 已是 ADR-305 枚举形态）、词库 1139 行（用户在用，行数会变） | `uninstalled/`、`updates/` 可回滚到 1.0.0…1.0.2 |
| **pro**（Intel / macOS 13.7.8，用户 `bot`，SSH 别名 `pro`） | **1.0.0 / build 34**，宿主执行 `94394884…`（**未升到 1.1.0**） | config 与词库保持 1.0.0 基线（`show_wubi_learning=true` 是用户有意设置） | 升级前有 `uninstalled/bundle.*` |

## 2. 本轮完成

### 2.1 结构库 / corpus 线（2026-11-06，报告 240–246）

| 范围 | 结果 |
|---|---|
| **corpus 第二阶段需求清单** | 新增 `docs/结构库第二阶段需求.md`：把缺口拆成 N1 字根字形身份库 / N2 笔画笔顺 / N3 结构标注 / N4 完整拆字，写清准入规格、已否决路线、四道验收门槛（3,000 字 ≥98%、许可齐全、运行资源 ≤512 KiB、离线查询 p95 ≤5ms）与 M2-1～M2-4 里程碑。**体积按现状 558 B/字 外推会超标 3 倍**，已写成第二阶段必做项。 |
| **D3 许可更正（报告 246 / ADR-310）** | 上游 `NOTICE.md` 明确 `wubi86_chaizi.txt` 与 `HeiTiZiGen.ttf` **未附带任何版权声明**；登记从「MIT/低风险」改为「未声明/高风险/仅构建期 oracle」。B0 不再用 D3 作组件来源（`full` 737→735，8 条 D2 漏拆如实标 partial），新增门禁「产物不得出现 D3 来源」。 |
| **字体路线关闭（报告 246）** | 两款候选字体均无许可（D2 的 etmon 还源自无许可的 `qingg`），且 D3 字体不含我们阻塞的 U+F00xx → 走不通。另记两条已证伪路线：私有区等价类传递、IDS 叶数投票。 |
| **B0 schema v5 + D19（报告 245）** | 登记 `yi-bai/ids`（MIT，下载不入库）；`ids`/`idsStructure` 作结构参考（与识别码结构 559/619=90.3% 一致，不覆盖），严格条件补占位 23 条。 |
| **B0 schema v4（报告 244）** | 查明 D2 是「每码位一形」：末位私有区=识别码槽、其余=占位字根；组件数↔码长 100% 对齐，识别码 622；41/42 成字字根有笔画（D14 补 了/也/上）。 |
| **B0 schema v3（报告 243）** | 占位组件 `null` + 键位推断；修掉 D3 字根按字符解析（空格混入组件、BOM/CRLF）缺陷。 |
| **13% 结构不一致归因（报告 242）** | 66/512 是两套**分类口径**差异（独体字判杂合、拆法不同、包围），不是数据错误；处置=五笔识别码为权威、IDS 只作校验、差异归档。 |
| **corpus 数据来源调研（`docs/research/corpus-data-sources.md`）** | 主选 `yi-bai/ids`（MIT）+ Unihan 交叉校验；**不采用** Make Me a Hanzi 的 Arphic 图形、Hanzi Writer、KanjiVG、字典抓取。 |
| **B0 现状（schema v5，1,000 字）** | `full` **735** / `partial` **257** / `unknown` 8；识别码可解释 **624**；含占位 243 条；产物 557,632 B（≈558 B/字）。 |

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

- **corpus 第二阶段未开工（ADR-309/310，需求见 `docs/结构库第二阶段需求.md`）**：缺的是**许可干净的字根字形身份库**（N1，249 条占位的根因）与**真实笔顺**（N2）。现有数据已榨干：IDS 粒度粗（220 条叶数不等）、两款上游字体无许可、D2 自身对 8 个字漏拆。
- **D3 只能作构建期 oracle（ADR-310）**：许可「未声明」，**不得**进发布产物、不得复用其字体；`pua-map.json` 也不随包分发。
- **B0 体积会超标**：现 558 B/字，扩到 3,000 字约 1.6 MiB，超出 512 KiB 预算 → 第二阶段必须先定「运行包字段子集」（`ids`/`positionMismatch`/`notes` 不进包）。
- **1.1.0 预检已过（报告 247）**：候选 `393318c` 身份零偏差（1.1.0/build 38、CI 双绿、ZIP `448d3170…` 逐字节一致、站点仍 `v1.0.2·37`、无 tag）；**自用 3 天已由用户 2026-11-06 显式豁免**（写进 `docs/releases/1.1.0.md` §3）；**只剩授权**：① `git tag -a v1.1.0 393318c` + push（触发 Release）② dispatch Pages ③ pro 换包升级。
- **pro 仍是 1.0.0/build 34**：等 1.1.0 Release 上线后用它自带更新器升级（一次验证同包 + 升级链）。
- **客户端自动回读缺口**：Safari/Chrome/Xcode 在自动矩阵是 BLOCKED，需人工补（报告 229）。
- **`ps rss` 口径**：macOS 27 计入共享页（同宿主 footprint 33 MiB / rss 95 MiB），`RSS_HARD_MB=96` 贴近误判边缘，建议改 `vmmap` footprint。

## 4. 下一步（1.1.0 收尾，按顺序）

1. **机器可判部分（air，无需换包；报告 230 起一套命令）**：
   ```sh
   make verify                      # 13s
   make macos-offline-tests         # 56 文件/295 例，6 并发 ~34s（JOBS=N 可调）
   FAST=1 make macos-auto-acceptance # 迭代档 4.7 分钟；发布门禁用默认档（~9 分钟）
   python3 tools/check-level1-codes.py && make eval-candidates EVAL_JSON=/tmp/after.json
   ```
   判定：零诊断全绿；`jianma1` 命中/首选明显改善、其余类别 `hit%`/`first%`/`keys` 零劣化。
2. ~~装机人工走查~~ **已完成（2026-11-06，报告 234）**：A 档 10 项 + IT-25 四项全部 PASS，无 FAIL/BLOCKED。用户同时定下新规矩：**验收只依赖系统自带应用**（VS Code / 微信等非默认安装的应用从清单移除，Chrome/Xcode 降为 optional），已由 `test-acceptance-portability.py` 强制。
3. **三天自用**：1.1.0 装包后自用 3 天再 tag（计划 §4）；期间不换包，「换包后确认新二进制」必做（报告 220 教训：`lsof … | grep -c deleted` 必须为 0）。
4. **发布（需用户明确授权）**：`git tag -a v1.1.0` 打在**验收候选提交** `393318c` → Release → 核对资产（ZIP `448d3170…` 逐字节一致、DMG staple/spctl、appcast `sparkle:version=38`）→ dispatch Pages → 写 `docs/releases/1.1.0.md` → 站点回读 `v1.1.0 · 构建 38`。
5. **pro 升级**：Release 上线后让 pro 用自带更新程序 `1.0.0 → 1.1.0`（同包 + 升级链一次闭环），升级后核 `payloadSHA256`、执行 SHA `d3c5a2ef…`、config/词库保留。
6. 之后：D 排序观察期（ADR-304 P2/P3，有证据才做）→ E 拼音深化 / F 平台扩展 / G 数据教学（`docs/MVP后执行计划.md`）。

## 4.1 换到 air 后怎么开工

| 项 | 值 |
|---|---|
| 系统 / 架构 | macOS 27.2 / arm64，用户 `joker`，SSH 别名 `air` |
| 仓库 | `~/Documents/EasyInputMethod`（先 `git fetch origin --prune && git switch dev && git merge --ff-only origin/main`） |
| 已装包 | **1.1.0 / build 38**（候选，宿主执行 `d3c5a2ef…`），输入源在用，不要重装 |
| 证据目录 | `platforms/macos/build/acceptance-air-1.1.0-b38/`（候选 ZIP/源码 + 安装记录）；旧候选目录已按用户决定清理 |

```sh
cd ~/Documents/EasyInputMethod && git fetch origin --prune && git switch dev && git merge --ff-only origin/main
git log --oneline -1                        # 记下这个提交
./scripts/handoff-status.sh --for=device    # 重采已装包执行 SHA / config / 输入源 / 词库行数
make verify                                 # cargo 门禁
make macos-offline-tests
```

**air 已知平台差异（别当 bug）**

- `q ` = 「多」（五笔一级简码），首个按键常被窗口激活吞掉 → 探针串看起来像「多你好。」。**1.1.0 起一级简码 25 字都是 1 键首选，探针串开头会多出简码字，属预期。**
- Safari 的输入区要读 AX（macOS 27 标题不随输入更新）；TextEdit 焦点属性读不到时回退窗口文本区。
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
