# 095 — HUD 光标来源修复（ADR-214）：首轮真机测量与二次修正

2026-10-19。承接报告 094 的 D7/D12（用户确认：空文档有光标应显示、终端有光标应显示、Finder 无文本焦点不应显示）。

## 已装并实测的包

| 项 | 值 |
|---|---|
| 包 | `7f51687`（zip `f6f834c8…`、执行 `c38b1310…`、Notarized Developer ID） |
| 方式 | 重启后 `clean-install --input-source-removed --purge-data`；旧数据 → `uninstalled/data.aF2JSJ` |
| 该版实现 | HUD 光标**只**用 `firstRect(forCharacterRange:)`（ADR-214 第一版） |
| 证据 | `platforms/macos/build/acceptance-a-095/` |

## 真机测量（该版）

| 场景 | 结果 | 结论 |
|---|---|---|
| TextEdit 空文档（chars=0） | HUD 显示，(75,33) 96×36 | 空文档保留提示 ✔（用户预期） |
| TextEdit 文末光标 | HUD 显示，但底边距行顶 **13pt**（旧版 attributes 路径是 8pt） | `firstRect` 返回的是行片段矩形，比 `attributes` 的线高矩形高约 5pt → 位置不如旧版准 |
| Finder 前台（桌面，无文本焦点） | HUD **仍显示**（(64,644)） | **`firstRect` 在 Finder 桌面也返回有效矩形**，第一版规则对 D7 无效 |
| Terminal 有焦点光标（窗口被我先移到屏幕外） | HUD 在 (307,−753) | 位置与 Terminal 的真实光标一致（窗口确实在屏幕外）→ `firstRect` 在 Terminal 可用 |
| Terminal 在屏内、但 IME 尚未为该客户端激活 | HUD 跑到 (64,756) | 用的是**上一个应用的缓存客户端**（TextEdit 的插入点）→ 跨应用陈旧，需按前台应用校验 |
| Terminal 在屏内、已激活（输入过字） | HUD (275,329)，水平对准光标，垂直比光标行顶高 **26pt**（= 行高 18 + 设计间距 8） | 能显示，但偏移不是 8pt，属客户端矩形语义差异，需后续单独处理 |

## 由此确定的修正（已提交，待新包复验）

1. **`attributes` 优先、`firstRect` 兜底**：AppKit 文本视图位置准（8pt），终端只实现 `firstRect`，仍能显示。
2. **Finder 无文本不算光标**：`bundleIdentifier() == "com.apple.finder"` 且 `length()==0` 时直接不显示（重命名输入框 `length>0` 仍显示）。
3. **屏幕内校验**：光标中心必须落在某块屏内，否则不显示（避免把翻转/像素坐标的矩形换成屏外提示）。
4. **前台应用校验**：缓存客户端只在 `bundleIdentifier()` 等于前台应用时才使用，避免切换应用后提示跳到上一个应用的位置。

`StateHUDCaretResolver` 现签名：`resolve(startIndex:hasText:allowsEmptyCaret:lineRect:firstRect:)`。
A 机 Swift 5.8.1 下用同源 `Sources/*.swift` 编译的小程序逐条验证 **9/9 PASS**（空文档、终端 firstRect、Finder 伪光标、
Finder 重命名、空行回退、attributes 优先、都取不到、屏内接受、屏外拒绝），`candidate.hud-source` 断言同步更新。

## 仍需真机确认（下一轮）

| 场景 | 期望 |
|---|---|
| Terminal 有焦点光标 | **显示**；位置为光标上方（当前客户端语义下垂直偏移可能 > 8pt，需记录实际值） |
| Finder 前台 | **不显示** |
| TextEdit 空文档 | **显示**，且底边距行顶 8pt（attributes 路径） |
| TextEdit 文末/空行 | 显示，上方 8pt，空行回退最近字符 |
| 候选窗可见时切换状态 | 仍走内联芯片，不弹 HUD |

## 结论

第一版（只 `firstRect`）**不能**解决 D7（Finder 的 `firstRect` 也有效），还把 TextEdit 的位置精度从 8pt 降到 13pt；
二次修正（attributes 优先 + Finder 门禁 + 屏内校验 + 前台应用校验）已提交，等新签名包在 A 上复验。
Terminal 的垂直偏移（26pt）是客户端矩形语义差异，先如实记录，再决定是否做客户端特化。

## 095b — 二次修正真机复测（包 `888b8d1`，执行 `9c211948…`）

| 场景 | 结果 |
|---|---|
| TextEdit 空文档（窗口被恢复成屏外时） | HUD 跟着光标出现在屏外 (−1021) → 说明定位用的是真实光标；把窗口移回屏内后 HUD 正常出现 |
| TextEdit 有文本、光标在文末 | HUD 出现，但**底边距文字行顶 22pt**（094 的 attributes-only 构建是 8pt）→ 偏移回归，待诊断 |
| Finder 前台（桌面） | **仍出现** HUD（日志 `order window … op: 1`，截图差分命中）→ 说明 `client()` 取到的仍是上一个应用的客户端（我只给缓存加了前台校验） |
| Terminal | 本轮未复测（留给下一轮） |

### 已追加的修正

