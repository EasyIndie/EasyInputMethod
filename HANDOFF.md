# HANDOFF — 当前状态

## 0. 元信息

- 更新：2026-10-20 / Codex（GPT-6）；B 机验收进行中，报告 104。
- 分支：main 基线 `6ed5da1`；TextEdit 探针修复（ADR-219）待提交，候选将重新锁定。
- 阶段：A 报告 103 保留；B 尚未安装隔离包或发键，私有根与 helper 已建。
- 最近验证：B `make verify` 全绿（182 产物隐私检查），TextEdit 专项 9 例通过；沙箱外离线 40 文件/174 例仅矩阵旧文案断言失败，修后该文件 7 例通过，远端全量待跑。

## 1. 安装与数据

| 设备 | 系统 | 已装包 | 状态 |
|---|---|---|---|
| A（`bot`，Intel / macOS 13.7.8） | x86_64 | 生产 `07bbb2f`（执行 `681fb1c8…`，Notarized Developer ID） | 宿主 21703 运行中；真实 `config.toml` `809e2cae…`、词库 `2ee1a469…`（217 行）全程未变；输入源已由用户加回 **生产「萤火虫」**（`cn.jokerhub.inputmethod.Lampyris.default`） |
| A（同上） | x86_64 | ~~隔离测试包~~ | **已彻底移除（2026-10-20 15:40）**：`disable-owned` → 用户系统设置移除 → `lsregister -u` + 删实体包 + 删私有根；`~/Library/Input Methods` 只剩生产 `Lampyris.app`（公证，`spctl accepted`）。⚠️ 用户移除时**把生产「萤火虫」输入源也一起移除了**（TIS 现只剩 ABC/搜狗）；需要时在系统设置重新添加即可，包未动 |
| B（`joker`，arm64 / macOS 27.0.1） | arm64 | 生产 `17053e1`（执行 `535d546f9de1…`，Developer ID / accepted） | 原源 `com.sogou.inputmethod.sogou.pinyin`；宿主基线 17339；config `3bc1117cc337…`（8 显式快捷键），词库 `74f76e92a6ca…`（29 行）；报告 104 待验，真实数据未改 |

- 隔离包本机前置（一次性，已由用户授权）：**Ghostty 需「辅助功能」**（否则 `osascript` `-1728`）+
  **「自动化」允许控制 System Events / TextEdit / Safari / Terminal**（否则 AppleEvent `-1712`）。
- 未设置 `LAMPYRIS_SUPPORT_DIR`；隔离包把 config/词库写在私有根内；真实数据 12 次探针均 `realDataUnchanged=true`。

## 2. 本轮完成（2026-10-20）

| 内容 | 结果 | 报告/ADR |
|---|---|---|
| **HUD 缺陷修复** | 根因：`disabled` 把宿主恒有的 `.prohibited` 当测试判据 → HUD 从不创建 | ADR-217、102 §9 |
| 新候选 `f74aae7` 验收 | **pass 18 / fail 0 / blocked 5**；`focus`/`multi-display`/`light-dark-layout`/`long-composition`/`undo`/`mode-switch`/`sleep-wake`/`accessibility`/`application-VSCode` 转 PASS | 103 |
| 新探针 + 契约测试 | HUD/面板、Chrome（标题通道）、VS Code、睡眠唤醒、VoiceOver AX 面、IT-12 矩阵、内嵌计时 | 103 证据、ADR-218 |
| A 离线门禁解阻 | Swift 5.8 兼容 + 编码声明 + 过期用例表 → `macos-offline-tests` 122 例、`local-acceptance` 67 观测全绿 | 102 §8 |
| 宿主内性能 | 按键→候选 p50 14.1–14.9 ms／p95 20.6–23.5 ms；引擎 p50 1.0 ms；面板 42/165 ms | 103、IT-12 卡 |

## 3. 当前未决

- B 出包前置：`6ed5da1` 正式 CI 39384028937 被 TextEdit 离线 mock/中断锚点失效阻断；ADR-219 修复专项通过、待提交与远端完整复核。报告 104 不继承 103 的 PASS。

- 报告 103 剩余 5 项 BLOCKED，全部外部/结构性：`application-Chrome`（Chrome 155 页面不接受任何输入法，
  搜狗/生产/隔离三向对照已证）、`arm64-macos27`（B 机）、`independent-reproduction`（第三方）、
  `one-person-five-days`（待 RC 锁定后开始 5 工作日）、`application-WeChat`（策略）。
