# HANDOFF — 当前状态

## 0. 元信息

- 更新：2026-10-19 22:15 / pi（deepseek-flash）· **发布门禁推进中：IT-01 已收口可做部分、IT-03 报告机器可校验、下一步 IT-14 前置**
- 分支：`main` @ `b37a565`（已推送；工作树 clean；仅 main）
- 阶段：A 装 `07bbb2f`（执行 `681fb1c8…`）；报告 097（所有权）/098（数据根）/099（真实 IMK）/100（独有身份）/101（机器可校验报告 pass=9 blocked=14）
- 最近验证：`make verify` 全绿；CI + macOS 出包对 `07bbb2f` 均 success

## 1. 安装与数据

| 设备 | 系统 | 已装包 | 状态 |
|---|---|---|---|
| A（`bot`，Intel / macOS 13.7.8） | x86_64 | `07bbb2f`（执行 `681fb1c8…`，Notarized Developer ID） | `config` SHA `809e2cae…`（mixed/中文标点/简体/半角、显式 hotkey 8 项）；词库 215 行；输入源**当前为 `Lampyris.default`**（用户可能正在使用，勿擅自切走）；宿主 91040 |
| B（`joker`，arm64 / macOS 27） | arm64 | `17053e1`（`535d546f…`） | 报告 093：UI 验收通过；未参与本轮 |

- 取包（A）：CI `macOS Acceptance Package` → `packaging/out/a-098/candidate-jEPEDX`（commit `07bbb2f`）。
- 本地换包：`make macos-fast-reinstall APP=… ARGS=--stop-host`（不注销；需先在系统设置移除输入源；`--keep-data` 保留用户数据）。
- 数据隔离：`launchctl setenv LAMPYRIS_SUPPORT_DIR <绝对路径>`（ADR-215）；**先 kill 宿主再 unsetenv**。

## 2. 本轮完成（2026-10-19 发布门禁）

| 提交 | 内容 | 报告 |
|---|---|---|
| `3369ee4` | A 机全新安装 `17053e1` 并验收（a–j） | 094 |
| `7f51687`/`888b8d1`/`c5c8b4a`/`5d762d4`/`a278d70` | HUD 光标：firstRect→两趟 attributes、前台应用校验、窗口归属（层号≥0）、屏内校验 | 095/096 |
| `a138921` | 不注销换包路径 `make macos-fast-reinstall` + `tissrc` + `iterate-macos-ime` 技能 | — |
| `08bcdf2`/`07bbb2f` | 前台应用校验收口 + **ADR-215** `LAMPYRIS_SUPPORT_DIR` 数据根覆盖 | 098 |
| `31aef04`/`f46d458` | IT-01：TextEdit 所有权（macOS 13 窗口销毁修复）、独有身份实体包注册 PASS | 097/100 |
| `1335f50`/`57eaf14` | 真实 IMK 验收（私有根）+ `guard-focus.sh` 发键闸门 | 099 |
| `e3db1de`/`b37a565` | IT-03 机器可校验报告（`check`：pass 9 / blocked 14）+ undo/四状态/长组合补测 | 101 |

## 3. 当前未决

- **IT-14 前置（当前阻塞发布门禁的下一步）**：需要 CI 产出「**隔离身份 + Developer ID 签名**」的包。
  现有 `.github/workflows/isolated-imk-notary.yml` 只支持 B 机（arm64 runner、绑定 `/private/var/folders/…` 的私有根）；
  要扩成：支持 x86_64/universal、可指定任意目标根、产物带 `IMKTestRoot` 绑定说明。做完后能一次性补验
  「已装独有包输入 / Safari / Terminal / 多屏 / 唤醒」这几项（报告 100 记录 A 机因 ad-hoc 无证书全部 BLOCKED）。
- **IT-01 剩余**：微信聊天隔离草稿（BLOCKED）、完整剪贴板多类型恢复（仅命名剪贴板 + mock 证据）。
- **IT-12 性能基线**、**IT-03 剩余 14 项 BLOCKED**、**IT-15 独立重建**、**IT-23 五日试用**：未开始。
- **A 工具链差异**：`make macos-offline-tests` 在 A 必红（Swift 5.8.1 编不了若干测试 + 高负载 `swiftc` 超时）；Swift 侧门禁以 CI 为准。
- **流程坑（已写进技能与报告）**：`typekeys a b c` 会用空格连接参数；发键前必须 `guard-focus.sh <目标>`；
  `unsetenv` 只影响新宿主。

## 4. 下一步

### 4.1 主线：IT-14 前置（CI 签名隔离包）

1. 改 `.github/workflows/isolated-imk-notary.yml` 与 `packaging/macos/prepare-isolated-ci.py`：
   - 允许 `arch=x86_64|universal`（A 是 Intel）；`TARGET_TEST_ROOT` 允许任意本机私有根（不必 `/private/var/folders`、不必 arm64）；
   - 保留「签名前重绑 `IMKTestRoot`、不在 runner 上执行接收方绑定包」的安全约束；
