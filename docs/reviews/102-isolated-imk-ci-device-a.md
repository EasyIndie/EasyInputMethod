# 102 — IT-14 前置：CI 出「隔离身份 + Developer ID」包（A 机实测完成，Safari 一组 BLOCKED）

2026-10-19/20，A（Intel / macOS 13.7.8）。目标：让 CI 产出**隔离身份 + Developer ID 签名/公证**的测试包，
用来补验报告 101 里 `application-Safari` / `application-Terminal` / 「已装独有包输入」的 BLOCKED 项。

**当前状态（2026-10-20 08:20）：重新登录后系统已发现隔离源，TextEdit、Terminal、Safari 三组各 4 场景共 16/16 PASS**
（Safari 需先把测试工具改成 LaunchServices 投递，见 §5.3）。

## 1. 工具扩展（提交 `c60bd88`）

| 文件 | 改动 |
|---|---|
| `.github/workflows/isolated-imk-notary.yml` | 新增 `arch`（`arm64`/`x86_64`/`universal`）；固定 arm64 runner 上交叉构建（Rust `--target` + Swift `-target <arch>-apple-macosx13.0` + `lipo`）；签名前用 `lipo`/PlistBuddy 复核架构与 `IMKTestRoot` 绑定；附件名带架构 |
| `packaging/macos/prepare-isolated-ci.py` | 目标根从「只允许 `/private/var/folders`」放宽为「接收设备系统临时目录内」：`/private/var/folders/**/T`、`/private/tmp`、`/tmp`、`/private/var/tmp`、`/var/tmp` 的直接子目录；仍要求 `lampyris-imk-<UUID>`、绝对规范化、无 `..`，拒绝真实数据目录 |
| `platforms/macos/tests/isolated-imk.py` | `build(root, arch)` 按架构切片构建；本机默认（`native`）行为不变；新增 `build_arches`/`macho_arches` |
| 测试 | `test-isolated-ci.py` 3 项、`test-isolated-imk.py` 6 项全绿；`make verify` 全绿 |
| 文档 | `ADR-216`、`packaging/macos/ISOLATED-CI.md` |

安全约束保持：**签名前**才把 `IMKTestRoot` 重绑到接收方目标根，此后不在 runner 上执行该包；
凭据仅 main、Actions 固定 commit、签名材料 always 清理。

## 2. 出包与核对（run `39269308347`，commit `c60bd88`，success）

- 私有根：`/private/var/folders/x7/hhbm75rn6vz_37yjj5rsq9yc0000gn/T/lampyris-imk-fd15c596-…`（0700 + 0600 `owner`）。
- 产物：`LampyrisIMKTest.zip`，SHA-256 `d14a395bdb25bdd763ecdc9a3865d1ae73c953cb386cb89a6b0daa6ebae39c8d`；
  包内 `TARGET-ROOT.txt`、`TARGET-ARCH.txt`（requested=built=x86_64）、`SOURCE-COMMIT.txt` = `c60bd88…`。
- 执行文件：`x86_64`，身份 `cn.jokerhub.inputmethod.LampyrisIMKTest.fd15c596-…`；
  `codesign --verify --strict` ✓、`stapler validate` ✓、`spctl` → **accepted / `source=Notarized Developer ID`（Team `2N62934Y28`）**；
  `IMKTestRoot` 与目标根一致（证据 `102-package-verify.txt`）。

## 3. 安装（未动生产包与用户数据）

- 解压后复制为私有根内 `LampyrisIMKTest.app` 与 `~/Library/Input Methods/LampyrisIMKTest-fd15c596-….app`，
  并做 `lsregister -f`；`source-state` 编译完成。
- 装前/装后：生产 `Lampyris.app` 执行 SHA `681fb1c8…`、宿主 91040 未停止、真实 `config.toml` `809e2cae…` 未变；
  本轮**没有**设置 `LAMPYRIS_SUPPORT_DIR`（隔离包自身把配置写明在私有根内）。
