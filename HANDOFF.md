# HANDOFF — 当前状态

## 0. 元信息

- 更新：2026-10-20 08:00 / pi（deepseek-flash）· **重新登录后隔离源可用；TextEdit/Terminal 四路径 12/12 PASS，
  Safari 组因 Safari 18.6 沙箱扩展被拒而 BLOCKED（非输入法缺陷）**
- 分支：`main` @ `91813dd`（本轮为文档提交）
- 阶段：A 生产包 `07bbb2f`（执行 `681fb1c8…`，宿主重启后**未启动**）；报告 102 已补实测结果；
  报告 101 机器报告由 pass 9 / blocked 14 → **pass 10 / blocked 13**
- 最近验证：`make verify` 全绿（`91813dd`）；隔离公证 CI run `39269308347` success

## 1. 安装与数据

| 设备 | 系统 | 已装包 | 状态 |
|---|---|---|---|
| A（`bot`，Intel / macOS 13.7.8） | x86_64 | 生产 `07bbb2f`（执行 `681fb1c8…`，Notarized Developer ID） | 宿主**未运行**（10-20 07:37 重启后未启动）；真实 `config.toml` `809e2cae…`（19 日 20:45 后未变）、词库 `2ee1a469…`（20 日 07:17，用户自己打字学词，不是本轮写入）；输入源当前 `com.apple.keylayout.ABC`（探针还原值，用户可切回 sogou） |
| A（同上） | x86_64 | **隔离测试包** `cn.jokerhub.inputmethod.LampyrisIMKTest.fd15c596-…`（CI run `39269308347`，commit `c60bd88`，zip `d14a395b…`） | **已安装且可用**：私有根 `/private/var/folders/x7/hhbm75rn6vz_37yjj5rsq9yc0000gn/T/lampyris-imk-fd15c596-…`（重启后被清，已按 ADR-131 同路径重建空根）；`source-state` 已重编译；父源 + `.default` 均 `enabled=true`（用户在系统设置添加后） |
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
| `run-installed-safari-probe.py` × 4 场景 | **0/4 BLOCKED**（Safari 沙箱扩展，见 §3） | 102 §5.3 |
| 报告 101 改判 | `application-Terminal` BLOCKED→PASS（pass 10 / blocked 13） | 102 §7 |

## 3. 当前未决

- **Safari 组解阻（需批准的工具改动）**：`owned-safari.applescript` 的 create 用
  `make new document with properties {URL: file://…}`，Safari 18.6 拒绝授予沙箱扩展
  （`failed to obtain sandbox extension: (null)`，WebKit `code=-1202`），窗口为空 → 守卫按设计 BLOCK。
  对照实验：`open -a Safari <同一 file:// URL>` 能加载。修法＝改用 LaunchServices 投递并同步改测试
  （「独有窗口」判定要换成「新增窗口差集」），**属验证工具语义变更，本轮未擅自实施**。
- **现场未清理**（等用户确认归属）：Safari 2 个测试窗口（`safari-fixture-qc3zc5jm`、一个「未命名」空白）、
  TextEdit 1 个「未命名」文档（无路径）、`platforms/macos/build/installed-*`、私有根内 `safari-diag.*`。
- **隔离包暂不卸载**：留着补跑 Safari 组，避免再经历一次「新装输入法需重新登录」（ADR-130/131）。
- **IT-01 剩余**：微信聊天隔离草稿（BLOCKED）、完整剪贴板多类型恢复（仅命名剪贴板 + mock 证据）。
- **IT-12/IT-15/IT-23**、**IT-03 其余 13 项 BLOCKED**：未开始。
- **A 工具链差异**：`make macos-offline-tests` 在 A 必红（Swift 5.8.1 + 高负载 `swiftc` 超时）；Swift 侧门禁以 CI 为准。
  单文件 `swiftc` 实测 1m12s，命令超时别给 300s 以下。

## 4. 下一步

1. **Safari 解阻**（推荐先做，成本小）：改 create 走 `open -a Safari`，用「前一窗口 ID 集合的差集」定位新窗口，
   保留 URL/标题/焦点三重校验；补 `test-installed-*` 相应用例 → `make verify` → 重跑 4 场景 → 报告 102 补录。
2. **清理现场**：用户确认后关掉上述窗口/文档，删除 `build/installed-*` 与 `safari-diag.*`，
   回读生产执行 SHA / config / 词库摘要。
3. 或先做不依赖 Safari 的：补测 101 的 `focus` / `multi-display`（不需签名），再采 IT-12 引擎/渲染基线
   （`run-perf.sh`、`render_perf.swift`）。
4. 全部收尾后：`source-state disable-owned` → 用户移除输入源 → `lsregister -u` + 删实体包 → 删私有根。

## 5. 授权与边界

- 不自动注销/重启/解锁；TCC（辅助功能/自动化）由用户在系统设置点选，不绕过。
- 不热替换生产包；隔离包是独立身份，未动真实 config/词库，未启动生产宿主。
- 配置只经 `ime-config`；不写 `UserDefaults`/`com.apple.HIToolbox`。
- 验证语义（守卫、超时、判定）不得为了「跑通」而放宽；改守卫必须连带改测试并写报告。
- 失败即停、保留证据；不伪造 PASS；截图/口头确认不记为正式 PASS。
- 一轮只测一个包；每批发键前有焦点/身份守卫；中途失源即记 BLOCKED。

## 9. 会话日志

- 2026-10-20 / pi：**重新登录后隔离源可用，TextEdit/Terminal 12 次探针全 PASS**。重建被清掉的私有根、重编译 helper；
  用户添加输入源后父源+模式皆启用，`-50` 消失；Safari 组因 Safari 18.6 拒绝 AppleScript 投递 `file://` 的沙箱扩展而 BLOCKED
  （`open -a` 可加载，修法待批准）；报告 102 §5–§7 补齐，101 的 `application-Terminal` 改判 PASS（pass 10 / blocked 13）。
- 2026-10-19 / pi：IT-14 前置出包并安装，停在重新登录前；`c60bd88` 让隔离公证 CI 支持 x86_64/universal 与任意系统临时根（ADR-216）。
- 2026-10-19 / pi：发布门禁中段：A 装 `07bbb2f`；097 所有权 / 098 数据根 / 099 真实 IMK / 100 独有身份注册 / 101 机器报告（pass=9 blocked=14）。
- 2026-10-19 / pi：HUD 收口（095/096）；ADR-214 修复（firstRect 优先 + attributes 兜底）。
- 2026-10-19 / pi：A 全新安装 `17053e1`（094），HUD D7/D8 记录后由 ADR-214 定夺。
