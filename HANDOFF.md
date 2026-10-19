# HANDOFF — 当前状态

## 0. 元信息

- 更新：2026-10-19 11:20 / pi（deepseek-flash）· **HUD 二次修正完成（报告 095），等新包 + 一次注销复验**
- 分支：`main` @ `bc0347e`（本轮末尾另提交报告 094）
- 阶段：A 现装 `7f51687`（执行 `c38b1310…`，首版 HUD 修复）；报告 095 实测后已二次修正（attributes 优先 + Finder 门禁 + 屏内校验 + 前台应用校验），等 CI 出包复验
- 最近验证：`make verify` 全绿（212 产物）；A 的 D2/D3 （设置首开分区、关于瞬时不出窗）本轮均未复现

## 1. 安装与数据

| 设备 | 系统 | 已装包 | 状态 |
|---|---|---|---|
| A（`bot`，Intel / macOS 13.7.8） | x86_64 | `17053e1`（`535d546f…`） | 报告 094；`--purge-data` 全新安装，旧包/旧数据在 `uninstalled/bundle.PuMacz`、`uninstalled/data.xLySk8`；`config` SHA `3bc1117c…`（全模板、`mode=mixed`、`alt+f`、零 `ctrl+shift`）、词库 5 行、输入源 ABC、宿主 6164 |
| B（`joker`，arm64 / macOS 27） | arm64 | `17053e1`（`535d546f…`） | 报告 093：UI 验收通过；`config` SHA `3bc1117c…`（`mode=mixed`、`alt+f`、显式 hotkey 8 项）、词库 17 行、输入源 ABC、宿主 17339 |

- B 最终包：`packaging/out/header-type/candidate-bZTrDz/`（zip `02b70dfd…`、执行 `535d546f…`、Notarized Developer ID）。
- A 取包：`gh run download 39135852935 -n Lampyris-macos-acceptance-17053e1e914b258d814e085f59a8460c0853179e`。
- 输入源经验：安装后必须在「系统设置 → 键盘 → 文字输入」添加（`TISEnableInputSource` 返回 0 不生效）；`selsrc` 只选中已启用源。

## 2. 本轮完成（新 UI 收尾）

| 提交 | 内容 | 报告 |
|---|---|---|
| `fba09ba` | 全/半角默认 `⌥Space` → `⌥F`（ADR-210） | 079 |
| `99c9841`…`ae84601` | 状态 HUD + 候选内联两字芯片 + 光标跟随/可见性修复（ADR-211/213） | 080–087 |
| `1932c69` | pinyin-data 固定到 commit `923b108d`（Unicode 17.0.0），修 CI SHA 漂移 | 090 |
| `60a3751`…`ba767ac` | 候选头部中心线对齐、翻页光学上提 1.5pt | 088/089/091 |
| `17053e1` | 头部字号统一 12pt、芯片高 20/留白 12、候选悬停 6/2pt | 092/093 |
| `f842262` | 记录用户 UI 验收通过 | — |

## 3. 当前未决

- **HUD（报告 094 D7/D12 → 095 二次修正，待复验）**：
  - 已实测：`firstRect` 在 Finder 桌面**也有效**（换 API 治不了 D7）；TextEdit 用 `firstRect` 底边距行顶 13pt（attributes 为 8pt）；Terminal 的 `firstRect` 可用但垂直高 26pt（行高 18 + 8）；跨应用时缓存客户端会把 HUD 放到上一个应用。
  - 已改（ADR-214 v2）：`attributes` 优先、`firstRect` 兜底；Finder 且 `length()==0` 不显示；光标中心必须在屏内；缓存客户端只在 `bundleIdentifier()` 等于前台应用时使用。本地同源 9/9 PASS。
  - 待验：Terminal 应显示（实际偏移待测）、Finder 不应显示、TextEdit 空文档应显示且 8pt。
