# HANDOFF — 当前状态

## 0. 元信息

- 更新：2026-10-18 / pi（deepseek-flash）· **状态反馈：候选框内联芯片 + HUD 亮暗修复（报告 080）+ 宽度默认 ⌥F（报告 079）**
- 分支：`main` @ `5fc233a` + 报告 078/交接提交（已推送，工作树干净；无其它本地/远程分支、无额外工作树）
- 阶段：**B 已装 `6494eab`；源码已含 `⌥F`（ADR-210）、状态 HUD + 候选框内联芯片（ADR-211），需重新出包/安装才能看到**；A 仍装旧包 `a234ef31…`；MVP 发布门禁未全部关闭
- 最近验证：`make verify` 全绿（180 产物隐私断言）；B 的 a–j 实机验收全 PASS（报告 078）
- 交接：`make handoff SCENARIO=compact|session|agent|device PROMPT=1` 采集状态并出提示词骨架（流程见 `.agents/skills/update-handoff/SKILL.md`、模板见 `docs/交接提示词模板.md`）；CI `check` + `macOS Acceptance Package` 对 `6494eab` 均通过（run `39088753850`，出包 artifact `Lampyris-macos-acceptance-6494eab746949fc89282d13f38b194bbd0c9eeae`）

## 1. 安装与数据

| 设备 | 系统 | 已装包 | 状态 |
|---|---|---|---|
| A（本机 `bot`，Intel / macOS 13.7.8） | x86_64 | `a234ef31…`（**旧**） | 报告 071 验收通过；`config` SHA `907998e6…`（显式 `mode=wubi`、`full_width=true`）、输入源已还原 ABC；**未做全新安装** |
| B（`joker`，arm64 / macOS 27） | arm64 | `6494eab`（`8984c223…`，**新**） | 报告 078：重启后 `--purge-data` 全新安装 + a–j 全 PASS；`config` SHA `b4e7f50b…`（`mode=mixed`、`toggle_width=alt+f`、无 `ctrl+shift*`）、旧 config/510 行词库在 `uninstalled/data.fNwzqh/`；输入源已还原 ABC，宿主 PID 2193 常驻、窗口 0 |

- **待安装新包 `21abc39`（含 ⌥F 默认 + 状态 HUD + 候选框芯片）**：
  `packaging/out/chips-package/candidate-Qzydv4/extracted/Lampyris-0.1.0-universal/Lampyris.app`
  zip SHA `f298d769…`、执行 SHA `c8baf0ba…`、`spctl` = Notarized Developer ID。
  可从 CI 重新取：`gh run download 39105384532 -n Lampyris-macos-acceptance-21abc396b94ba445dd3524e56a9d9ff8810938ea`。
  （`c5fdaef` 已被取代：只有首版 HUD，无候选芯片。）
- 已装旧包（`6494eab`）：`packaging/out/clean-install/candidate-80z8RZ/…`，zip `0325ef9d…`、执行 `8984c223…`。
- B 旧 `config.toml` 的显式 `ctrl+shift*` 已随 `--purge-data` 移出活动目录，新配置为 Schema 默认值。
- 新增操作经验：安装后输入源必须在「系统设置 → 键盘 → 文字输入」里添加（`TISEnableInputSource` 返回 0 但不生效）；`selsrc` 只负责选中已启用的源。

## 2. 本轮完成（`a234ef31` 之后合入的改动）

| 提交 | 内容 | 报告 |
|---|---|---|
| `2a863e1` | 关于页「反馈问题」下拉按固有尺寸收窄、两按钮按行中心对齐（macOS 13 上原来宽 157pt、错位 4pt） | 072 |
| `7b3a49d` | 候选窗去掉多余的 22pt 底部预留（无 hint 时 74→64pt，上下留白 8/8） | 073 |
| `c337a89` | `make macos-ui-snapshots`（离屏 UI 截图，缓存后 5s）+ 组合键「事件必须晚于最近修饰键变化」的防误判 | 074 |
| `7e2edc7` | **默认快捷键改 Option 语义前缀**（ADR-209）：`⌥M` 模式 / `⇧` 中英 / `⌥Space` 全半角 / `⌥P` 标点 / `⌥T` 简繁 / `⌥L` 学习区 / `⌥,` 设置 / `⌥A` 关于 | 075 |
| `4a48443` | `uninstall.sh --purge-data`：旧包与旧 config/词库移入 `uninstalled/`（移动不删除） | 076 |
| `8f14754` | 不注销验收三档（快照 / 隔离实窗 / 已装包）+ `scripts/clean-install.sh` / `make macos-clean-install` | 077 |