- 隔离包启动前置（`IMKTestRoot`、UUID、0700/0600 所有权、签名）由包自身与探针再次校验。

## 4. 阻塞：系统发现需要一次重新登录（BLOCKED，非 FAIL）

| 检查 | 结果 |
|---|---|
| TIS 枚举 | 2 个自有身份（父源 + `.default` 模式），`enableCapable=true`；`.default` 模式 `enabled=true`、`selectCapable=true`（证据 `02-state-after-install.json`） |
| 系统设置「＋」列表 | **看不到**「萤火虫隔离验收 fd15c596」（用户确认） |
| 菜单栏输入法菜单 | **看不到**（用户确认） |
| 尝试启用父源并选择独有模式 | **`TISSelectInputSource` 返回 `-50`**，父源 `enabled` 仍为 0（证据 `102-select-blocked.txt`） |
| 状态恢复 | `restore-original` 正常，当前源回到用户原源；真实数据未变（`05-state-after-restore.json`） |

与 ADR-130/131 在设备 B 的实测一致：**公证包本身通过校验，但新装第三方输入法的系统发现发生在登录时**；
不重新登录时源不可见、`TISSelectInputSource = -50`。本轮不绕过（不写 `com.apple.HIToolbox` 偏好、不伪造启用）。

## 5. 重新登录后的实测结果（2026-10-20 07:39–08:00）

### 5.1 重新登录解决了「需一次登录才被发现」

| 检查 | 重新登录前（§4） | 重新登录后 |
|---|---|---|
| 自有父源 `enabled` | `false` | `true`（用户已在系统设置添加） |
| 自有模式 `.default` `enabled` / `selectCapable` | `true` / `true` | `true` / `true` |
| `TISSelectInputSource` | **`-50`** | 成功切换到 `.default`（见 §5.2 各运行目录的 `selected.json`） |
| 系统设置「＋」与菜单栏菜单 | 看不到 | 可见并可添加（用户确认「现在有了」） |

- 重新登录把 `$TMPDIR` 内的私有根清掉了；路径未变，按 ADR-131 在**同一 UUID 路径**重建空根（`0700` + `0600 owner`），
  重新编译 `source-state`（1m12s，`-warnings-as-errors`），包的 `IMKTestRoot` 绑定仍然有效，无需重跑 CI。
- 证据：`102-evidence/102-state-after-relogin.json`（自动可见、父源仍 0）、`102-state-after-add.json`（用户添加后两者皆 1）。

### 5.2 探针结果

| 组 | 场景 | 结果 | 证据 |
|---|---|---|---|
| TextEdit | normal / failure / INT / TERM | **4/4 PASS** | `102-evidence/102-textedit-probes.txt` |
| Terminal | normal / failure / INT / TERM | **4/4 PASS** | `102-evidence/102-terminal-probes.txt` |
| Safari | normal / failure / INT / TERM | **4/4 PASS**（解阻后，见 §5.3） | `102-evidence/102-safari-probes.txt` |

- 每组每次运行前都先 `source-state restore-original`，防止用户切源造成的源漂移（两次 miss 都按 BLOCK 处理，未伪造通过）。
- 全部 16 次运行的 `result.json` 均为 `sourceAndEnabledRestored=true`、`realDataUnchanged=true`；
  真实 `config.toml` / `user-dictionary.tsv` 摘要前后一致（探针内建校验，指向 `~/Library/Application Support/Lampyris`）。
- 包身份与来源：`102-evidence/102-isolated-package-identity.txt`（zip sha256 `d14a395b…`、`x86_64`、commit `c60bd88`；
  与生产候选 `07bbb2f` 相比 `crates/` 与 `platforms/macos/Sources/` 无差异）。

### 5.3 Safari 组：根因与解阻（工具侧改动）

**根因**（非输入法缺陷，证据 `102-evidence/102-safari-blocked.txt`）：

- `owned-safari.applescript` 原先 create 走 `make new document with properties {URL: file://…}`；
  窗口能建，但页面始终空白（`URL = missing value`），于是被「页面身份/独有窗口」守卫按设计 BLOCK。