- **A 机平台差异已清**：D2（设置首开分区）与 D3（关于瞬时不出窗）本轮均未复现；新记 D9（面板 531×70 vs B 538×70 字体度量）、D10（⇧ 合成事件成对）、D11（HUD 不在 AX 树内）。
- **终端 Meta 冲突**：裸 `⌥+字母` 与 zsh/readline 的 `M-f/M-b/M-d/M-t/M-l/M-p/M-m/M-a/M-,` 重叠；改 `⌃⌥`（VO 冲突）或英文模式让位，待用户决定。
- **发布门禁**：I1 已完成；I0（IT-01/03）、I2（IT-10/11、16…22）、I3（IT-12/23）、I4（IT-13…15）未关闭。IT-13 对 `17053e1` 的 dry-run 已通过。
- **A 平台差异**：macOS 13 的设置默认分区（D2）与关于窗口瞬时不出（D3）需在 A 复验。
- **IT-12 真实性能/IT-23 五日试用**：需先完成 IT-01 隔离验收再采真实 IMK 证据。
- **TCC 副作用**：排查截图时执行过 `tccutil reset ScreenCapture`，各应用录屏授权可能需重新勾选。

## 4. 下一步

### 4.1 A 机全新安装 + 验收 — ✅ 已完成（报告 094）

安装：重启后用 `clean-install --input-source-removed --purge-data`，旧包/旧数据进 `uninstalled/`；
执行 SHA `535d546f…`；用户在系统设置添加「萤火虫」后 `selsrc` 选中；验收后输入源还原 ABC。
结果：a–g、i、j 全 PASS；h 只有「无焦点」「空文档」两项仍弹 HUD（D7/D8）。

### 4.2 下一步（按优先级）

1. **HUD 复验（报告 095）— 等 CI 对二次修正出包 + 一次注销**
   - 已装的是第一版 `7f51687`（执行 `c38b1310…`），其 HUD 规则已被证明不够（报告 095）；
   - 新包：等 CI 对 `attributes 优先 + Finder 门禁` 的提交出 `Lampyris-macos-acceptance-*` 产物后，
     用 `gh run download <run> -n <artifact> -D packaging/out/a-095b` 取包并核对 zip/执行 SHA；
   - 用户动作：切 ABC → 系统设置移除「萤火虫」→ 注销/重启（**会终止 agent 会话**）→ 开 pi 说「继续 095」
   - 登录后：
     ```sh
     make macos-clean-install APP=packaging/out/a-7f51687/candidate-ocC9YU/extracted/Lampyris-0.1.0-universal/Lampyris.app ARGS=--input-source-removed
     ```
     然后在系统设置添加「萤火虫」+ `selsrc`
   - 必验 5 条：①Terminal 有光标 → **应显示**；②Finder 前台 → **不应显示**；③TextEdit 空文档 → **应显示**；
     ④TextEdit 有文本/空行回退 → 应显示且上方 8pt；⑤候选窗可见时仍走内联芯片（不弹 HUD）
   - 判定失败时抓宿主日志（`log show --predicate 'process == "Lampyris"'`），看 `Get attributes for character` 次数与
     `order window … op: 1` 是否出现
2. 发布门禁：**IT-01 隔离验收 → IT-03 正式逐项报告 → IT-12 性能 → IT-14/15 → tag/Release**。
3. IT-01 只使用隔离测试应用，不碰真实文档。

### 4.2 发布门禁

顺序：**IT-01 隔离验收 → IT-03 正式逐项报告 → IT-12 性能 → IT-14/15 → tag/Release**。
下一步可先做 IT-01 的原生多应用所有权/AX/剪贴板/输入源恢复隔离验证（只用隔离测试应用，不碰真实文档）。

## 5. 授权与边界

- 不自动注销/重启/解锁；重启由用户执行。安装替换前必须切 ABC、移除输入源、宿主退出；禁止热替换。
- 配置只经 `ime-config`；不手改 `config.toml`、不写 `UserDefaults`；`--purge-data` 只移出、不删除。
- 不操作用户真实文档/聊天；失败即停并保留证据；截图/口头确认不记为正式 PASS。
- 一轮只测一个包；探针遵守 `tools/macos-probe/README.md`。
- 本轮经验：源未移除但宿主已停时可「移除源 → 终止孤儿宿主 → 安装 → 重新添加」，不等同热替换；TCC 改动需告知用户。

## 9. 会话日志

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
