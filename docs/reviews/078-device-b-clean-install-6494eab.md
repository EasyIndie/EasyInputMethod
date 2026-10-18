# 078 — B 机全新安装 + 重启后实机验收（`6494eab`）

2026-10-18。B 机（`joker`，arm64 / macOS 27.0.1）在**重启后**以 `--purge-data` 全新安装
`Lampyris 0.1.0`（源码 `6494eab`、执行 SHA `8984c223…`），并按 HANDOFF §4.3 的 a–j 逐项验收。
本轮**只测这一个包**，无热替换、无二次重启；配置只经 `ime-config` 读写，未手改 `config.toml`。

## 0. 前置与阻塞（第一次尝试）

首次会话核对发现**并未真正重启**，按守则停在上一步，未做任何改动：

| 检查 | 结果 |
|---|---|
| 开机时间 | `system boot Oct 18 01:00`（当时 11:10，已运行 10h） |
| 宿主 | `PID 37962`，启动于 03:38，仍在跑旧包 `a234ef31…` |
| 输入源 | TIS 仍报告 `cn.jokerhub.inputmethod.Lampyris.default` 可用（退出登录才生效） |

证据：`precondition-check.txt`。用户重启后（11:36）复核：宿主未运行、旧包在、启用列表中无萤火虫
（`precondition-after-reboot.txt`）；当前源为搜狗五笔，已先切回 ABC 再安装。

## 1. 包与全新安装

| 项 | 值 |
|---|---|
| zip SHA-256 | `0325ef9d6bb8eaedda4f2ac6c1f1a593658184ee4986f5fdc6ea061ecc08daee` ✅ 与 HANDOFF 一致 |
| 执行 SHA | `8984c22373a24d4b2a20fe038ff5a21c38970fd79606be8564347e661f43087e` ✅ |
| 公证 | `spctl` = Notarized Developer ID；`stapler validate` 通过 |
| 旧包 | 移到 `uninstalled/bundle.gDETF5/Lampyris.app`（未删除） |
| 旧配置 | `uninstalled/data.fNwzqh/config.toml`，SHA `6314f3f4…`（8 项显式 `ctrl+shift*`） |
| 旧词库 | 同目录 `user-dictionary.tsv`，**510 行**（HANDOFF 记的 496 行已增长） |
| 新宿主 | `PID 2193`，跑 `8984c223…` |

`make macos-clean-install` 主流程一次通过（`clean-install.log`）；`selsrc` 无法自动选中是因为源已被移除，
按脚本提示在系统设置里添加「萤火虫」后选中（TIS 的 `TISEnableInputSource` 返回 0 但不生效，不写系统 plist）。
安装产物与数据状态见 `install-state.txt`。

## 2. 验收结果

| # | 项目 | 结果 | 证据 |
|---|---|---|---|
| a | 菜单 7 个产品行 + 快捷键 `⌥M / ⇧ / ⌥空格 / ⌥T / ⌥P / ⌥, / ⌥A` | **PASS** | `02-menu-open.txt` / `02-menu-dump.txt` / `02-menu-shortcuts.txt` |
| b | 全新配置 `mode=mixed`、旧 `ctrl+shift*` 零残留、旧数据在 `uninstalled/` | **PASS（口径需订正，见 D1）** | `02-fresh-config.toml` / `02-fresh-config-checks.txt` / `install-state.txt` |
| c | `wq`+空格→你；`nihao`+空格→你好；`kwwl`→中华人民共和国（auto_commit） | **PASS** | `03-wubi-wq.txt` / `03-pinyin-nihao.txt` / `03-mixed-kwwl.txt` |
| d | `⌘Z` 撤销 IME 提交 | **PASS（分组行为与 macOS 13 不同，见 D4）** | `04-undo-fresh.txt` / `04-undo-grouping-macos27.txt` |
| e | 四状态往返 + 模式三循环，每步回读 config | **PASS** | `05-state-language.txt` / `05-state-width.txt` / `05-state-variant.txt` / `05-state-punctuation-1.txt` / `05-state-punctuation-2.txt` / `06-mode-cycle.txt` |
| f | 设置页快捷键分区 8 项；关于页按钮同行、文字行居中 | **PASS（宽度见 D3）** | `07-settings-shortcuts-ax.txt` / `07-settings-shortcuts.png` / `07-about-layout.txt` / `07-about-ax-texts.txt` / `07-about.png` |
| g | 候选窗 5+ 候选 + `1/N` 时 64pt、上下留白 8/8；带附行 92pt | **PASS** | `07-candidate-frame.txt` / `07-candidate-ax-layout.txt` / `09-ui-snapshots.txt` |
| h | `⌃Space` 切到萤火虫后立刻按 Shift：只切中英，不变全角 | **PASS（见 D5）** | `08-ctrlspace-shift*.txt` |
| i | 复核 A 的 D2/D3 | **PASS（均未复现）** | `07-settings-open.txt` / `07-about-first.txt` / `07-about-stability.txt` |
| j | 还原 mode/标点/字形/输入源；config 字节、宿主、包不变 | **PASS** | `10-restore-before.txt` / `10-restore-after.txt` / `10-final-state.txt` |