## 3. 当前未决

- **A 机同样待全新安装**（见 §4）：A 的 `config.toml` 仍是显式 `mode=wubi`、`full_width=true`，看不到新默认值；A 是 Intel / macOS 13.7.8，需按 078 的流程重跑并留意平台差异。
- **待安装 `21abc39`**：已出包核验（zip `f298d769…`、执行 `c8baf0ba…`），含 ⌥F、HUD 亮暗修复与候选头部芯片；B 仍装 `6494eab`，需按 §4 注销安装后复验。
- **CI 数据源漂移**：`CI` 的「Reproduce licensed pinyin data」因上游 `pinyin-data/pinyin.txt` 变更而 SHA 不匹配（期望 `621f8ca9…`，实际 `7365b877…`），与本轮代码无关；需按 `add-data-source` 流程复核后更新。
- **终端 Meta 冲突（未决）**：裸 `⌥+字母` 与 zsh/readline 的 `M-f/M-b/M-t/M-l/M-p` 重叠；用户反馈英文模式下透传异常，实测「确认英文」时 `Shift+Enter`/`Ctrl+C` 可透传，疑为状态误判；状态 HUD 可降低误判，但前缀是否改 `⌃⌥` 仍待决定。
- **报告 078 的新差异**：D1 首份配置是全量模板（`alt+*` 全写，非只写改动键）；D2 macOS 27 设置面板首次落在「输入」（A 的「候选」未复现）；D3 关于按钮 78/101.5pt（按固有尺寸 + 同行居中判 PASS，报告 072 的「75/80」口径需订正）；D4 macOS 27 方向键不能断开 IME 提交的撤销组（单次撤销正常）；D5 源切换后第一下 Shift 在合成事件下未切中英（点一下文本区即正常，非全角误切）。
- **发布门禁（均未关闭）**：I0 安全（IT-01…03）／I1 可靠性／I2 体验／I3 性能与兼容（IT-12/14/23）／I4 分发（IT-13 dry_run、IT-15 第三方复现、tag/Release）。
- **A 机遗留差异**（报告 071/073）：D2 = macOS 13 上设置面板首次打开落在「候选」分区（B 的 macOS 27 为「输入」，已复核）；D3 = 紧随 AX 点击工具栏后点「关于」有一次未出窗（B 上 3/3 未复现）。
- **翻页组视觉空隙**（报告 073）：上一页/页码/下一页之间 4pt frame + 24pt 点击区 → 视觉约 17pt，偏松；收紧需改 ADR-183 的点击区契约，待用户决定。
- **A 的 Swift 5.8.1 编译不了 `tools-presentation.swift`/`candidate-presentation.swift`**（`LocalAcceptanceEvidence` 异构字典字面量）：macOS 13 上的这部分离线断言只在 CI 跑；建议单开一张卡修兼容性。
- **正式报告**：`platforms/macos/build/final-menu-abdb83f/formal-report.json` 仍是旧包 `abdb83f` 的 1 PASS/22 BLOCKED。

## 4. 下一步：A 机同样的全新安装 + 验收

> A 机仍是 `a234ef31…`、显式 `mode=wubi`/`full_width=true`。要看到 ADR-209 的新默认值，必须
> `--purge-data` 全新安装。流程与 B 相同（报告 078 已验证），顺序**不能颠倒**。

### 4.1 准备（用户手动）

1. 切到 **ABC**；
2. 系统设置 → 键盘 → 文字输入 → 移除「萤火虫」；
3. 注销/重启使宿主退出（B 的经验：只做前两步不重登，宿主会继续跑旧包）。

### 4.2 登录后（agent 执行，逐条记录，失败即停）

```sh
cd ~/Documents/EasyInputMethod
git fetch origin && git checkout main && git pull --ff-only
make -C tools/macos-probe
# 包：packaging/out/clean-install/candidate-80z8RZ/extracted/Lampyris-0.1.0-universal/Lampyris.app
shasum -a 256 packaging/out/clean-install/*/Lampyris-0.1.0-universal.zip  # 0325ef9d…
make macos-clean-install APP=packaging/out/clean-install/candidate-*/extracted/Lampyris-0.1.0-universal/Lampyris.app
```