- **端到端 p95 超标**：引擎 1.0 ms 达标，但「按键→候选可见」p95 20–24 ms > §12 的 16 ms；是否立项优化待定（先写 ADR）。
- **采样会话敏感**：同一会话反复 `pkill` 宿主后系统会停止按需拉起/接管；采样需在新登录会话按
  `run-installed-perf-trace.sh` 的顺序做（ADR-218）。
- IT-12 未覆盖：B 机复采、合成器完成/VoiceOver 路径、满词库下的长时稳定性。
- 隔离验收已完全收尾；`~/Library/Input Methods` 只剩生产 `Lampyris.app`（公证）。

## 4. 下一步

0. **B 当前断点**：完成 ADR-219 完整离线回归与提交；重新锁定 main，分别运行 `macos-acceptance.yml` 与 `isolated-imk-notary.yml`（arch=arm64）。私有根为 `/private/var/folders/z0/1h35x82j7d767_fm_x3tvdsh0000gn/T/lampyris-imk-3b030dda-b3f5-4424-a45c-90c5cfabfbf7`；初次隔离 run 39395207876 仅作旧提交构建记录，未安装。三个 helper 已在根内编译，旧提交隔离 run 已成功但不安装；性能脚本存在绕过自有窗口守卫的直接发键路径，修复前不运行（104）；需在安装后采登录时实际原源并写 0600 selection journal。详细基线与边界见报告 104。

1. **决定 p95 超标是否立项**：先写 ADR（是否把「按键→候选可见」纳入门禁、目标值与测量口径），再决定是否优化 IMK 回写路径。
2. **B 机复采**：CI 出 arm64 隔离包 → 按 ADR-218 流程采 `run-installed-perf-trace.sh` + 矩阵，补齐 `arm64-macos27`。
3. **锁定 RC 后**：安装生产包做最终实机验收（点击/VoiceOver/多屏/客户端）并开始 IT-23 的 5 个工作日。
4. **Chrome**：等 Chrome 侧修复/换版本后用 `run-installed-chrome-probe.py` 复测，再改判。

## 5. 授权与边界

- 不自动注销/重启/解锁；TCC（辅助功能/自动化）由用户在系统设置点选，不绕过。
- 不热替换生产包；隔离包是独立身份，未动真实 config/词库，未启动生产宿主。
- 配置只经 `ime-config`；不写 `UserDefaults`/`com.apple.HIToolbox`。
- 验证语义（守卫、超时、判定）不得为了「跑通」而放宽；改守卫必须连带改测试并写报告。
- 失败即停、保留证据；不伪造 PASS；截图/口头确认不记为正式 PASS。
- 一轮只测一个包；每批发键前有焦点/身份守卫；中途失源即记 BLOCKED。

## 9. 会话日志

- 2026-10-20 / Codex：B 基线已采（macOS 27.0.1 / arm64，生产执行 `535d546f9de1…`、config 8 显式快捷键、词库 29 行、原源搜狗拼音）；未换包/发键。定位正式 CI 的 TextEdit mock 超时及中断锚点失效，ADR-219 最小修复专项 9 例通过；make verify 全绿。报告 104 进行中，矩阵旧文案断言同步修复；远端完整复核后重新锁候选。

- 2026-10-20 / pi：**会话收尾**。修 HUD 缺陷（ADR-217）并出新候选 `f74aae7`，报告 103 = pass 18 / blocked 5
  （`focus`/`multi-display`/`light-dark-layout`/`long-composition`/`undo`/`mode-switch`/`sleep-wake`/`accessibility`/VSCode 转 PASS）；
  新增 7 个探针+契约测试并打通内嵌计时（ADR-218：按键→候选 p50 14.1–14.9 ms、p95 20.6–23.5 ms，引擎 1.0 ms）；
  A 离线门禁首次全绿（122 例/67 观测）；隔离包/私有根/本地产物已清理，生产数据与宿主全程未变。
- 2026-10-20 / pi：内嵌计时打通并采到 n=45（total p50 14.1–14.9 ms / p95 20.6–23.5 ms；engine 1.0 ms；面板 42/165 ms），
  写入报告 103 与 ADR-218；同时确认 ad-hoc 构建被 Gatekeeper 拦截、必须用 CI 公证包采样。
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