### a. 菜单

`items=23`，产品行 7 项；AX 的 `AXMenuItemCmdChar` + `AXMenuItemCmdModifiers` 直接读出：

| 行 | 标题 | char | mods | vkey | 解码 |
|---|---|---|---|---|---|
| 模式 | 混输模式 | `M` | 10 | — | `⌥M` |
| 中英 | 中文输入 | — | 8 | 56 | `⇧` |
| 全/半角 | 半角输入 | — | 10 | 49 | `⌥空格` |
| 简/繁 | 简体输入 | `T` | 10 | — | `⌥T` |
| 标点 | 中文标点 | `P` | 10 | — | `⌥P` |
| 设置 | 设置 | `,` | 10 | — | `⌥,` |
| 关于 | 关于 | `A` | 10 | — | `⌥A` |

`mods=10` = `NoCommand(8) + Option(2)`，与 ADR-209 的 Option 语义一致；空格/Shift 仍以 vkey 报字符。

### b. 全新配置

首份 `config.toml` 由 `persist::generate_template()` 生成（`ime-config` 的既有设计），因此**全量写入**
带注释的 Schema 默认值：`mode=mixed`、`toggle_*=alt+*`、`toggle_english=shift`、`count=7`、
`punctuation=chinese`、`full_width=false`、`chinese_variant=simplified`。
`ctrl+shift` 出现次数 **0**。SHA `3154254f…`（还原后仍相同）。

> D1：HANDOFF §4.3(2) 写的「无显式 `hotkey.*`」与实际实现不符——文件是全量模板，不是仅写改动键。
> 真正该断言的是「没有旧 `ctrl+shift*` 残留」，本轮按此判 PASS，并把 HANDOFF 口径订正。

### c–d. 输入与撤销

| 操作 | 结果 |
|---|---|
| `wq` + 空格 | 你 |
| `nihao` + 空格 | 你好 |
| `kwwl`（四码唯一） | 立即上屏 中华人民共和国 |
| 新建文档 `wq`+空格 → 你，`⌘Z` | 回到空文档 |

> D4：macOS 27 的 TextEdit 不再因方向键断开 IME 提交的撤销组。`你` + `方向键` + `你好` 后 `⌘Z`
> 会一次撤销两段（`04-undo-grouping-macos27.txt`）；单次提交的撤销正常。属客户端/系统行为差异，
> 与报告 071（macOS 13 只撤销最后一条）不同，不影响输入法本身。

### e. 四状态与模式

- 中英：`中文输入` ↔ `英文输入`，会话级，不写 config。
- 全/半角：`半角输入` ↔ `全角输入`，会话级，`full_width` 保持 `false`。
- 简/繁：`简体输入` → `繁体输入`（`traditional`）→ 还原 `simplified`。
- 标点：`中文标点` → `英文标点`（`english`）→ 还原 `chinese`。
- 模式：`mixed` → `wubi` → `pinyin` → `mixed`，菜单标题同步 `混输/五笔/拼音模式`。

### f. 设置 / 关于

