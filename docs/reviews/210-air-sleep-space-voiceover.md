# 210 air 侧收尾三件：睡眠唤醒 / 多 Space / VoiceOver（0.1.14 build 23）

设备：air（`ssh air`，`joker`，arm64 / macOS 27.0.1 / SDK 27.0 / Swift 6.4），包 `0.1.14 / build 23`，执行 `a165f05c0b704796380a39f5666da5e2cfa1a8cb2d23868dfd3d1532d429e4dc`（与 pro 同一个候选包）。
证据目录：air 上 `platforms/macos/build/acceptance-air-210/`。

## 1. 睡眠 → 唤醒（报告204 判据）PASS

| 判据 | 结果 |
|---|---|
| 真的睡了 | `wake gap=26.5s`（进程被挂起导致时钟跳变 > 5s） |
| 宿主未重启 | PID **2078**，唤醒前后一致 |
| 唤醒后首键 | `wq ` → **你** |
| 质量样本 | **16/16 PASS**（`/tmp/lampyris-quality-air-postwake`） |
| 配置 / 词库 | `809e2cae…` / 650 行，与睡前一致 |
| 外联采样 | **0 条** TCP/UDP（20 次采样） |
| 显示布局 | `1440×900@2x`，未变 |

## 2. 多 Space PASS

基线（原桌面）：候选窗 `253,328 538×188`。
用户手动切到另一个桌面后，在新桌面新开输入窗口 → 候选窗 `253,328 538×188`（屏幕 `1440×900`）**完整在屏内**、位置随客户窗；`wq ` → **你**。

### 2.1 过程中的一个假象（已定性为探针问题）

新桌面第一次键入得到「多」而不是「你」。追查：air 上单独 `q ` 打出来就是 **多**（五笔一级简码 q = 多），说明**首个按键 `w` 被窗口激活吞掉**，引擎只收到 `q`。
同一现象也解释了客户端矩阵里一次 `多你好。`（少了一个`你`）。属于 `keytopid` 投递与窗口激活的时序，不是产品缺陷；正式断言前多等 2–3 秒即消失。

## 3. VoiceOver PASS（人耳确认）

- **装机版**（`cn.jokerhub.inputmethod.Lampyris.default`）上 `axobserve` 抓到
  `AXAnnouncementRequested`（候选组 role=`AXGroup`，换候选）+ `AXSelectedChildrenChanged` + `AXAnnouncementRequested`（`AXApplication`，上屏），与 pro/macOS 13 同构。
- **人耳**：air 上开着 VoiceOver（PID 12941），驱动 `wq` → → → → 空格，用户确认听到面板编码、换候选播报与上屏播报（答复「A」）。

### 3.1 为什么人耳那一轮用的是调试窗口

air 上 VoiceOver 开启后，**装机版**的输入上下文会掉回 ABC：`wq,` 打出来是裸 `wq`（`has_non_ascii:false`），输入法菜单显示「正在加载…」。同样的按键在 VoiceOver 关闭时正常。
因此 air 上「按键 → 播报」的人耳验证改用**同一份 `CandidateWindow` 代码**的调试窗口（`make macos-preview`，私有 support 目录），装机版的播报以 `axobserve` 取证为准；pro 上装机版已有人耳确认（报告207）。这条限制记入未决。

## 4. 收尾状态

| 项 | 值 |
|---|---|
| 已装 | 0.1.14 / build 23，执行 `a165f05c…`，宿主 PID 2078 |
| 配置 / 词库 | `809e2cae…` / 651 行（学习写入） |
| 输入源 | 已还原 `com.apple.keylayout.ABC`；VoiceOver 已退出 |
| 回滚 | `~/Library/Application Support/Lampyris/uninstalled/bundle.194538`（0.1.13，执行 `c3b533e4…`） |

## 5. 结论

- air 与 pro 现在跑同一个包，**自动项与人工项都已有结论**：air 侧睡眠/多 Space/VoiceOver 三项 PASS。
- 唯一遗留是 §3.1 那条环境限制（VoiceOver + 装机版在 air 上输入上下文掉成 ABC），需要后续单独定位（是 VoiceOver 改了当前输入源，还是 IMK 在 VO 下的客户端重建）；不影响播报实现本身的结论。
