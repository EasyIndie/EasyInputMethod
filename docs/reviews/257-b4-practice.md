# 257 — B4 练习：只出 full 题，A+C 两种题型，进度本地有界

- 日期：2026-11-06　｜　决策：ADR-313（已实现）　｜　快捷键：`hotkey.open_practice`（默认 **⌥K**）

## 1. 做了什么

| 文件 | 内容 |
|---|---|
| `platforms/macos/Sources/Practice.swift` | 题库（只取 `quality=="full"`）、判分（码 / 识别码表）、进度（`practice.tsv`） |
| `platforms/macos/Sources/PracticeWindow.swift` | 独立非模态窗口：题干、输入框或按钮、判分反馈、进度摘要、下一题/显示答案/打开进度文件 |
| `crates/ime-config/src/schema.rs` | 新增 `hotkey.open_practice`（默认 `alt+k`，可选 `none`） |
| `InputController` | 热键路径打开练习窗口（与设置/关于同一套处理，不依赖菜单） |

## 2. 题型（用户选定 A + C）

- **A 看字打码**：给一个字，输入完整五笔码；大小写与空白不敏感。
- **C 识别码判断**：给字 + 拆解提示，选「末笔」（横竖撇捺折）与「结构」（左右/上下/杂合），按反查表判对错。

> B（看码选字）按建议暂不做：它练的是速度，A/C 练的是不会的东西。

## 3. 数据与边界

- 题库来自 `B0-runtime.tsv`（ADR-311 v2），**只用 `full`**（3,000 字里 2,010 条）；
  `partial`/`unknown` 不出题——不拿不确定的东西考人。
- 识别码表：横 GFD / 竖 HJK / 撇 TRE / 捺 YUI / 折 NBV（与 B0 生成规则同源）。
- 进度：`~/Library/Application Support/Lampyris/practice.tsv`，`字 \t 题型 \t 次数 \t 正确 \t 最近时间`；
  **数据不是配置**（不写 config.toml / UserDefaults / 第二个配置文件）；上限 3,000 行 / 256 KiB，超限按次数少淘汰；
  写入先写临时文件再 `replaceItemAt` 原子替换，失败保留旧文件。

## 4. 验证

- `cargo test -p ime-config` / `-p ime-ffi`：Schema 数量与键列表更新为 23 项，全绿。
- 离线回归 **62 文件 / 328 例 PASS**（`wubi-learning.swift` 里新增练习断言：只出 full 题、判分大小写不敏感、
  识别码表两例、进度 3,200 次记录后有界且可重载）。
- `make verify` PASS（232 产物零网络符号）。
- 设置页断言更新：快捷键行含 `hotkey.open_practice`，行数 23。

## 5. 还没做

- **装包实测**：新窗口的真机交互（键盘焦点、关闭释放、导出）尚未在装机包上走查。
- 题型 B 与错题复现策略（ADR-313 已列为可选）。

## 6. 关联

ADR-311/312/313、报告 252/256、`docs/设计`、`docs/配置架构.md`。
