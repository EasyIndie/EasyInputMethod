# 293 — 隔离预览补上键位图字根/口诀资源

日期：2026-11-16　设备：air（arm64 / macOS 27.2）
结论：预览环境的资源缺口已修（**只影响调试预览，已装包不受影响**）；真机键位图面板恢复字根与口诀。

## 1. 现象

在隔离预览里打开练习 → 展开「键位图」：只有键盘轮廓，**没有字根，也没有口诀**。
用户以为是本批改动（练习重试/窗口落点）引入的回归。

## 2. 根因

`KeyRootLayout.load()` 从 `Bundle.main` 的 `Resources/key-roots-wubi86.tsv` 读取字根与口诀；
缺失时回落到内置的「只有 25 个键名」版本（`roots: []`、`mnemonic: ""`）。

`dev-preview.sh` 只复制了 `B0-runtime / wubi86-core / symbols / emoji / wubi86-level3-codes`，
**漏了 `modules/keymap/data/key-roots-wubi86.tsv`**；`run-panel-interactive.py` 按预览包 Resources
逐项软链，所以隔离预览同样缺。正式包由 `build.sh` 复制该文件，因此已装包正常。

## 3. 修复

- `dev-preview.sh` 构建预览包时复制 `key-roots-wubi86.tsv` 到 `Contents/Resources/`（附注释说明来源）。
- 隔离预览经软链自动获得；无需改产品代码。

## 4. 验证（隔离预览实机）

| 项 | 观测 | 结果 |
|---|---|---|
| 键位图展开 | 出现「五笔 86 · 25 键字根分布」+「口诀」开关 | PASS |
| 口诀 | 打开开关后 AX 读到完整五区口诀（横区「王旁青头戋（兼）五一…」等） | PASS |
| 字根 | 口诀非空即证明加载的是真实 TSV（内置兜底 `mnemonic` 为空、`roots` 为空） | PASS |
| 附带项 | 练习页 `已练 29 字`、一级简码 tab 仍锁定（供下一步「达标即时解锁」验收） | PASS |

## 5. 差异与遗留

- 只影响本地调试预览；正式候选包原本就带该资源，无需重新发版。
- 同类缺口以后按「预览包 Resources 与 build.sh 复制清单一致」检查；本轮已把练习/符号/键位图用到的
  资源（B0、码表、符号、emoji、三级简码、键位字根）全部覆盖。