安装后若 `selsrc` 报 `missing`：到「系统设置 → 键盘 → 文字输入」添加「萤火虫」，再
`bin/selsrc cn.jokerhub.inputmethod.Lampyris.default`。`TISEnableInputSource` 返回 0 **不会生效**，
不要改系统 plist。

### 4.3 验收（a–j 同报告 078）

先打开**自建** TextEdit 文档（`/tmp/lampyris-a/…`），按键一次激活控制器。逐项与 B 对齐：

1. 菜单 7 行，快捷键 `⌥M / ⇧ / ⌥F / ⌥T / ⌥P / ⌥, / ⌥A`（`mods=10`、`vkey 56`；全/半角已改 ⌥F，ADR-210）。
2. 全新配置：`mode=mixed`、`alt+*`、`ctrl+shift` 零残留；旧 config/词库在 `uninstalled/data.*/`。
   （注意：首份配置是**全量模板**，不要再用「无显式 hotkey.*」当判据。）
3. `wq`→你、`nihao`→你好、`kwwl`→中华人民共和国。
4. `⌘Z`：新建文档单次提交后撤销应回空；macOS 13 的「方向键断开撤销组」按报告 071 操作。
5. 四状态往返 + 模式三循环，每步回读 `config.toml`。
6. 设置页快捷键 8 项；关于页按钮同行、文字行居中（宽度按固有尺寸判，不套 75/80）。
7. 候选窗：`1/N` 时 64pt；`make macos-ui-snapshots` 对照 8/8 与 hint 92pt。
8. `⌃Space` 后立刻 Shift：不得变全角；若 Shift 未切中英，先点一下文本区再复测（探针焦点）。
9. 复核 A 的 D2（macOS 13 设置默认分区可能是「候选」）与 D3（关于瞬时不出窗）。
10. 还原 `mode=mixed`、标点中文、字形简体、输入源 ABC；核对 config 字节、宿主 PID、执行 SHA。

### 4.4 收尾

- 报告 `docs/reviews/079-device-a-clean-install-6494eab.md`（PASS/FAIL/BLOCKED + 证据文件名，
  证据放 `platforms/macos/build/acceptance-a-079/`，该目录被 gitignore）。
- 同步本文件与 `ROADMAP.md`；`make verify` 后提交推送。

## 5. 授权与边界

- 不自动注销/重启/解锁；重启与登录由用户执行，agent 只做重启后的卸载/安装/验收。
- 配置只经 `ime-config`；不手改 `config.toml`、不写 `UserDefaults`。全新安装靠 `uninstall.sh --purge-data` 把文件**移出**活动目录，不删除。
- 不覆盖未知并发改动；不创建全量备份；不操作用户真实文档；微信等真实会话须按 IT 卡单独授权。
- 实机动作前核对自有文档、输入源、宿主与焦点；失配立即停止。用户截图/口头确认不能记为正式 PASS。
- 一轮只测一个包，不热替换；探针遵守 `tools/macos-probe/README.md`。

## 9. 会话日志

