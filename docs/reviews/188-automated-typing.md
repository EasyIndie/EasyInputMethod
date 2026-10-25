# 188 键入路径自动化（探针 + 首轮结果）

## 1. 为什么以前自动化不了

上一轮（报告187）用 `tissrc select` 切到 `Lampyris.default`、再从 SSH 会话向 TextEdit 发合成按键，只落成裸 ASCII。原因有两条：

1. **`TISSelectInputSource` 只影响调用进程自己的输入上下文**，不会改变其他 App 的输入源；
2. **`CGEvent` 投递受 TCC 约束**：`open` 启动的 ad-hoc App 自己发键会被静默丢弃（本地 `keyDown` 监视器 `keys_seen=0`），而 SSH 会话里 IMK 的 mach 服务不可达（日志 `error messaging the mach port for IMKCFRunLoopWakeUpReliable`）。

## 2. 可行组合（已入库为探针）

新增 `tools/macos-probe/imetype.swift`、`keytopid.swift`（`make -C tools/macos-probe` 构建）：

1. `open -n` 启动最小 `.app`（内含 `imetype`），测试窗口落在图形会话；
2. `imetype` 在**自身进程内**切输入源，并用 `NSTextView` 承接上屏文本；
3. 从**受信任的终端进程**用 `keytopid <pid> <按键串>` 向该窗口 PID 投递按键。

按键串语法：`;` 分隔，片段为普通字符（可多字符）、单独修饰键（`shift`）、或 `opt+f` / `ctrl+a` / `shift+a`。

## 3. 首轮结果（0.1.13/build21，生产位，宿主 PID 12298）

命令骨架：

```sh
open -n /tmp/lampyris-imetype.app --args --source cn.jokerhub.inputmethod.Lampyris.default \
     --keys "" --settle 26 --out /tmp/it9.json
keytopid <测试窗口 pid> 'wq '; keytopid <pid> 'nihao '; …
```

| 场景 | 结果 |
|---|---|
| 五笔整码上屏（`wq` + 空格） | 上屏「你」 |
| 拼音兜底（`nihao` + 空格） | 上屏「你好」 |
| 四码唯一自动上屏（`wqiy`，不按空格） | 上屏「你」（符合 `wubi.auto_commit` 默认） |
| 中文标点（`.`） | 上屏「。」 |
| 全角切换（⌥F → `12` → ⌥F） | 上屏「１２」，再切回半角后 `config.full_width=false` |
| 键入期网络 | 28 次采样（1 秒/次）**全部 0 连接** |
| 键入期内存 | RSS 17.2 → 35.3 MiB 区间波动，会话结束回落到 20.5 MiB |
| 宿主稳定 | 同一 PID 12298 全程存活，无崩溃报告 |

一次矩阵会话的完整上屏文本为 `你你好。想法１２`（`keys_seen=26`，全部按键送达测试窗口）。

## 4. 投递通道的差异（第二轮：`--hid`）

`keytopid` 支持两种投递：默认 `postToPid`（直接进目标 App 队列）与 `--hid`（投到 HID tap，走完整输入链路）。实测：

| 场景 | `postToPid` | `--hid` |
|---|---|---|
| ⌥M 模式循环 | 连发 3 次只生效 2 次，`config.mode` 停在 `pinyin` | **每次按下都生效**：`mixed → wubi → pinyin`，配置逐次落盘 |
| ⌥ 组合（全角/标点） | 部分生效 | 生效（`12` → １２） |
| 单按 Shift 切中英 | 未见 `abc` | 同样未见 `abc`，文本出现「想法」 |

- 结论：**修饰键热键必须用 `--hid`**（`postToPid` 绕过 IME 热键层，只把键送进 App 的 keyDown 路径）。
- **单按 Shift 仍是未解释项**：隔离实验里单独发 `abc`（不切中英）文本为空、`keys_seen=3`，符合「wubi 码未打完不提交」；一旦先发 `shift`，最终文本变成「想法」而非 `abc`。这既不像「切到英文」，也不像「留在中文」，需真实按键复核后才可定性；本轮**不记为产品缺陷**。

## 4.1 节奏参数

`keytopid <pid> <按键串> [保持ms] [间隔ms] [--hid]`，默认 120/180。慢节奏（250/900）未改变 Shift 的结果，排除"按键太快"。

## 5. 状态还原

- 矩阵结束后 `config.toml` 的 SHA 回到会话前的 `809e2cae…`（`mode=mixed`、`punctuation=chinese`、`full_width=false`、`chinese_variant=simplified`、`show_wubi_learning=true`）。
- 用户词库因自动化上屏 520 → 531 行（真实学习写入，未清理）。
- 输入源回到 `com.apple.keylayout.ABC`，测试窗口进程已退出。

## 6. 对最终 RC 矩阵的意义

- 「键入期零外联」「上屏正确性」「全角/标点切换」从此可脚本化复现，不必每次请用户手打。
- 单按 Shift、⌥M 这类**修饰键单发/连发**场景仍需真实按键，或后续把合成节奏调慢再试。
