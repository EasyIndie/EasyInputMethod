# HANDOFF — 当前状态

## 0. 元信息

- 更新：2026-10-20 09:20 / pi（deepseek-flash）· 隔离验收已收尾（16/16）；**再修掉 A 的两个离线门禁缺陷**
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
- **报告 101 剩余 6 项 A 侧 BLOCKED**（`focus`/`light-dark-layout`/`multi-display`/`imk-performance`/`sleep-wake`/`accessibility`）
  与 Chrome/VSCode 客户端矩阵：都需要**隔离身份包**（生产包会写真实学习词库，规则禁止合成打字），
  且 Chrome/VSCode 探针尚未编写。另 4 项结构性阻断（B 机 arm64、第三方复现、五日试用、微信草稿）。

## 4. 下一步

1. **补 101 的 `focus` / `multi-display`**（不需要签名），把 BLOCKED 再减 2 项。
2. **IT-12 引擎/渲染基线**：`run-perf.sh`、`render_perf.swift`。
3. **B 机（arm64）**复验仍缺：需 B 上出 arm64 隔离包（CI `arch=arm64`）并按 ADR-130/131 重新登录后添加输入源。

## 5. 授权与边界

- 不自动注销/重启/解锁；TCC（辅助功能/自动化）由用户在系统设置点选，不绕过。
- 不热替换生产包；隔离包是独立身份，未动真实 config/词库，未启动生产宿主。
- 配置只经 `ime-config`；不写 `UserDefaults`/`com.apple.HIToolbox`。
- 验证语义（守卫、超时、判定）不得为了「跑通」而放宽；改守卫必须连带改测试并写报告。
- 失败即停、保留证据；不伪造 PASS；截图/口头确认不记为正式 PASS。
- 一轮只测一个包；每批发键前有焦点/身份守卫；中途失源即记 BLOCKED。

## 9. 会话日志

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