- Safari 日志：`com.apple.Safari:Sandbox … Error fetching token from extension controller without UI`、
  `Loading URL request: failed to obtain sandbox extension: (null)`；WebKit 侧 `didFailProvisionalLoadForFrame code=-1202`。
  Safari 18.6 **不再给 AppleScript 投递的 `file://` 授予沙箱扩展**。
- 对照：`open -a Safari <同一 file:// URL>` 能正常加载（LaunchServices 会带上沙箱扩展）。

**解阻**（经用户授权的验证工具改动，`platforms/macos/tests/owned-safari.applescript`）：

1. create 先 `make new document` 拿到**我们新建的窗口 ID**（保留「不得复用旧窗口」守卫），
   再用 `/usr/bin/open -a Safari <fixture>` 由 LaunchServices 投递页面；
2. 轮询等新页面落地，目标窗口只允许是「我们刚建的那个」或「本轮新出现的」，
   否则 `BLOCKED 未取得独有窗口`（不会接管用户已有窗口）；
3. Safari 会把页面开成标签页，因此只关闭**非 fixture** 的标签，保留「窗口内恰好 1 个 fixture 标签」不变式。

**代价与已知边界**：仍要求 `file://` 离线页面（未改成 localhost 服务）；若用户当时占着 Safari 前台空窗口，
LaunchServices 可能把页面放进旧窗口 → 探针会 BLOCK 而不是接管（宁停不猜）。新增静态契约测试：
`platforms/macos/tests/test-installed-safari-probe.py`（8 项）。

**环境侧另有两个坑（非缺陷，已由用户授权解决）**：
1. 重新登录后 `osascript` 缺「辅助功能」授权（`-1728`）→ 用户为 Ghostty 勾选；
2. `ghostty → TextEdit` 的「自动化」授权被拒（`auth_value=0`，导致 AppleEvent `-1712` 超时）→ 用户在「自动化」里放开。

## 6. 本轮执行记录（上一轮交接给本轮的步骤，已执行 1–4）

1. 校验私有根仍存在且为 0700+`owner`；若登录后临时根被清掉，按 ADR-131 在**同一 UUID 路径**独占重建
   （不恢复测试配置内容），并重新编译 `source-state`。**→ 已做**（临时根被清，已重建空根）。
2. 复核已装包：`codesign --verify --strict`、`stapler`、`IMKTestRoot`、UUID 与私有根一致。**→ 已做**。
3. 系统设置添加「萤火虫隔离验收 fd15c596」（或确认 TIS 两个自有身份已 enabled）。**→ 用户已添加**。
4. 以当时实际原源刷新 `selection-state.json`，再跑
   `run-installed-textedit-probe.py` / `run-installed-safari-probe.py` / `run-installed-terminal-probe.py`
   的 normal/failure/INT/TERM；每批发键前 `guard-focus.sh`，中途失焦立即记 BLOCKED。
   **→ TextEdit/Terminal 完成；Safari 阻塞（§5.3）。**
5. **收尾（2026-10-20 08:35 已执行）**：
   `restore-original`（当前源 → `com.apple.keylayout.ABC`）→ `disable-owned`
   （父源与模式 `enabled` 均 `false`，`enabled` 列表已无测试身份；macOS 13 上模式需等实体包移除后才真正退出列表）
   → 用户在系统设置移除「萤火虫隔离验收 fd15c596」→ `lsregister -u` + 删除
   `~/Library/Input Methods/LampyrisIMKTest-fd15c596-….app` → 删除私有根
   （隔离包的 config/词库、`source-state`、`safari-diag.*`、`screen.png`、`module-cache`）。
   证据：`102-evidence/102-teardown.txt`、`102-teardown-state.json`。
6. **回读（收尾后）**：生产包执行 SHA `681fb1c8…` 未变、宿主未运行、真实 `config.toml` `809e2cae…`、
   词库 `2ee1a469…`（用户自己打字学词，非本轮写入）；`~/Library/Input Methods/` 只剩 `Lampyris.app`，
   私有根已不存在。
