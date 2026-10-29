# 220 「HUD 不显示」的结论：不是缺陷，是换包后仍在跑旧二进制

> 用户第三次报告「状态变化 HUD 没出现」。前两次都没能定位，因为诊断开关没生效（日志文件根本没写）。
> 本次把开关改成文件方式并给三个分支打点后，用户复测：**HUD 与候选窗都正常**，
> 之前的现象是**换包后新版本没有实时生效**（运行中的宿主还是旧进程/旧二进制）。

## 1. 为什么诊断开关之前"看起来没开"

`LAMPYRIS_HUD_DIAG` 由 `launchctl setenv` 设置，但宿主是 **IMK 通过 launchd 拉起**的：
`ps -Eww` 在这台机器上不显示环境（`-E` 不再输出），而 `lsof`/`ps` 又无法证明变量传进去了，
于是「日志文件不存在」既可能是没开日志、也可能是没走到该分支——**不可区分**。

## 2. 改法（已随 build 31 发布）

| 改动 | 说明 |
|---|---|
| 文件开关 | `~/Library/Application Support/Lampyris/hud-diag` 存在即开启；不再依赖 `launchctl setenv` |
| 分支打点 | `showStateFeedback` 记录走「内联芯片」还是「HUD」，以及面板可见性/组合态/传给 HUD 的光标矩形 |
| 入口打点 | `hudCaretRect` 记录 IMK 客户端 bundle、前台应用 bundle、`length()/selection()` |
| 失效守卫 | 每条 `return nil` 都写原因（沿用报告 219 的补法） |

诊断用完即删该文件（本次已在两台机器上移除）；代码保留，无文件时零开销。

## 3. 换包后必须确认「跑的是新二进制」

这次真正的教训在**运维动作**上：包换好了、文件 SHA 也对，但**正在运行的宿主进程可能仍是旧映像**。
判别方法（已写进 `iterate-macos-ime` 收尾清单）：

```sh
P=$(pgrep -x Lampyris | head -1)
lsof -p "$P" | grep 'MacOS/Lampyris' | grep -c deleted   # 必须为 0
shasum -a 256 "$HOME/Library/Input Methods/Lampyris.app/Contents/MacOS/Lampyris"
```

- `deleted` 计数 > 0 → 进程持有的是**已被替换掉的旧文件**，HUD/候选的旧行为都可能是它造成的。
- 文件 SHA 与运行进程的 `lsof` 路径一致、且 `deleted` 为 0，才算"新版本已生效"。

## 4. 结论

- **HUD 无缺陷**：报告 219/220 三次「不显示」分别是（a）诊断开关未生效无法取证、（b）候选窗跟随鼠标（真实缺陷，已在 build 30 修）、（c）**旧进程未退出**。
- 试用基线确定为 **1.0.0 / build 31**：air 与 pro 执行 SHA 均为 `9cbe8a22…`，`running_deleted=0`。
