# 190 热键矩阵自动化 + 前两份报告的更正

## 1. 更正报告188 的两个结论

| 报告188 的结论 | 实测更正 |
|---|---|
| 「单按 Shift 切中英异常，出现『想法』」 | **探针问题**：用 `CGEvent` 的 `keyDown(56)` 不会被当成修饰键变化。改成真正的 `flagsChanged` 事件（新 token `shiftc`）后，中英切换完全正常 |
| 「⌥M 连发 3 次只生效 2 次」 | **投递通道问题**：`postToPid` 绕过 IME 热键层；改 `--hid` 后每次按下都生效 |

两个都不是产品缺陷，报告188 的措辞已在正文修正。

## 2. 新增能力（`tools/macos-probe`）

- `keytopid` 增加 `shiftc`/`optc`/`ctrlc`/`cmdc`：发**真正的 `flagsChanged`**，供只监听修饰键的热键使用；新增 `cmd` 组合（如 `cmd+s`）。
- `keytopid --hid` 现在**先校验目标进程就是前台应用**，不是就退出 3，避免按键落到用户窗口（报告189 事故的直接修补）。
- 新增 `type-session.sh '<按键串>' [--settle N]`：起测试窗口 → 等前台 → 先发一次纯修饰键"点"窗口（首个键会被激活吞掉）→ 发正文 → 回读 JSON。一条命令得到一个可复现的断言结果。

## 3. 热键矩阵实测（0.1.13/build21，执行 `a3faf05c…`）

| 场景 | 按键 | 上屏 | 判定 |
|---|---|---|---|
| 混输 + 标点 | `wq nihao .` | `你你好。` | PASS |
| 单按 Shift 切英文 | `shiftc;abc` | `abc` | PASS |
| 再按 Shift 切回中文 | `shiftc;shiftc;wq ` | `你` | PASS |
| 标点快捷键 | `opt+p;.;opt+p;.` | `.。` | PASS |
| 全角快捷键 | `opt+f;12;opt+f;12` | `１２12` | PASS |
| 简繁快捷键 | `opt+t;xuexi ` | `學習`（默认 `学习`） | PASS |
| 模式循环 | `opt+m` ×N | `mixed → wubi → pinyin → mixed`，逐次落盘 | PASS |

- 结束后 `config.toml` SHA 回到 `809e2cae…`（mode=mixed、标点中文、半角、简体）。
- **踩坑记录**：`opt+m` 会改的是持久化 `mode`。若测完停在上一步，后续「拼音兜底」看起来就像坏了（实际是五笔模式）。测试脚本必须先确认 `mode=mixed` 再跑矩阵。

## 4. 客户端矩阵（覆盖报告189 的 Xcode 缺口）

`KEYS='wq nihao .' ./tools/macos-probe/client-matrix.sh` 全绿：

| 客户端 | 上屏 | 回读 |
|---|---|---|
| 文本编辑 | `你你好。` | AX `AXTextArea` |
| Safari | `你你好。` | 页面标题 + AX |
| Google Chrome | `你你好。` | 标签页标题 + AX |
| Ghostty | `你你好。` | `cat >` 文件 |
| Xcode 27 | `你你好。` | `⌘S` 落盘后读文件 + AX |

Xcode 之前 BLOCKED 的原因只是**没等够时间**（启动到窗口可编辑要十几秒），现在脚本里用「前台变成 Xcode」作为等待条件。

## 5. 现在的自动化覆盖面

| 门禁项 | 状态 |
|---|---|
| 键入期零外联（逐键采样） | 可自动化（`lsof` 循环 + 会话） |
| 上屏正确性（五笔/拼音/标点/全角/简繁/总英） | 可自动化 |
| 模式与偏好持久化 | 可自动化（读 `config.toml`） |
| 目标客户端（TextEdit/Safari/Chrome/Ghostty/Xcode） | 可自动化 |
| 性能（p95、稳态内存） | 可自动化（采样 RSS + 会话时长） |
| 辅助功能、多屏缩放、睡眠唤醒 | 需真实交互，暂未自动化 |
| 卸载/升级异常、第三方重建、五日试用 | 需流程性操作，未自动化 |