- 2026-10-18 / pi：**出 `21abc39` 包（状态芯片 + HUD 暗色修复）**。macOS Acceptance Package 成功，产物核验：zip `f298d769…`、执行 `c8baf0ba…`、Notarized Developer ID；B 待注销安装。`CI` 仍仅因上游 pinyin-data SHA 漂移失败。
- 2026-10-18 / pi：**状态反馈收尾（ADR-211 / 报告 080）**。修好 HUD 暗色背景（离屏渲染未套用 appearance）；候选框可见时不再弹 HUD，改为头部右侧、翻页区左侧的单字状态芯片（混/五/拼、中/英、全/半、简/繁、`。`/`.`，学习区追加「学」），激活态 accent 底色、右对齐并与翻页同中心线；候选窗宽高随芯片自适应并重新定位。新增 `candidate.status`/`candidate.hud` 断言（含亮暗亮度差），`macos-local-acceptance` **64 场景全 PASS**，`macos-offline-tests` 与 `make verify` 全绿；`c5fdaef` 不含芯片，需再出包。
- 2026-10-18 / pi：**出含状态 HUD 与 ⌥F 的新包**（`c5fdaef`）。CI 的 macOS Acceptance Package 成功，产物已下载核验：zip `8ee4d3ee…`、执行 `4bcd4a0d…`、Notarized Developer ID + stapler 通过；B 尚未安装（需注销）。同轮修好 preview smoke 的 ⌥F 用例与 local-acceptance 62 场计数；`CI` 仍因上游 pinyin-data SHA 漂移而红。
- 2026-10-18 / pi：**统一状态反馈 HUD（ADR-211 / 报告 080）**。新增 `StateHUD.swift`（`StateFeedback` 文案映射、胶囊视图、非激活面板），菜单命令与快捷键（含模式/学习区）统一在光标旁提示 1.15s；遵循减弱动态效果、VoiceOver 播报、`.prohibited`/离屏环境不弹窗。`macos-ui-snapshots` 新增 6 张亮暗快照，`controller-menu` 增加文案断言并通过，`make verify` 全绿；需重新出包才能在真机看到。
- 2026-10-18 / pi：**全/半角默认快捷键改 `⌥F`（ADR-210 / 报告 079）**。用户报告 `⌥Space` 与 ChatGPT 虚拟宠物冲突；只改 `hotkey.toggle_width` 默认值，其余保持 ADR-209；已有显式配置不覆盖，B 机经设置面板改为 `alt+f`。同步 ime-config 单测、settings/learning/预览用例、配置架构与发布说明；补登记 `candidate.padding`/`learning.stale-chord` 后 `macos-local-acceptance` 62 场景全 PASS；`make verify` 全绿。
- 2026-10-18 / pi：**B 机重启后全新安装 + 实机验收（报告 078，包 `6494eab`）**。zip `0325ef9d…`/执行 `8984c223…` 核验通过；`--purge-data` 把旧包、旧 `config`（`6314f3f4…`）与 510 行词库移入 `uninstalled/`；a–j 全 PASS：菜单 `⌥M/⇧/⌥空格/⌥T/⌥P/⌥,/⌥A`、`wq/nihao/kwwl`、`⌘Z`、四状态+模式、设置快捷键 8 项、候选 64pt（hint 92）、`⌃Space` 不误切、D2/D3 未复现、还原 ABC；新差异：首份配置是全量模板、macOS 27 撤销分组与 13 不同。下一步 A 机同样全新安装（§4）。
- 2026-10-18 / pi：交接标准化。新增 `scripts/handoff-status.sh`（只读采集分支/包 SHA/config/词源/CI/工具会话，`--for=compact|session|agent|device`，`--prompt` 出骨架）与 `make handoff`；`update-handoff` skill 改为四场景矩阵 + 五步流程 + HANDOFF 契约 + 反例；新增 `docs/交接提示词模板.md`（四份模板）并接入 AGENTS §6.1 与 docs 索引。
- 2026-10-18 / pi：交接 B 机重启后验收。本轮完成 ⌥ 默认值（ADR-209）、候选窗底部留白、关于页按钮、组合键防误判、离屏截图工具、`--purge-data` 与 `scripts/clean-install.sh`；新包 `6494eab` 已出（exec `8984c223…`）并在 A 核验，A 未安装。B 重启后按 §4 执行 `make macos-clean-install` 并写报告 078。
- 2026-10-18 / pi：无注销验收三档 + 一条命令全新安装（报告 077）。`make macos-ui-snapshots` 增设设置四分区截图并打印默认 ⌥ 绑定文本；新增 `scripts/clean-install.sh` / `make macos-clean-install`（卸载→安装→校验，缺 `--input-source-removed` 只打印清单）；明确只有「签名包+真实 IMK」需要一次注销。
- 2026-10-18 / pi：出包 + 交接全新安装。`7e2edc7`/`4a48443` 的 CI 因学习区快捷键用例仍按 `⌃⇧L` 而红，修好并重跑（`6494eab` 全绿）；新包下载核验（zip `0325ef9d…`、执行 `8984c223…`、Notarized Developer ID）。
- 2026-10-18 / pi：默认快捷键改 Option 语义前缀（ADR-209 / 报告 075）。实测系统无「仅 ⌥+字母」快捷键、⌥E/N/U/I 为死键；默认改为 ⌥M/⌥Space/⌥P/⌥T/⌥L/⌥,/⌥A（中英仍单 ⇧）。
- 2026-10-18 / pi：`make macos-ui-snapshots` + 快捷键误判修正（报告 074）。组合键匹配要求事件时间戳晚于最近修饰键变化（20ms 容差），修 `⌃Space` 切换后重投递旧空格被当成 `⌃⇧Space` 而误切全/半角。
- 2026-10-18 / pi：候选窗底部留白修正（报告 073）、关于页 macOS 13 布局修正（报告 072）。
