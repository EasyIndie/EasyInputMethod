# 075 — 默认快捷键改为 Option（⌥）语义前缀

2026-10-18。用户提出「用 Option/Alt 表示开关/选项，让快捷键与功能语义对应，同时避免与系统及其它应用冲突」。本轮把 8 项默认值从前缀 `ctrl+shift` 改为 `⌥ + 语义首字母`（ADR-209）。**未装包**。

## 决定

| 动作 | 旧默认 | 新默认 | 语义 | 布局产物（ABC/US） |
|---|---|---|---|---|
| 切换输入模式 | `ctrl+shift+m` | **`alt+m`** | Mode | µ |
| 中英切换 | `shift` | `shift`（不变） | 主流单 Shift | — |
| 全/半角 | `ctrl+shift+space` | **`alt+space`** | Width | NBSP |
| 中英标点 | `ctrl+shift+.` | **`alt+p`** | Punctuation | π |
| 简/繁 | `ctrl+shift+t` | **`alt+t`** | Traditional | † |
| 显示/隐藏学习区 | `ctrl+shift+l` | **`alt+l`** | Learning | ¬ |
| 打开设置 | `ctrl+,` | **`alt+,`** | Settings | ≤ |
| 关于 | `ctrl+shift+a` | **`alt+a`** | About | å |

菜单右侧提示、设置页快捷键按钮都由同一份 Schema 渲染成 `⌥M` / `⌥空格` / `⌥,` 等；`none`/空仍表示关闭，冲突检测（ADR-093）不变。

## 冲突分析（实测）

### 系统快捷键

`defaults read com.apple.symbolichotkeys`：已启用的 39 条系统符号快捷键中，含 ⌥ 的共 9 条，**全部带 ⌘ 或 ⌃**：

| 组合 | 用途 |
|---|---|
| `⌃⌥Space` | （系统项，本轮不使用 ⌃⌥） |
| `⌃⌥⌘8` | 缩放 |
| `⌘⌥D` / `⌘⌥F5`… | Dock/辅助 |
| `⌥F1/F2` | 亮度 |

→ **没有任何「仅 ⌥ + 字母」的系统快捷键**；`⌘Space`（Spotlight）与 `⌃Space`（切换输入法）都不被新默认占用，`alt+space` 因此彻底避开报告 074 的 `⌃Space` 冲突。VoiceOver 的 VO 键是 `⌃⌥`，本轮也不使用。

### Option 符号与死键（ABC/US 布局实测，`UCKeyTranslate`）

| 键 | ⌥ 产物 | 键 | ⌥ 产物 |
|---|---|---|---|
| M | µ | T | † |
| W | ∑ | P | π |
| L | ¬ | A | å |
| , | ≤ | . | ≥ |
| Space | NBSP | **E/N/U/I** | **死键**（´ ˜ ¨ ˆ） |

选中的 8 个键都不是死键；`⌥E/N/U/I` 会破坏输入 é/ñ/ü/î 的能力，ADR 里明确禁止绑定（本轮未使用）。代价是绑定后这些符号（µ † π ¬ å ≤ NBSP ≥）在输入法激活时不可输入，已在 ADR 记为取舍。

### 其它应用（无法枚举，按已知惯例规避）

- **Terminal/readline 的 Meta 绑定**：`M-t`（交换词）、`M-l`、`M-a`、`M-.` 等会让位；`M-w`/`M-b`/`M-f`/`M-d` 未绑定，保持可用。
- **编辑器**：VS Code `⌥Z`（自动换行）、`⌥↑/↓`（移动行）等未绑定。
- **不碰 `⌘` 与 `⌃⌥`**：系统与应用快捷键最密集的两个区域。

## 改动

- `crates/ime-config/src/schema.rs`：8 项默认值 + 中文说明（写明为何不用 `⌃Space`、`⌥.`、死键）。
- `crates/ime-config/src/lib.rs`：默认值/冲突单测改用 `alt+space`、`alt+l`。
- 菜单与设置：`controller-menu.swift`、`preview-menu.swift`、`settings-presentation.swift` 的 keyEquivalent/标题期望改为 `⌥`。
- 宿主自测 `platforms/macos/Preview/main.swift`：改按 `⌥M`/`⌥P`/`⌥T`/`⌥Space`；锁配置文件用例改为按新默认触发。
- 学习区快捷键用例 `wubi-learning.swift`：默认 `alt+l`、宽度 `alt+space`、冲突用例 `alt+m`。
- 文档：`docs/配置架构.md` 默认值表、`docs/决策记录.md` ADR-209。

## 验证

- `cargo test --workspace` 全绿（含 ime-config 默认值/冲突/别名）。
- 离屏探针（真实 FFI + 合成 `NSEvent`）逐项核对：
  - 8 项默认值 = `alt+*`（中英仍 `shift`）；
  - 每项 `ConfiguredHotkey.modifiers == [.option]`、`equivalent` 正确（空格为 `" "`）；
  - 每项匹配自己的 ⌥ 事件，且**不**匹配 `⌃⇧` 同键；
  - 重复 ⌥ 绑定被拒绝（`alt+l` 与学习区冲突时 `set` 失败）。
- `make macos-ui-snapshots UI=panels` 重新渲染关于/设置/诊断（新默认下无渲染异常）。
- `make verify` 全绿。

## 未做 / 限制

- **未装包**：已装 `a234ef31…` 仍是 `ctrl+shift` 默认值，实机菜单要等新签名包。
- **已有显式配置不静默覆盖**：B 机 `config.toml` 在报告 068 时把 8 项都写成了显式 `ctrl+shift*`，A 机显式写了 `toggle_mode`。改默认值后它们保持原值——若要在 A/B 上体验新语义，需要按 `ime-config` 改回 `none`/新值（用户确认后再做，本轮未动）。
- **真实应用冲突矩阵**（编辑器/Terminal/VSCode/IDE）仍需同包实机逐项确认，属 IT-14 范围。

## 关联

ADR-209（本轮）、ADR-207/208（历史默认值）、报告 074（⌃Space 冲突与 stale-event 保护）、`docs/配置架构.md`。
