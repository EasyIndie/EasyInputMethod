# 079 — 全/半角默认快捷键 `⌥Space` → `⌥F`（ADR-210）

2026-10-18。用户报告 `⌥Space` 与 ChatGPT 的虚拟宠物输入冲突，要求更换默认值；确认 `⌥F` 实测可用。

## 决策

- 只改 `hotkey.toggle_width` 的默认值：`alt+space` → **`alt+f`**（F = Full-width）。
- 其余默认保持 ADR-209：`⌥M` 模式、`⇧` 中英、`⌥P` 标点、`⌥T` 简繁、`⌥L` 学习区、`⌥,` 设置、`⌥A` 关于。
- **已有显式配置不静默覆盖**；B 机的现有配置通过设置面板（走 `ime-config`）由用户显式改为 `alt+f`。
- 新 ADR：`docs/决策记录.md` ADR-210（局部取代 ADR-209 的 `alt+space`）。

## 改动

| 位置 | 内容 |
|---|---|
| `crates/ime-config/src/schema.rs` | 默认值与说明文字改 `alt+f` |
| `crates/ime-config/src/lib.rs` | 默认值断言与冲突用例改 `alt+f` |
| `platforms/macos/tests/settings-presentation.swift` | 设置页期望 `⌥F` |
| `platforms/macos/tests/wubi-learning.swift` | 宽度快捷键用例改 `⌥F`，并新增「`⌥Space` 不再切换」的负向断言 |
| `platforms/macos/Preview/main.swift` | 冲突用例改 `alt+f` |
| `docs/配置架构.md` / `docs/发布说明.md` | 默认值与快捷键表同步（发布说明的旧 `Shift+Space`/`Ctrl+Shift+*` 一并订正） |
| `platforms/macos/tests/run-local-acceptance.py` | 补登记 `candidate.padding`、`learning.stale-chord`，两个套件不再恒为 BLOCKED |
| `crates/ime-ffi/src/session.rs` | 注释去掉过时的 `Shift+Space` |

## 验证

- `cargo test -p ime-config`：16 通过（默认值、冲突、别名）。
- `make macos-local-acceptance`：**62 场景全 PASS**（修复前 candidate/learning 因清单漏登记恒 BLOCKED）。
- `make verify`：全绿（含 clippy / deny / 180 产物隐私断言）。
- B 机已装包（`6494eab`）实机：设置面板把值改为 `alt+f` 后按钮显示 `⌥F`，菜单 AX 读出的全/半角行由空格变为 `char=F, mods=10`；用户实测 `⌥F` 切换正常、`⌥Space` 不再触发。

## 未解决 / 关联

- 裸 `⌥+字母` 仍会覆盖终端/readline 的 Meta 键（`⌥F/B/D/T/L/P` 在 zsh 均有绑定），
  属于 ADR-209 已记录的取舍；是否改前缀（`⌃⌥`）待用户决定。
- 「状态变化无法感知」另见报告 080（统一状态反馈）。
