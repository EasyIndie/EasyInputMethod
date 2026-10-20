# HANDOFF — 当前状态

## 0. 元信息

- 更新：2026-10-20 14:15 / pi（deepseek-flash）· 隔离验收已收尾（16/16）；**再修掉 A 的两个离线门禁缺陷**
  （Swift 5.8 异构字面量 + 脚本编码），A 上 `macos-offline-tests` 122 例、`macos-local-acceptance` 67 观测全绿
- 分支：`main` @ `edd427e`（离线门禁修复）+ 本提交（文档/HANDOFF）
- 阶段：A 生产包 `07bbb2f`（执行 `681fb1c8…`，宿主重启后**未启动**）；报告 102 已补实测结果；
  报告 101 机器报告由 pass 9 / blocked 14 → **pass 11 / blocked 12**
- 最近验证：`make verify` 全绿；`test-installed-safari-probe.py` 8 项绿；隔离公证 CI run `39269308347` success

## 1. 安装与数据

| 设备 | 系统 | 已装包 | 状态 |
|---|---|---|---|
| A（`bot`，Intel / macOS 13.7.8） | x86_64 | 生产 `07bbb2f`（执行 `681fb1c8…`，Notarized Developer ID） | 宿主**未运行**（10-20 07:37 重启后未启动）；真实 `config.toml` `809e2cae…`（19 日 20:45 后未变）、词库 `2ee1a469…`（20 日 07:17，用户自己打字学词，不是本轮写入）；输入源当前 `com.apple.keylayout.ABC`（探针还原值，用户可切回 sogou） |
| A（同上） | x86_64 | ~~隔离测试包 `…LampyrisIMKTest.fd15c596-…`~~（CI run `39269308347`，commit `c60bd88`，zip `d14a395b…`） | **已彻底移除**：`disable-owned` → 用户在系统设置删除输入源 → `lsregister -u` + 删实体包 → 删私有根（含其 config/词库）；`~/.Library/Input Methods` 只剩生产 `Lampyris.app` |
| B（`joker`，arm64 / macOS 27） | arm64 | `17053e1`（`535d546f…`） | 报告 093；本轮未参与 |

- 隔离包本机前置（一次性，已由用户授权）：**Ghostty 需「辅助功能」**（否则 `osascript` `-1728`）+
  **「自动化」允许控制 System Events / TextEdit / Safari / Terminal**（否则 AppleEvent `-1712`）。
- 未设置 `LAMPYRIS_SUPPORT_DIR`；隔离包把 config/词库写在私有根内；真实数据 12 次探针均 `realDataUnchanged=true`。

## 2. 本轮完成（2026-10-20）

| 内容 | 结果 | 报告 |
|---|---|---|
| 重新登录后系统发现隔离源（`-50` 消失，可选中） | 父源/模式皆启用，选择成功 | 102 §5.1 |
| `run-installed-textedit-probe.py` × 4 场景 | **4/4 PASS** | 102 §5.2 |
| `run-installed-terminal-probe.py` × 4 场景 | **4/4 PASS** | 102 §5.2 |
| `run-installed-safari-probe.py` × 4 场景 | **4/4 PASS**（先修工具：`b757c08` 改 LaunchServices 投递） | 102 §5.3 |
| 报告 101 改判 | `application-Terminal` / `application-Safari` BLOCKED→PASS（pass 11 / blocked 12） | 102 §7 |
| A 离线门禁解阻（`edd427e`） | Swift 5.8 兼容 + 编码声明 + 过期用例表 → 122 例 / 67 观测全绿 | 102 §8 |

## 3. 当前未决

- **本地证据目录**：`platforms/macos/build/installed-*`（19 个，探针 `result.json`，不入库）可随时删除。
- **A 的 Swift 门禁已修复**（`edd427e`）：`make macos-offline-tests` 32 文件/122 用例全绿、`make macos-local-acceptance`
  67 观测全绿。A 上单文件 `swiftc` 仍要 1–3 分钟，命令超时别给 300s 以下。
- **IT-01 剩余**：微信聊天隔离草稿（BLOCKED）、完整剪贴板多类型恢复（仅命名剪贴板 + mock 证据）。
- **IT-12/IT-15/IT-23**、**IT-03 其余 13 项 BLOCKED**：未开始。
- **HUD 缺陷已修（ADR-217）并在新候选 `f74aae7` 上复验通过**：报告 103 的 `focus`/`multi-display`/`light-dark-layout` 已 PASS；
  报告 101（07bbb2f）保留 FAIL 作为历史记录。
- **`application-Chrome`（BLOCKED，Chrome 侧问题）**：Chrome 155.0.8059.85 的页面文本框**不使用任何输入法**——
  搜狗、生产 Lampyris、隔离包三种源下字母都原样落进页面（file:// 与 data: 页面都复现，fixture 用标题通道自报）；
  地址栏等原生控件正常；同机 VS Code（Chromium/Electron）**正常**（四路径 PASS）。已排除"输入上下文陈旧"（先选源再重启仍复现）。
