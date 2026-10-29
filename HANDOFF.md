# HANDOFF — 当前状态

## 0. 元信息

- 更新：2026-10-29 / pi（**air 本机**）。阶段：**1.0.0 / build 34 已装两台机器，四道 MVP 门禁已过 IT-14（锁定候选）/ IT-22（走查）/ IT-15（独立重建），只剩 IT-23 五工作日试用未起算**。
- 分支：`dev` 领先 `main` 一个文档提交（main = `27301f5`，PR #214 merge）；开放 PR **0 个**。`make verify` PASS、离线 **56 文件 / 303 例** PASS。
- 版本：`Cargo.toml` = **1.0.0**、`packaging/build-number` = **34**（ADR-298：1.0.0 只对应一个二进制，门禁只在冻结包上做）。
- 已装包：air 与 pro 均为 **1.0.0/build 34**，宿主执行同为 `9439488404a16414d9f2af7ba92d7ee0a735cbbbf27566a7f437b28ac58c7c25`（同一个二进制，`running_deleted=0`）。
- 换设备：仍是 **air 为主**（§4.1）。

## 1. 设备与数据

| 设备 | 已装包与执行 SHA | 数据 / 输入源 | 恢复点 |
|---|---|---|---|
| **air**（arm64 / macOS 27.0.1 / Xcode 27，用户 `joker`；pi 跑在 Background 会话，驱动不了 GUI 点击） | **1.0.0 / build 34**，宿主执行 `94394884…`；输入源 `Lampyris.default` 在用 | config `cfc86cff…`、词库 800+ 行（用户在用，行数会变） | `uninstalled/` 与 `updates/` 备份可回滚到 0.1.14/0.1.15/0.1.16 |
| **pro**（Intel / macOS 13.7.8，用户 `bot`，SSH 别名 `pro`） | **1.0.0 / build 34**，宿主执行 `94394884…`（= air，同包）；词库 765 行 | 输入源 `Lampyris.default` | 从 0.1.16/26 升级上来，备份 `uninstalled/bundle.*` |

## 2. 本轮完成（2026-10-29，1.0.0 build 29 → 34）

| 范围 | 结果 |
|---|---|
| 报告 217 锁定候选（build 29） | 六张截图复验 CaretPlacement（ADR-301）：下方/镜像/底部翻上/不压字全 PASS；报告含身份、门禁分工、IT-22 受查清单、IT-15 重建配方。 |
| IT-22 / IT-15 通过 | IT-22 限定范围通过（必查 11 + 抽查 8 全 PASS，其余引用报告 216 基线）；IT-15 用户在 air 跑 `run-repro.sh`：数据 4/4 逐字节一致、可执行文件差异解释为 SDK（ADR-033）、空闲 0 外联。顺手修好 `set -e` 下数据表比对从未执行的工具缺陷。 |
| build 30 / 31 | 30 修「候选窗跟随鼠标」（`allowsEmptyCaret: true` + 回退链）；31 加 HUD 文件开关诊断（报告 220：**换包后旧进程仍在跑**，非产品缺陷，`lsof … grep -c deleted` 进 skill 收尾清单）。 |
| **ADR-302 / 报告 221+222（build 32 → 33）** | 用户报「组合态按 Shift/⌥M/⌥F 会把编码和候选框一起清掉」。核心 `toggle_width`/`set_mode` 去掉 `cancel()`；Shift 切英文改为**原样上屏编码**。build 32 只修到 ⌥F，因为 Shift 走 `flagsChanged`、⌥M 走 `applyInputMode`（那里先 `cancelClientComposition()`）——33 补上这两条宿主路径，三条实机全 PASS。 |
| **ADR-303 / 报告 223（build 34）** | 候选窗去掉中英芯片：候选窗只在组合态出现、英文模式每键即上屏不建缓冲 ⇒ 芯片恒为「中文」。`chips` 5 → 4，删 `CandidateStatus.english` 字段；HUD 与 VoiceOver 播报不变。用户确认外观 OK。 |

## 3. 未决

- **IT-23 五工作日试用未起算**：两台设备已固定在 1.0.0/build 34，从**下一个工作日**开始记第 1 天；期间**不换包**，只做文档/CI/审查。
- **更新器自更新**仍未在真机演示：本机两次跨版本升级分别由 0.1.14 旧更新程序与被删过 bundle 的旧进程执行，未走 selfUpdate 分支；1.0.0 正式发布时若由 build 34 更新程序执行升级才可闭环。
- 旧账（与本批无关）：`install.sh` 新文案在 pro（macOS 13）复验；`AppleKeyboardUIMode=0` 导致设置面板 Tab 无效（系统默认，非缺陷）。
- 已知行为（写进发布说明）：⌥M 切到无候选的模式时，候选窗隐藏、编码以预编辑文本留在输入框，用户按 Esc 取消或继续补码。