7. **收尾后核对**：隔离宿主进程已结束；`tissrc list` 只剩 ABC / sogou / 生产 `Lampyris`（无 `LampyrisIMKTest`）；
   LaunchServices 仍留一条指向已删路径的陈旧记录（`-10814`），不影响 TIS 与系统设置，未重建整库。
8. 遗留（本地、不入库、可随时删）：`platforms/macos/build/installed-*` 19 个探针证据目录。

## 7. 对报告 101 的影响

- `application-Terminal`：**BLOCKED → PASS**。理由：在隔离身份 Developer ID 包（commit `c60bd88`，
  其 `crates/` 与 `platforms/macos/Sources/` 相对候选 `07bbb2f` **无差异**）上四路径全过，
  且每次运行都核对「输入源与启用集合还原」「真实数据未变」。证据：`102-evidence/102-terminal-probes.txt`、
  `102-evidence/102-isolated-package-identity.txt`。
- `application-TextEdit`：保持 PASS，新增本候选四路径独立证据（`102-evidence/102-textedit-probes.txt`）。
- `application-Safari`：**BLOCKED → PASS**。同一隔离包四路径全过（`102-evidence/102-safari-probes.txt`）；
  解阻详情见 §5.3（Safari 沙箱扩展 + 工具侧 LaunchServices 投递）。

## 8. 离线门禁在 A 的解阻（2026-10-20，提交 `edd427e`）

报告 101 的六项（`focus`/`light-dark-layout`/`multi-display`/`imk-performance`/`sleep-wake`/`accessibility`）
在 A 上先被两个**工具缺陷**挡住，与产品无关：

| 缺陷 | 现象 | 修法 |
|---|---|---|
| `LocalAcceptanceEvidence.record(actual: Any)` 收到异构字典字面量 | Swift 5.8.1 报 `heterogeneous collection literal`，7 个 Swift 用例与本地逐场景验收全红（曾被误记为「A 工具链差异」） | 增加 `[String: Any]` 重载 + 显式 `payload` 类型 |
| `run-local-acceptance.py` 无编码声明 | Apple `python3`(3.9.6) 报 `Non-UTF-8 code starting with '\xef'`，脚本根本跑不起来（3.11/3.13 正常） | 补 `# -*- coding: utf-8 -*-` |
| candidate 套件期望用例表过期 | 早于 `candidate.hud-source` / `paths.support-dir-override`，`observe()` 判「未知场景」→ 套件永远 BLOCKED | 用例表补齐 |

结果：

- `make macos-offline-tests`：**32 文件 / 122 用例全绿**（A 上首次）——证据 `102-evidence/102-offline-tests.txt`。
- `make macos-local-acceptance`：**67 个观测全绿**，绑定当前源码树摘要、90 个产物——证据 `102-evidence/102-local-acceptance.txt`。
  覆盖 `candidate.hud`/`hud-position`/`hud-source`（attributes 优先、终端 `firstRect` 兜底、边界夹取、面板不夺焦点）、
  亮/暗候选与面板、对比度目标、菜单/设置/工具/学习区 AX。
- `run-perf.sh`（A/Intel，高负载）：p50 0.55ms、p95 29.6ms、max 503ms、peak RSS 16.9MiB、稳态 12.4MiB
  —— 仅引擎级，不能当宿主门禁（`102-evidence/102-perf-engine-a.txt`）。

仍未解（都要**隔离身份包**，因为生产包会写真实学习词库，规则禁止合成打字污染）：真机 HUD/焦点、真机亮暗截图、
双屏 HUD、宿主级性能、睡眠唤醒、VoiceOver，以及 Chrome/VSCode 客户端矩阵（探针尚未编写）。

## 9. 真机 HUD 实测：HUD 未显示（已定位、已修，ADR-217）