- **`application-VSCode` 已 PASS**：探针 `run-installed-vscode-probe.py`（自有临时文件 + ⌘S 落盘读回），四路径全过。
- **重新登录后环境已重建**：私有根同 UUID 重建（0700+owner）、`source-state`/`hud-probe`/`ax-text-wait` 重编译、
  `selection-state.json` 重建（原源 sogou）；隔离宿主按需启动仍不正常（见 §4）。
- **内嵌计时钩子（ADR-218）**：`PerfTrace` 已实现并编入宿主（默认关闭、不记录输入内容、0600 写入）。
  唯一一次成功样本：total 18.7/22.8/9.5 ms（engine 0.11/0.31/1.73 ms）；可重复采样受「宿主按需启动失效 / 手工启动不接管连接」阻塞，
  需重新登录后按 ADR-218 的流程补采。诊断完成后已恢复干净源码并重装（无调试日志）。
- **`imk-performance` 基线与 IT-12 矩阵已采集（PASS）**：`run-installed-perf-probe.py` + `run-installed-perf-matrix-probe.py`
  （冷启动/满词库/首次简繁/唤醒；面板维度 BLOCKED——菜单 AX 树不含本宿主菜单项）。
  过程修复：`make-user-fixture.py` 写 0600（默认 0644 会被宿主所有权守卫拒绝启动）、宿主按需启动偶发失效时 open 兜底。
- **`accessibility` 已 PASS**（VoiceOver 开启下）：候选面板 AX 面完整 + 状态切换后客户端焦点不被夺；
  探针 `run-installed-accessibility-probe.py`（未运行时直接 BLOCK）。
- **`sleep-wake` 已 PASS**：`run-installed-sleep-wake-probe.py`（判据＝睡前/唤醒后各一次 TextEdit 探针）；
  实测唤醒时系统偶尔把输入源重置为 ABC，探针会重新锚定后继续验证。
- **`long-composition` / `undo` / `mode-switch` 已在新候选复验 PASS**：新探针
  `run-installed-ime-features-probe.py`（长组合 + Esc 回退、⌘Z 撤销、⌥M 模式循环读回宿主配置）。
- **本地已替换为修复版隔离包（ad-hoc 签名）**：`~/Library/Input Methods/LampyrisIMKTest-…app` 现在是本地构建；
  CI 公证包备份在私有根 `LampyrisIMKTest.app.ci-backup`，需要回到公证版时替换回去。
- **隔离包已重装并添加输入源**（用户操作），用于继续补验；不再需要重新登录即可被系统发现。
- **报告 101 剩余 6 项 A 侧 BLOCKED**（`focus`/`light-dark-layout`/`multi-display`/`imk-performance`/`sleep-wake`/`accessibility`）
  与 Chrome/VSCode 客户端矩阵：都需要**隔离身份包**（生产包会写真实学习词库，规则禁止合成打字），
  且 Chrome/VSCode 探针尚未编写。另 4 项结构性阻断（B 机 arm64、第三方复现、五日试用、微信草稿）。

## 4. 下一步

1. **Chrome 待外部修复**：三条因果已排除（隔离包身份、输入上下文陈旧、产品缺陷）。可试的下一步：Chrome 换稳定版/回退 155.0.8059.80，
   或用 Chrome 的「访达/终端里输入」对照；不影响产品验收结论（VSCode/Safari/TextEdit/Terminal 均正常）。
2. ~~VSCode 探针~~ ✅ 已完成（AX 不可用，改为自有文件 + ⌘S 读回）。
3. 报告 103 剩余 BLOCKED 全部是外部/结构性：`application-Chrome`（Chrome 侧）、`arm64-macos27`（B 机）、
   `independent-reproduction`（第三方）、`one-person-five-days`（5 日）、`application-WeChat`（策略）。
4. IT-12 剩余：**内嵌计时采样**仍受「宿主启动/接管时序」阻塞（重新登录后系统不再按需拉起；`open` 启动的宿主
   偶尔接客、多数不接；`launchctl setenv` 到不了 LaunchServices 进程）。钩子本身可用（ADR-218，唯一一次样本
   total 18.7/22.8/9.5 ms）。下一步选项：把宿主做成登录项、改「宿主自报样本到私有根」、或改在 B 机/CI 采集。
3. **B 机（arm64）**复验仍缺：需 B 上出 arm64 隔离包（CI `arch=arm64`）并按 ADR-130/131 重新登录后添加输入源。

## 5. 授权与边界

