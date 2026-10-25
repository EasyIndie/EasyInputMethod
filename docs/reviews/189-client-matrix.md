# 189 目标客户端矩阵（脚本化）

## 1. 方法

用报告188 的探针链路（`tissrc select` 设全局源 + `keytopid --hid` 从受信终端投递 + `guard-focus` 把关），对四个客户端发送同一串按键 `wq nihao .`：

- `wq` + 空格：五笔整码上屏
- `nihao` + 空格：拼音兜底
- `.`：中文标点

回读方式各不相同，避免只依赖一种证据：TextEdit 读 AX `AXTextArea` 值；Safari / Chrome 读页面标题（页面内 `oninput` 写入 `document.title`）；Ghostty 让新窗口跑 `cat > 文件` 后读文件。

已入库为 `tools/macos-probe/client-matrix.sh`（可重复执行，逐客户端强制 guard-focus）。

## 2. 结果（0.1.13/build21，执行 `a3faf05c…`，宿主 PID 12298）

| 客户端 | 上屏文本 | 回读通道 |
|---|---|---|
| 文本编辑（TextEdit） | `你你好。` | AX `AXTextArea.value` |
| Safari | `你你好。` | 页面标题 + AX |
| Google Chrome | `你你好。` | 标签页标题 + AX |
| Ghostty（终端） | `你你好。` | `cat >` 落盘文件 |
| Xcode 27 | **BLOCKED** | 首次启动未建立编辑器焦点，AX 查询返回 `NO_FOCUS_PID` |

- 四个客户端上屏一致，说明五笔优先 + 拼音兜底 + 中文标点在多宿主形态下行为相同。
- 宿主全程同一 PID，矩阵结束后 RSS 13.9 MiB；输入源已还原 ABC；`config.toml` SHA 仍为 `809e2cae…`（mode=mixed、标点中文、半角、简体）。

## 3. 事故与教训（如实记录）

一次不经 guard 的 `--hid` 投递把 `wq ` 打进了用户正在使用的 Ghostty 窗口（当时 Xcode 未取到焦点、前台回落到 ghostty）。因未发送回车，**没有执行任何命令**，只是命令行上多了 `wq ` 字样。教训与报告 099 一致，且这次是自己踩的：

- `--hid` 投递面向**前台应用**，前台可能在命令之间被切走；
- 因此**每一批发键前都必须 `guard-focus.sh <期望应用>` 并检查 `ok`**，这条已写进 `client-matrix.sh`，也是后续所有脚本的硬约束。

## 4. 未完成

- Xcode 需要首次启动向导/项目上下文，未纳入自动矩阵；如要覆盖，先由用户完成首次启动，再补一轮。
- 单按 Shift 中英切换仍待真实按键复核（报告188）。
- 浏览器只验证了文本域上屏，未覆盖富文本编辑器（如 Notion/飞书）与 Office 类应用。
