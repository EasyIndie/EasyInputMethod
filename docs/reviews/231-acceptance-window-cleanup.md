# 231 — 验收收尾清理：跑完不留下自己的窗口

- 日期：2026-11-06　｜　触发：用户「验收跑完残留各种测试窗口，希望清爽干净可重复」
- 关联：报告 230（验收提效）、`tools/macos-probe/cleanup-windows.sh`

## 0. 结果

| 项 | 之前 | 之后 |
|---|---|---|
| 每跑一次一键验收 | 新增 1 个 TextEdit 文档、1 个 Safari 标签、1 个 Chrome 标签、1 个 Xcode 窗口（`xcode.txt`） | **全部收掉**；应用若本来没开、也没留下窗口，会被退出 |
| 中断/失败时 | 残留同上 + 可能留下测速窗口与 `keytopid` 进程 | `trap EXIT INT TERM` 同样收掉 |
| 历史累积 | 本轮开始时已有 3 个 Safari 标签、3 个 Chrome 标签、3 个 Xcode 窗口、1 个 TextEdit 文档 | 用同一个脚本一次清空（见 §3 验证） |

浏览器与 Xcode **只在"确认是自己的"** 前提下处理：Safari/Chrome 只关 URL 指向 `…/clients/page.html`（或本轮 `--out` 目录）的标签，永不退出浏览器；Xcode 只关标题含 `xcode.txt` 的窗口，且只有"本轮是它启动的 + 已无窗口"才退出。

## 1. 归属判定（宁留一个窗口，不误关用户的东西）

| 对象 | 认领条件 |
|---|---|
| Safari / Chrome 标签 | URL 含 `/clients/page.html` 或本轮 `--out` 路径 |
| Xcode 窗口 | AX 标题含 `xcode.txt`（矩阵写出的临时文件） |
| TextEdit 文档 | 未保存（`path` 为空）**且**内容命中探针输出签名 |
| TextEdit 应用 | 关完只剩"空且未保存"的文档时退出（不含任何用户内容） |
| 进程 | `lampyris-imetype.app` 测速窗口、残留 `keytopid` |

`--textedit` 是显式开关：默认不碰 TextEdit，避免误伤用户正在写的文档。
`--quit-app NAME` 只由 `client-matrix.sh` 传给"它自己启动的"应用。

## 2. 接入点

| 脚本 | 行为 |
|---|---|
| `acceptance-auto.sh` / `quality-samples.sh` / `client-matrix.sh` / `acceptance-full.sh` | 开头 `trap cleanup_run EXIT INT TERM`，失败与 Ctrl-C 同样清理 |
| `client-matrix.sh` | TextEdit 段落改为**自己新建一个空白文档**，读完立刻关闭（不再借用用户文档） |

## 3. 验证（1.1.0 / build 38，air）

| 场景 | 结果 |
|---|---|
| 清理历史残留 | 关掉 Safari 1 个、Chrome 1 个标签 → 0；Xcode 3 个 `xcode.txt` 窗口 → 0；TextEdit 1 个 `你你好。` 文档 → 0 |
| `client-matrix.sh` 单跑 | 关 1 Safari 标签 + 1 Chrome 标签 + 1 Xcode 窗口；TextEdit 由我们启动 → 退出；浏览器（用户已在用）保持运行 |
| `FAST=1 acceptance-auto` 全跑 | 热键 7/7、性能 PASS（p95 14.48ms）、客户端 4/4；结束后 TextEdit 未运行、Safari/Chrome 0 标签、imetype 0 进程 |
| 重复跑 | 连续三次结果一致（本轮 auto-clean / clean2 / clean3 / clean4） |

## 4. 踩过的坑（写进脚本注释，避免下次重犯）

1. **`tell application "X"` 会启动应用**：清理脚本里直接发脚本会把刚退掉的 TextEdit 又拉起来 →
   先 `pgrep -x` 判断在运行，再发 AppleScript。本轮"检查文档数"就自摆过一次。
2. **边遍历边 `close` 会让索引失效**（实测 `-1719`）：改用 AppleScript 的 `whose` 过滤一次性关闭。
3. **AppleScript 混用 `and` / `or` 必须每段加括号**，否则语法错（`-2741`），且报错位置指向别的行，极难定位。
4. **未保存文档的 `path` 是空字符串而不是 `missing value`**：按 `path is missing value` 判断永远不命中，TextEdit 清理会静默失效。
5. **关掉 TextEdit 最后一个文档会再开一个空白窗口**：所以"只剩空且未保存的文档"时才整应用退出。

## 5. 边界

- 不清理用户自己的窗口：签名/URL/标题不匹配的一律保留，并在输出里给出 `skipped` / `kept` 计数。
- 不退出浏览器：用户可能开着真实会话，只关我们的标签。
- 不删证据：`--out` 目录里的 JSON/日志属于验收证据，保留不动（清理只针对窗口与进程）。
- 仍有 1 个已存在的坑：`performance` 项在这台机器上 p95 已贴到 14–16ms（阈值 16），
  单轮曾出现 16.09 的 FAIL —— 属真实的边缘性能信号，不是清理引入的（报告 229 §7.2）。