- 不自动注销/重启/解锁；TCC（辅助功能/自动化）由用户在系统设置点选，不绕过。
- 不热替换生产包；隔离包是独立身份，未动真实 config/词库，未启动生产宿主。
- 配置只经 `ime-config`；不写 `UserDefaults`/`com.apple.HIToolbox`。
- 验证语义（守卫、超时、判定）不得为了「跑通」而放宽；改守卫必须连带改测试并写报告。
- 失败即停、保留证据；不伪造 PASS；截图/口头确认不记为正式 PASS。
- 一轮只测一个包；每批发键前有焦点/身份守卫；中途失源即记 BLOCKED。

## 9. 会话日志

- 2026-10-20 / pi：重新登录后复测计时采样：系统不再按需拉起宿主、`launchctl setenv` 到不了 LaunchServices 进程、
  `open` 启动的宿主接客不稳定 → 卡点定位为「宿主启动/接管时序」，非钩子本身；已在 ADR-218 记录可选方案。
  环境已重建并还原（源 sogou、无标记/trace 残留、真实词库未变）。
- 2026-10-20 / pi：宿主级性能基线 PASS（新探针 `run-installed-perf-probe.py` + `ax-text-wait`）；报告 103 → pass 18 / blocked 5。
- 2026-10-20 / pi：无障碍 PASS（VoiceOver AX 面 + 焦点保持）；报告 103 → pass 17 / blocked 6。
- 2026-10-20 / pi：睡眠唤醒 PASS（新增 `run-installed-sleep-wake-probe.py`）；顺手把 TextEdit 探针的焦点守卫改成轮询到 AXTextArea，
  唤醒后不再误 BLOCK。报告 103 → pass 16 / blocked 7。
- 2026-10-20 / pi：长组合/撤销/模式循环在新候选复验 PASS（新探针），报告 103 升到 pass 15 / blocked 8。
- 2026-10-20 / pi：VSCode 探针完成（四路径 PASS，报告 103 的 `application-VSCode` 改判）；
  Chrome 结论修正为「页面文本框不使用任何输入法」（搜狗/生产/隔离三种源均复现，VSCode 正常）→ 记 BLOCKED（Chrome 侧）。
- 2026-10-20 / pi：**新候选 `f74aae7` 验收**（报告 103）：CI 包已下载复核（universal、公证、可执行 SHA `5cfb4c44…`）；
  12 次真机探针 + HUD 双屏/暗色探针 + 67 观测离屏全绿 → pass 11 / fail 0 / blocked 12。
  另新增 Chrome 探针（标题通道）；发现 Chrome 不把页面按键交给隔离输入法，需重启 Chrome 复测。
- 2026-10-20 / pi：真机面板探针（新增 `run-installed-hud-probe.py` + `hud-probe.swift` + 7 项契约测试）：
  发现 HUD 不显示 → 定位到 `disabled` 的 `.prohibited` 误判（诊断日志 `policy=1`），按 ADR-217 修复；
  修复后探针 PASS（双屏跟屏 + 亮暗 + 不夺焦点），`focus` 仍 FAIL（候选 07bbb2f 含缺陷，待新候选复验）。
- 2026-10-20 / pi：**隔离验收彻底收尾**：输入源回到 ABC、`disable-owned`、用户系统设置移除、`lsregister -u`+删包、删私有根；
  回读生产执行 SHA `681fb1c8…`/config `809e2cae…`/词库 `2ee1a469…` 与收尾前一致（报告 102 §6）。
- 2026-10-20 / pi：**隔离包三组 16/16 PASS**。Safari 根因是 Safari 18.6 不为 AppleScript 投递的 `file://` 授予沙箱扩展；
  经用户授权把 `owned-safari.applescript` 改成「AppleScript 建窗口 + LaunchServices 投递 + 新窗口差集守卫 + 只留 fixture 标签」
  （`b757c08`，新增 8 项静态契约测试），四场景全过；101 的 `application-Safari` 同步改判（pass 11 / blocked 12）。
- 2026-10-20 / pi：**重新登录后隔离源可用，TextEdit/Terminal 12 次探针全 PASS**。重建被清掉的私有根、重编译 helper；
  用户添加输入源后父源+模式皆启用，`-50` 消失；Safari 组因 Safari 18.6 拒绝 AppleScript 投递 `file://` 的沙箱扩展而 BLOCKED
  （`open -a` 可加载，修法待批准）；报告 102 §5–§7 补齐，101 的 `application-Terminal` 改判 PASS（pass 10 / blocked 13）。
- 2026-10-19 / pi：IT-14 前置出包并安装，停在重新登录前；`c60bd88` 让隔离公证 CI 支持 x86_64/universal 与任意系统临时根（ADR-216）。
- 2026-10-19 / pi：发布门禁中段：A 装 `07bbb2f`；097 所有权 / 098 数据根 / 099 真实 IMK / 100 独有身份注册 / 101 机器报告（pass=9 blocked=14）。
- 2026-10-19 / pi：HUD 收口（095/096）；ADR-214 修复（firstRect 优先 + attributes 兜底）。
- 2026-10-19 / pi：A 全新安装 `17053e1`（094），HUD D7/D8 记录后由 ADR-214 定夺。
