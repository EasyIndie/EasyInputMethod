# 096 — Finder 搜索框获焦时 HUD 不显示（报告 095 的回归）

2026-10-19，用户实测：**Finder 打开后，搜索框获焦，切换状态时没有 HUD**。

## 根因

报告 095 为了修 D7（Finder 桌面误显示），用了「`bundleIdentifier() == "com.apple.finder"` 且 `length()==0` 就不显示」的一刀切规则。
Finder 的**搜索框也是 Finder 的文本客户端**，且空搜索框 `length()==0` → 被这条规则误杀。

## 实测（包 `85358b2`，窗口层假设被推翻）

| 场景 | `windowLevel()` | `length()` | attributes 矩形 |
|---|---|---|---|
| Finder 桌面获焦 | **19** | 0 | `{{61,84},{1,14}}`（伪光标） |
| Finder 搜索框获焦（空） | **19** | 0 | `{{956,548},{1,16}}`（搜索框里的真光标） |

两者窗口层相同 → “按窗口层区分”的假设不成立（仍然误显示/不显示）。

再查 `CGWindowList`：桌面伪光标中心只落在 Finder 的**桌面层窗口**（layer `-2147483603`）里；
搜索框光标落在 Finder 的**普通窗口**（layer 0，261,217,920×436）里。

## 修法（ADR-214 修订，最终）

**光标中心必须落在前台应用的普通窗口（层号 ≥ 0）内**，否则不显示：

- Finder 桌面/图标视图（伪光标只落在桌面层窗口）→ 不显示；
- Finder 搜索框、TextEdit、终端（普通窗口）→ 显示；
- 取不到窗口信息时放行，避免误杀；仍保留「客户端属于前台应用」「屏内」「attributes 两趟」三条。



用**窗口层**区分“桌面伪光标”和“真输入框”：

- `client.windowLevel() < 0` → 桌面/图标视图这类桌面层窗口，`length()==0` 时不算有效光标（不显示）；
- `windowLevel() >= 0`（普通窗口：Finder 搜索框、TextEdit、终端…）→ 空内容也允许显示。

同时保留：客户端必须属于前台应用、光标中心必须在屏内、`attributes` 两趟回退后再退 `firstRect`。
诊断日志新增 `level=` 字段，便于真机核对。

## 验收清单（待新包）

| 场景 | 期望 |
|---|---|
| Finder 桌面获焦（点桌面空白处） | 不显示 HUD |
| **Finder 搜索框获焦（空）** | **显示 HUD** |
| Finder 搜索框有文字 | 显示 HUD |
| TextEdit 空文档 / 文末 | 显示，上方 8pt |
| Terminal 有焦点光标 | 显示 |

## 096c 真机复验（包 `a278d70`，执行 `0198bda1…`，不注销换包）

安装：`make macos-fast-reinstall … ARGS=--stop-host` → 旧数据 `uninstalled/data.pyhmfo` → 用户加回输入源。诊断 `LAMPYRIS_HUD_DIAG=1`，验完 `unsetenv`。

| 场景 | 结果 | 证据 |
|---|---|---|
| **Finder 桌面获焦** | **不显示** ✔ 诊断 `pick … rect={{61,84},{1,14}}` → `drop: caret not inside app window`，5 秒内 HUD 上屏 0 次 | `03-finder-desktop.txt` |
| **Finder 搜索框获焦（空）** | **显示** ✔ `pick … rect={{860,1742},{1,16}}`（未 drop），HUD 上屏 1 次 | `04-finder-search.txt` |
| **TextEdit 文末** | **显示且 8pt** ✔ 诊断回退到 `line0={{191,639},{1,13}}`（attributes，未退 firstRect）；`hudcg` HUD (143,104) 96×36，面板底 140 / 行顶 148 | `05-textedit.txt`、`te-on2/off2.png` |
| TextEdit 空文档 | 显示 ✔ `line0={{125,639},{1,13}}`，HUD (77,104) | `06-textedit-empty.txt` |
| **Terminal** | 显示 ✔ `pick … first256={{123,409},{0,18}}`，HUD (75,329)，截图差分命中 | `07-terminal.txt`、`term-on/off.png` |
| 还原 | 输入源 ABC、config `15f49acf…`（mixed/中文标点/简体/半角）、宿主 76119、执行 `0198bda1…`、诊断 env 已清、宿主窗口 0 | `08-restore.txt` |

### 中途修正记录（同一提交链）

1. `85358b2` 试图用 `windowLevel()` 区分 Finder 桌面/搜索框 → **实测两者都是 19**，无效。
2. `5d762d4` 改为「光标中心须落在前台应用普通窗口（层号 ≥0）内」→ Finder 两条都对了，但 **TextEdit 被误 drop**：
   主屏高度取了 `NSScreen.screens.first`，本机它不是零点屏（1280×800 + 1920×1080 双屏）。
3. `a278d70` 修：主屏高度取**原点 (0,0) 的屏**；并**fail-open**（看不到该应用常规窗口时放行）。→ 四条全部通过（上表）。

### 结论

- Finder 桌面（伪光标）与 Finder 搜索框（真输入框）**都能正确区分**，且不依赖任何应用名/bundle id。
- TextEdit 文末恢复到 8pt；空文档、Terminal 均正常。
- 已知残余：Terminal 的垂直间距约 16pt（`firstRect` 语义差异），不影响可读，暂不特化。
