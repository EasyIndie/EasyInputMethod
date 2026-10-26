# 204 睡眠 → 唤醒后的首键与输入路径（pro）

## 1. 背景

「睡眠唤醒后直接输入，首键不丢」原本记人工。本轮把它拆成：**自动让机器睡下并判定真的睡过**、**唤醒后立刻驱动一次真实输入**，再补一轮质量样本。用户配合唤醒了机器。

环境：pro（Intel / macOS 13.7.8），0.1.13/build 21，执行 SHA `c3b533e4…`，输入源 `Lampyris.default`，客户端「文本编辑」。证据目录 `/tmp/lampyris-sleepwake/`。

## 2. 先解决「睡不下去」

第一次 `pmset sleepnow` 没有任何效果。`pmset -g` 显示：

```
pid 652(caffeinate): [0x…] 47:52:26 PreventSystemSleep named: "caffeinate command-line tool"
Localized=THE CAFFEINATE TOOL IS PREVENTING SLEEP.
```

即这台机器上有个 `caffeinate -s`（PID 652，自 10-24 起、约 2 天）一直阻止系统睡眠。用户确认后停掉它，`PreventSystemSleep` 归 0，才具备测试条件。

## 3. 怎么判定「真的睡了、又醒了」

`tools/macos-probe/sleep-test.py`：执行 `pmset sleepnow` 后每秒取一次时钟；进程在睡眠期间被挂起，醒来后第一轮就会出现**大于 5 秒的时钟跳变**，据此判定「睡过 + 已唤醒」，并打印睡了多久。

实测：

```
sleep_request 2026-10-26T03:02:40Z
wake gap=57.1s at 2026-10-26T03:04:12Z
```

即机器**睡了 57 秒**后被用户按键唤醒。`pmset -g log` 对应记录为 `Sleep Entering DarkWake state due to 'Software Sleep'` 与 `Wake … due to HID Activity`，与判定一致。

## 4. 唤醒后立刻验证

| 项 | 结果 |
|---|---|
| 宿主 | PID **69116 未变**（没有崩溃/重启），输入源 `Lampyris.default` |
| 首键（`wq ` → 上屏） | **PASS**：`axtext` 读到 `你`，无丢键 |
| 候选窗 | **PASS**：`axwins` 报 `AXSystemDialog 531×188 @73,166`，7 个候选项都在 AX 树里 |
| `type-session 'wq nihao .'` ×2 | **PASS**：`keys_seen=10`、`你你好。` |
| `acceptance-preflight.sh` | `ready=true`，`exec_sha` 仍 `c3b533e4…` |
| `quality-samples.sh` | **16/16 PASS** |
| 配置 / 词库 | `config.toml` `2bd3fde6…` 未变；词库 501 行（学习写入） |
| 网络 | 0 条 TCP/UDP |
| 显示布局 | 唤醒后与睡眠前一致（内置 1280×800@2x 主屏 + LG 1920×1080@2x 在上） |

补充说明：用户唤醒时在 Chrome 上按键，Chrome 的输入源按系统"每应用记住输入源"回到 ABC；切到文本编辑并选中萤火虫后，**第一次组合键就正常上屏**，没有出现"首键被吞"。

## 5. 结论

- 睡眠 57 秒 → 唤醒后输入路径正常：宿主不重启、配置不变、首键不丢、候选窗正常、16 项质量样本全过、零外联。
- 这台机器此前测不了，是因为 `caffeinate -s` 长期阻止睡眠；已停（用户操作）。**若不再需要防睡眠，别再手动拉起**，否则后续验收会重复卡在这里。
- 新增工具：`tools/macos-probe/sleep-test.py`（睡下 + 时钟跳变判定唤醒）。

## 6. 未覆盖

- 长时间睡眠（数小时/过夜）与合盖睡眠：本轮是 57 秒软件睡眠；过夜场景要用户次日配合。
- 唤醒后首个**应用**是否是用户原本的应用、以及蓝牙/外接键盘唤醒：本轮由用户按内置键盘唤醒。