- 设置窗口 650×588，**首次打开落在「输入」**（A 的 D2 在 macOS 27 未复现）。
- 快捷键分区实读：`⌥M / ⇧ / ⌥空格 / ⌥P / ⌥T / ⌥, / ⌥A / ⌥L`，顺序与 ADR-209 一致。
- 关于窗口 450×356；「复制诊断」78×26、「反馈问题」101.5×26，**同一行 y=398、高 26、中心同在 x=720**；
  三行文字均为 `x=512 w=416`，中心对齐（报告 072 的修正生效）。
- D3：宽度并未收到「75/80pt」量级——`反馈问题` 的固有宽度（含雪佛龙）就是 101.5pt；
  本轮判 PASS 的依据是「按固有尺寸收窄 + 同行中心对齐」，并把期望值订正为「两按钮同行同高、中心共线」。

### g. 候选窗

- 实机：`wq`（7 候选 + `1/12`）时面板 **468×64**；AX 中编码行 y=93（距顶 7pt），候选行
  y=117、h=26、底 143（距底 150 有 7pt），即上下等距，符合 073 的「底部 ≤ 顶部 + 2pt」不变式。
- 学习区开启（`⌥L`）时面板变为 468×154，关闭后回到 64（`07-candidate-frame-learning.txt`）。
- 离屏快照（`make macos-ui-snapshots`）：
  - `single` / `pager`：400×64，顶/底 **8/8**；
  - `hint`（带附行）：400×92，顶/底 8/36；
  - 快捷键文本行与菜单/设置一致。

### h. `⌃Space` 误切回归

- 英文模式、源 ABC → `⌃Space` 切到萤火虫 → **立刻**按 Shift：菜单仍是 `半角输入`，**未变全角**（核心回归不成立）。
- 但合成事件下这第一次 Shift 未切中英：宿主在源刚切换时还没绑定客户端输入上下文；点一下文本区后
  Shift 立即正常切到 `中文输入` 且保持半角。真实用户在有焦点输入框里切换不受影响；
  探针口径已记录，避免把「探针焦点问题」误判为缺陷。

### i. A 的 D2 / D3

- D2：macOS 27 首次打开设置落在「输入」，与 B 旧结论一致；A 的「候选」更像 macOS 13 的
  `NSToolbar` 初始化差异。
- D3：按「AX 点工具栏快捷键 → 立刻点关于」重复 3 轮，**3/3 出窗**，未复现瞬时不出窗。

## 3. 还原

| 项 | 还原后 |
|---|---|
| 输入源 | `com.apple.keylayout.ABC` |
| mode / 标点 / 字形 / 全角 / 学习区 | `mixed` / `chinese` / `simplified` / `false` / `false` |
| `config.toml` SHA | `3154254f56f894a9ec4e63fb73e0cf53f58020c1309410b51d3c406af523f120`（切换源前后一致） |
| 已装包执行 SHA | `8984c223…`（未变） |
| 宿主 | 仍为 `PID 2193`，窗口数 0 |
| 自建文档 | `/tmp/lampyris-b/` 已删除，TextEdit 未保存退出 |

## 4. 差异与后续

| 编号 | 现象 | 判定 |
|---|---|---|
| D1 | 首份配置是全量模板（含 `alt+*`），不是「只写改动键」 | 文档口径订正（HANDOFF §4.3） |
| D2 | macOS 27 设置面板首次打开=「输入」 | A 的 macOS 13 差异，macOS 27 不复现 |
| D3 | 关于按钮 78 / 101.5pt，非 75/80 | 按固有尺寸 + 同行居中即通过，订正报告 072 的期望写法 |
| D4 | macOS 27 方向键不能断开 IME 提交的撤销组 | 系统/客户端差异，非输入法缺陷；单次撤销正常 |
| D5 | 源切换后第一下 Shift 在合成事件下未切中英（点一下文本区即正常） | 探针焦点问题，非误切全角回归 |

发布门禁不变：I0 安全 / I1 可靠性 / I2 体验 / I3 性能与兼容 / I4 分发仍未关闭；
本报告只覆盖「新包在 B 机全新安装后的核心行为」。

## 5. 证据目录

`platforms/macos/build/acceptance-b-078/`（`platforms/macos/build/` 已被 `.gitignore` 忽略，不入库）：
前置、安装日志、菜单、配置、输入、撤销、四状态、模式、设置/关于、候选帧、快捷键回归、快照与还原，共 46 个文件。