为补验报告 101 的 `focus`/`light-dark-layout`/`multi-display`，新增真机面板探针
（`platforms/macos/tests/run-installed-hud-probe.py` + `isolated-imk/hud-probe.swift`）。

| 检查 | 结果（修复前，隔离包与生产包一致） |
|---|---|
| 候选窗 | ✅ 531×70、`layer 101`、`onScreen=true`、跟随客户端窗口所在屏、前台仍是 TextEdit、窗口截图有真实内容 |
| 状态提示 HUD | ❌ 屏幕上**没有任何像素变化**（按 HUD 矩形逐像素比对：`0/51200`） |
| 同配置最小 `NSPanel` 对照 | ✅ 可见（`44 184/51 200` 像素差异）→ 环境没问题 |

### 9.1 根因：HUD 被自己的「测试模式」判据关掉了（已修，ADR-217）

`StateHUDController.disabled` 原本是
`LAMPYRIS_ACCEPTANCE_OUTPUT != nil || NSApp.activationPolicy() == .prohibited`。
第二条的意图是「无头回归不要建浮层」，但 IME 宿主的 `Info.plist` 带 `LSBackgroundOnly = 1`，
AppKit 对这类常驻后台进程返回的 `activationPolicy` **恒为 `.prohibited`** —— 真实宿主因此也命中「测试模式」，
`show()` 整段提前返回，HUD 从不创建。

对比实验（诊断日志，仅本地构建，未入库）：

```
LAMPYRIS-HUD entry disabled=0 valid=1 caret=Optional((218.0, 1764.0, 1.0, 13.0))
LAMPYRIS-HUD ordered frame={{170, 1785}, {96, 36}} visible=1 policy=1 level=101   ← policy=1 即 .prohibited
```

- 早先「400×32 窗口」其实是**候选窗**被改成状态条尺寸后隐藏，不是 HUD；我的探针又把快捷键按错成 ⌃⇧M
  （默认是 ⌥M），所以 `show()` 从未被调用，现象被双重掩盖。
- 修复（代码一处）：`disabled` 只认显式开关 `LAMPYRIS_ACCEPTANCE_OUTPUT`，并写明宿主恒为 `.prohibited`。
  见 `ADR-217`。

### 9.2 修复后复验（本地构建的隔离包，PAT 探针 PASS）

用修复后的源码本地构建隔离身份包（ad-hoc 签名，替换掉已装包；CI 公证包备份在私有根 `…app.ci-backup`），
`run-installed-hud-probe.py --second-display` 结果：

| 检查 | 结果 |
|---|---|
| 候选窗 | 599×70、`layer 101`、`onScreen=true`、所在屏 = 客户端窗口所在屏（内建屏 0） |
| 状态 HUD | 96×36、`layer 101`、`onScreen=true`、位置在光标上方、所在屏 0 |
| 前台 | 全程 TextEdit（面板不夺焦点） |
| 双屏 | 把客户端窗口移到 LG 4K（屏 1）后，HUD 跟到屏 1 的 (17, −1036)，候选窗同样跟屏 |
| 亮/暗 | 暗色下 HUD 仍可见，截图与亮色不同（10 870 / 10 472 字节） |
| 状态还原 | 输入源与启用集合还原、真实词库未变 |

证据：`102-evidence/102-hud-fixed-probe.json`、`102-evidence/hud/fixed-hud-{0,1,dark}.png`。

### 9.3 对报告 101 的影响

`focus` 仍记 **FAIL**：候选 `07bbb2f` 本身含该缺陷；修复在 main（ADR-217），需要**新候选**出包后用同一探针复验才能改判。
`light-dark-layout` / `multi-display` 的真机证据目前来自修复后的本地构建，同样等新候选复验。

## 证据

- `platforms/macos/build/installed-{textedit,terminal,safari}-*/`（本地，不入库）
- 入库小证据：`docs/reviews/102-evidence/`：包核对与身份、重新登录前后 TIS 状态、`-50` 阻塞、
  TextEdit/Terminal 各四路径 `result.json`、Safari 阻塞与日志根因