2. `gh workflow run isolated-imk-notary.yml -f target_root=<A 的私有根>` → 下载产物 → 核对 zip/执行 SHA；
3. A 上安装（需要一次注销或 fast-reinstall 路径）→ 系统设置添加隔离输入法 → 跑
   `run-installed-textedit-probe.py` / `run-installed-safari-probe.py` / `run-installed-terminal-probe.py`（normal/failure/INT/TERM）；
4. 写报告 102，更新 101 报告把对应项从 BLOCKED 改判。

### 4.2 备选（不依赖签名）

- 在当前候选补测 `focus`（HUD 各场景）与 `multi-display`，把 101 的 BLOCKED 再减 2 项；
- 采集 IT-12 的引擎/渲染基线（`run-perf.sh`、`render_perf.swift`），宿主级时延留到签名轮。

## 5. 授权与边界

- 不自动注销/重启/解锁；重启由用户执行。安装替换前必须切 ABC、移除输入源、宿主退出；禁止热替换。
- 配置只经 `ime-config`；不手改 `config.toml`、不写 `UserDefaults`；`--purge-data` 只移出、不删除。
- 不操作用户真实文档/聊天；失败即停并保留证据；截图/口头确认不记为正式 PASS。
- 一轮只测一个包；探针遵守 `tools/macos-probe/README.md`。
- 本轮经验：源未移除但宿主已停时可「移除源 → 终止孤儿宿主 → 安装 → 重新添加」，不等同热替换；TCC 改动需告知用户。

## 9. 会话日志

- 2026-10-19 / pi：**交接：发布门禁中段**。A 装 `07bbb2f`；097 所有权 / 098 数据根 / 099 真实 IMK / 100 独有身份注册（软链 BLOCKED、实体 PASS）/ 101 机器报告（pass=9 blocked=14）。补测 undo+四状态+长组合 PASS；下一步 IT-14 前置（CI 签名隔离包）。
- 2026-10-19 / pi：**HUD 收口**：Finder 桌面不显示、Finder 搜索框显示、TextEdit 8pt、Terminal 显示（报告 095/096）；判据全部通用（前台应用/屏内/普通窗口/attributes 两趟）。

- 2026-10-19 / pi：**HUD 预期澄清 + ADR-214 修复**。用户确认：空文档有光标应显示（撤销 D8）、终端有光标应显示（D12 缺陷）、Finder 无文本焦点不应显示（D7 成立）。改 `StateHUDCaretResolver`（firstRect 优先、attributes 仅 length>0 兜底）+ `candidate.hud-source` 断言；A 的 Swift 5.8.1 同源编译小程序 5/5 PASS；待新包复验。
- 2026-10-19 / pi：**A 机全新安装 `17053e1` 并验收（报告 094）**。重启后 `--purge-data` 安装（执行 `535d546f…`、旧数据进 `uninstalled/`），首次配置 `3bc1117c…`（全模板、`alt+f`、零 `ctrl+shift`）；a–g/i/j 全 PASS，D2/D3 未复现；**h 的两项 FAIL**：Finder 前台时 HUD 仍显示（(64,658)）、空文档仍显示（(98,46)）→ 记 D7/D8 待 ADR 定夺；macOS 13 上 HUD 不在 AX 树内，改用 CGWindowList + 像素 OCR 取证。

- 2026-10-18 / pi：**A 机换包前置就绪，停在注销前**。包已下载解压并核对 zip `02b70dfd…`/执行 `535d546f…`（codesign+staple OK），dry-run 通过；A 实际 config `48259b19…`（`mode=mixed`，显式 hotkey 仅 `ctrl+shift+m` 残留、词库 996 行），与旧 HANDOFF 写的 `907998e6…`/`mode=wubi` 不符，已按实测订正；萤火虫源已移除但宿主 67948 未退出，按边界不杀进程、不热替换。

- 2026-10-18 / pi：**交接：B 新 UI 验收通过、A 待装**。B=`17053e1`（执行 `535d546f…`），config `3bc1117c…`，ABC；CI/出包双绿；A 的 SSH 公钥被拒，待授权或本机执行；发布门禁 I0/I2/I3/I4 未关闭。
- 2026-10-18 / pi：**用户 UI 验收通过**。候选头部字号统一 12pt、芯片/悬停留白、翻页光学对齐均确认；CI/出包双绿。
- 2026-10-18 / pi：**头部字号/留白真机通过（报告 093，`17053e1`）**：输入码/芯片/页码 12pt，芯片高 20、留白 12，悬停 6/2pt；面板 538×70。
- 2026-10-18 / pi：**翻页光学对齐真机通过（报告 091，`ba767ac`）**：翻页组上提 1.5pt，AX 中心 132/132.5 vs 芯片 134。
- 2026-10-18 / pi：**修复 CI pinyin-data 漂移（报告 090）**：URL 固定到 commit `923b108d`，SHA 不变；生成物无 diff，CI 转绿。
- 2026-10-18 / pi：**状态 HUD 光标跟随真机通过（报告 087，`ae84601`）**：去掉动画（后台宿主 alpha 卡 0）、优先 `client()`、空行回退最近字符；无焦点不显示。
- 2026-10-18 / pi：**全/半角默认改 `⌥F`（ADR-210 / 报告 079）**：避开 ChatGPT `⌥Space` 冲突；已有显式配置不覆盖。