## 4. 下一步（按顺序）

1. **IT-23 第 1 天（下一个工作日）**：`tools/macos-probe/walkthrough-evidence.sh --label it23-day1`，覆盖中英混排 / 较长输入 / 撤销 / 焦点切换 / 睡眠唤醒；逐日 `it23-day2…day5`，模板见 `docs/reviews/211-it23-five-day-template.md`。
2. **五天全绿 → ADR-298 阶段 D**：`git tag -a v1.0.0` 打在**验收候选提交**（本轮 build 34 = `27301f5` 的候选 ZIP `a7f89ee1…`，宿主 `94394884…`）→ 触发 Release → 核对资产（ZIP/DMG/源码/更新程序 `.sha256` + appcast `sparkle:version`）→ dispatch Pages。
3. 发布后：回读站点版本行、补写 `docs/releases/1.0.0.md`、宣布 MVP 完成。

## 4.1 换到 air 后怎么开工

| 项 | 值 |
|---|---|
| 系统 / 架构 | macOS 27.0.1 / arm64，用户 `joker`，SSH 别名 `air` |
| 仓库 | `~/Documents/EasyInputMethod`（先 `git switch dev && git pull --ff-only`） |
| 已装包 | **1.0.0 / build 34**（宿主执行 `94394884…`），输入源在用，不要重装 |
| 证据目录 | `platforms/macos/build/acceptance-air-1.0.0-b29|b33|b34/`（不入库） |

```sh
cd ~/Documents/EasyInputMethod && git fetch origin --prune && git switch dev && git pull --ff-only
git log --oneline -1                        # 记下这个提交
./scripts/handoff-status.sh --for=device    # 重采已装包执行 SHA / config / 输入源 / 词库行数
make verify                                 # cargo 门禁
make macos-offline-tests                    # air 上 56 文件 / 303 例全 PASS
```

**air 已知平台差异（别当 bug）**

- `q ` = 「多」（五笔一级简码），首个按键常被窗口激活吞掉 → 探针串看起来像「多你好。」。
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
- **IT-23 期间不换包**：换包当天作废重来。
- 只用自建文档与自有会话；失败即停并保留证据。

## 9. 会话日志（最近）

- 2026-10-29 / pi（air）：**候选窗去掉中英芯片（ADR-303 / 报告 223，build 34）**。代码确认候选窗只在组合态出现、英文模式 `handle_key` 每键即 `commit` 不建缓冲 ⇒ 芯片恒为「中文」，纯占位。`CandidateStatus.chips` 5 → 4、删 `english` 字段与「语言：」无障碍分支；`candidate-presentation`/`ui-snapshots`/`Preview` 同步。用户实机确认外观 OK。PR #214 → main `27301f5`，候选 ZIP `a7f89ee1…`、宿主 `94394884…`，两台设备已装。
- 2026-10-29 / pi（air）：**组合态切换不再丢字（ADR-302 / 报告 221+222，build 32 → 33）**。核心 `toggle_width`/`set_mode` 去掉 `cancel()`（切模式保留缓冲并按新模式 `recompute_with_commit(false)` 重算、不自动上屏）；Shift 切英文改为把编码**原样上屏**。build 32 只通过 ⌥F——Shift 走 `flagsChanged`、⌥M 在 `applyInputMode` 里先 `cancelClientComposition()`，33 补上两条宿主路径后三条实机全 PASS。PR #212 `c9951fa` / #213 `55ffdc6`。
- 2026-10-29 / pi（air）：**IT-22 限定范围通过、IT-15 独立重建通过（报告 218）**。IT-15 发现工具缺陷：`set -e` 下先 `cmp` 可执行文件（跨 SDK 必失败）导致**数据表比对从未执行**；改为数据表先比（4 张，不一致即失败）、可执行文件后比并解释 SDK 差异。复跑：身份链 PASS、数据 4/4 逐字节一致、空闲 0 外联。
- 2026-10-29 / pi（air）：**build 30/31**。30 修「候选窗跟着鼠标」（`allowsEmptyCaret: true` + 本轮→上次→鼠标回退链）；31 把 HUD 诊断改成文件开关（`launchctl setenv` 传不进宿主），报告 220 定位「HUD 不显示」实为**旧进程仍在跑**，`lsof … deleted` 检查进 skill 收尾清单。
- 2026-10-29 / pi（air）：**1.0.0 锁定候选（报告 217）**：ADR-299 拼音多词拼接、ADR-300 组合开始播报编码、ADR-301 `CaretPlacement` 几何单一决策点；六张截图复验通过，两台设备装同一个 1.0.0 包。
