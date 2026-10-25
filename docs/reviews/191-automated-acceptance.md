# 191 一键自动化验收（热键 / 客户端 / 性能 / 零外联）

## 1. 一条命令

```sh
make macos-auto-acceptance                 # 默认 10 轮，约 6 分钟
ROUNDS=4 make macos-auto-acceptance        # 快速冒烟
```

`tools/macos-probe/acceptance-auto.sh` 依次跑：模式前置 → 热键与上屏 → 五客户端矩阵 → 键入延迟/内存/网络，任一项失败即非零退出，并把证据写到 `OUT` 目录。

## 2. 关键实现（为什么能自动化）

| 能力 | 做法 |
|---|---|
| 逐键延迟 | 测试窗口把 `NSEvent` 直接交给自己的 `keyDown`，经输入上下文走真实 IME 往返；用 `NSText.didChangeNotification` 记录「投递→文本变化」用时，**不轮询字符串**（轮询会抢主线程，实测把 p95 从 7.9ms 抬到 32.9ms） |
| 网络 | 会话期间每秒 `lsof -nP -i` 采样宿主 PID，断言全程 0 条 TCP/UDP |
| 内存 | 键入结束后静置 20 秒再取 RSS，作为"稳定态"（测峰值会被候选窗/首次布局干扰） |
| 中断风险 | `keytopid --hid` 发键前校验目标 PID 就是前台应用；`type-session.sh` 先清掉残留测试窗口 |

## 3. 本次结果（0.1.13/build21，执行 `a3faf05c…`，宿主 PID 12298）

| 项 | 结果 |
|---|---|
| 混输 + 标点 | PASS（`你你好。`） |
| Shift 切英文 / 切回中文 | PASS（`abc` / 中文） |
| ⌥P 标点 | PASS（`.。`） |
| ⌥F 全角 | PASS（`１２12`） |
| ⌥T 繁简 | PASS（`學習` / `学习`） |
| ⌥M 模式循环 | PASS |
| 客户端矩阵 | PASS 5/5（TextEdit / Safari / Chrome / Ghostty / Xcode） |
| 键入延迟 | 160 键：p50 **2.23 ms**、p95 **6.43 ms**（阈值 16 ms） |
| 稳定态内存 | **11.8 MiB**（阈值 30 MiB） |
| 网络 | 0 条 TCP/UDP |
| 还原 | `mode=mixed`、输入源 ABC |

## 4. 已知边界

- 单键最大 52 ms 的偶发离群（候选窗首次创建/字体），p95 仍远低于门限；若要深究，可开 `LAMPYRIS_PERF_TRACE` 用隔离包的 ADR-218 通道分阶段拆解。
- 生产宿主的 `LAMPYRIS_PERF_TRACE` 注入不生效（`launchctl setenv` 后 `open` 起的宿主读不到），因此延迟走应用侧"投递→文本变化"，不包含 IMK 派发内部耗时。
- 仍无法自动化：辅助功能（VoiceOver 实读）、多屏缩放、睡眠唤醒、卸载/升级异常流程、第三方重建、五日试用。