1. **前台应用校验覆盖两个来源**：`client()` 与 `activeClient` 都要求 `bundleIdentifier()` 等于前台应用（取不到 bundle 时才放行），彻底挡掉跨应用陈旧客户端。
2. **诊断开关**（默认关闭）：`launchctl setenv LAMPYRIS_HUD_DIAG 1` 后宿主把每次解析的 `line<i>`、`first<i>`、`pick` 写入 `$TMPDIR/lampyris-hud-diag.log`，用于下一轮定位 22pt 偏移到底来自哪条 API 与哪个矩形。

## 095c — 不注销换包后的复测（包 `08bcdf2`，执行 `a3a5a905…`，宿主开诊断）

安装走 `scripts/macos-fast-reinstall.sh`（不注销）：切换 ABC → 用户移除输入源 → 终止空闲孤儿宿主 → 装包 → 用户重新添加输入源。
旧包/旧数据 → `uninstalled/bundle.C9sYMm`、`uninstalled/data.Dl6Ddh`。

| 场景 | 结果 |
|---|---|
| Finder 前台（桌面，无文本焦点） | **不再显示 HUD** ✔（诊断无输出 → 前台校验把陈旧客户端挡在解析之前） |
| Terminal 有焦点光标 | **显示 HUD** ✔（`firstRect824={{123,175},{0,18}}`；截图像素差分在 (75,557)-(170,620) 命中面板+阴影；`CGWindowList.on` 仍误报 false） |
| TextEdit 文末光标 | 显示，但偏移仍在：诊断显示 `line11={{0,0},{0,0}}`（**末字符 attributes 返回零矩形**）、`first11={{246,652},{0,16}}`，于是选中了精度较差的 firstRect |

### 偏移的根因（诊断实证）

1. `attributes(forCharacterIndex:)` 在**文末/最后一个字符**返回零矩形（老代码靠“向前回退 64 字符”绕开；我上一版把回退与 firstRect 交替，导致在最后一个索引就直接退回 firstRect）。
2. firstRect 在**多显示器**下会按主屏高度翻转 y（本例窗口在 1080 高的副屏，返回的 y 却是 `800 - 148`），提示因此被夹到另一块屏上 → 视觉上“高了 20 多 pt”。

### 修正（第三次，待复验）

`StateHUDCaretResolver` 改成**两趟**：先把 `attributes` 沿回退走完（最多 64 个），一次都拿不到才用 `firstRect` 沿回退走。
这样文末/空行仍用 attributes（单屏 8pt、多屏也在同一坐标系），只有真正不实现 attributes 的终端才走 firstRect。
本地同源验证 **9/9 PASS**（新增“末字符 attributes 失效时先回退 attributes、不退回 firstRect”用例）。

## 095d — 两趟解析真机复验（包 `c5c8b4a`，执行 `2e072ddb…`，不注销换包）

安装：用户移除输入源 → `make macos-fast-reinstall … ARGS=--stop-host` → 用户添加输入源（全程未注销、未重启）。
旧数据 → `uninstalled/data.RyS0Lt`。宿主开 `LAMPYRIS_HUD_DIAG=1`，验收后 `unsetenv`。

| 场景 | 结果 | 证据 |
|---|---|---|
| **Finder 前台（无文本焦点）** | **不显示 HUD** ✔（最近 6 秒 `order window … op: 1` 计 0；诊断无输出=前台校验在解析前挡掉） | `05-finder.txt` |
| **Terminal 有焦点光标** | **显示 HUD** ✔：诊断 `pick … first256={{123,409},{0,18}}`，截图像素差分命中面板 (75,321) 96×36，底边距光标行约 16pt | `06-terminal.txt`、`term-on/off.png` |
| **TextEdit 文末光标** | **显示且回到 8pt** ✔：诊断 `line5..1={{0,0},{0,0}}`（attributes 在文末仍返回零矩形）→ 回退到 `line0={{191,639},{1,13}}` 命中 attributes，**没有**退回 firstRect；截图面板底边 140、文字行顶 148 → **8pt** | `03-hud-textedit.txt`、`on/off.png` |
| TextEdit 空文档 | 显示 ✔ `line0={{125,639},{1,13}}`，同样 8pt | `04-hud-empty.txt`、`empty-on/off.png` |
| 候选窗可见时切状态 | 走内联芯片 ✔（最近 5 秒 HUD 上屏 0 次，候选窗仍在） | `07-inline-chip.txt` |
| 还原 | 输入源 ABC、`config` SHA `15f49acf…`（mixed/中文标点/简体/半角）、宿主 23275、执行 SHA `2e072ddb…`、诊断 env 已清 | `08-restore.txt` |

### 结论

- D7（Finder 无文本焦点误显示）：**已修复并真机确认**（前台应用校验 + Finder 无文本门禁）。
- D12（终端有焦点不显示）：**已修复并真机确认**（`attributes` 两趟走完再退 `firstRect`）。
- TextEdit 的 22pt 偏移：**已修复并真机确认 8pt**（根因是“末字符 attributes 返回零矩形”时提前退回 firstRect；两趟解析消除了它）。
- 输入源自动化：`TISEnableInputSource` / `TISDisableInputSource` 都返回 0 但**不生效**，添加/移除仍需用户在系统设置各点一次；
  其余步骤已由 `make macos-fast-reinstall` + `tissrc` + `.agents/skills/iterate-macos-ime` 固化。

### 仍保留的客户端差异

- Terminal 的 HUD 垂直偏移约 16pt（`firstRect` 给的行高矩形语义与 AppKit 的线高矩形不同），不影响“在光标上方”的可读性；
  要压到 8pt 需要按客户端特化，暂不做（记录为已知差异）。
