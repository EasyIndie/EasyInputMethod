# 177 App Store 搜索框首次输入卡顿调研（进行中）

## 现象

- 设备：`ssh pro`（Intel / macOS 13.7.8 / 22H730），App Store 3.0；
- 已装 Lampyris 0.1.12/build20，输入源已启用；
- 在 App Store 搜索框**偶发首次输入卡顿**，状如卡死，等待较长时间后恢复；
- 尚未取得精确复现时间、卡顿时长和当时前台应用截图。

## 公开资料检索

- 在可用的公开搜索渠道中没有找到可核实的“Lampyris + Mac App Store 搜索框”同款报告；
- 有一般性的 Mac App Store 搜索慢/网络加载讨论，但没有找到可引用的 Apple 官方缺陷编号或明确修复版本；
- 因此**不能称为已知产品缺陷**，也不能据此认定系统兼容问题；搜索受限本身不能证明“不存在”。

## 本机证据（只读）

- 无 Lampyris/App Store 崩溃报告；无 Secure Input；`Lampyris` 空闲 CPU 0%，内存正常；
- 11:15:12.672–11:16:17.344（约 65 秒）`Lampyris` 没有任何 `Setting marked text` / `Get attributes` 日志；
  这段时间 WindowServer 有触控/鼠标事件，但没有 App Store 日志；
- 该时间点前后 Lampyris 持续打印：
  `CandidatePanel ordered front from a non-active application may order beneath ...`
  这是候选窗在后台宿主中的窗口层级提示，尚不能证明与卡顿相关；
- 10:58:16 App Store 曾在同一秒发起大量 CFNetwork 任务（首次搜索/页面加载特征），但与上述 11:15 间隔不重合；
- 设备上有 RayLink 远程工具，若复现通过远程桌面进行，输入路径本身也可能引入延迟；
- 历史 build6 的冷首键约 42.7ms（layout 9ms + measure 6.3ms），**不足以解释数十秒级卡顿**；0.1.12 尚未在 Intel 上按同一协议复测。

## 假设排序（待验证，不作结论）

1. **App Store 首次搜索/主线程或网络阻塞**：App Store 自己卡住，第三方输入法同步调用 IMK client
   （`selectedRange`、`attributes(forCharacterIndex:)`、候选窗定位）时一起等待；ABC 可能也会卡，只是没有候选窗。
2. **Lampyris 首次输入路径**：候选窗懒创建、首次布局/测量或 SQLite/词典初始化；历史数据只有几十毫秒，不能解释长卡。
3. **候选窗与 App Store 的窗口/光标交互**：日志中的 `ordered front from non-active application` 提示可能放大等待，
   但需要 sample 证明主线程停在哪里。
4. **远程会话/系统环境**：RayLink、远程桌面、系统负载或 macOS 13.7.8 的 App Store 问题。

## 建议的 A/B 复现（判定系统还是产品）

同一台 `pro`、同一 App Store 搜索框、同一查询文本：

1. **ABC 对照**：切到 ABC，冷启动 App Store，首次点击搜索框并输入；记录是否也卡、卡多久。
2. **Lampyris 冷宿主**：重启 Lampyris 宿主，先在 TextEdit 输入一次使其完成懒加载，
   再切到 App Store 搜索框输入；与“完全冷启动后直接进 App Store”对比。
3. **Lampyris 暖宿主**：已输入过若干次后再进 App Store，观察是否仍只卡第一次。
4. **网络对照**：App Store 搜索页已加载/离线（或断网）时输入，判断是否与首次网络请求相关。
5. 卡住时在活动监视器对 `App Store` 和 `Lampyris` 各做一次 **Sample Process / Spin Dump**，
   记录时间戳、CPU、是否在 IMK/mach_msg/WindowServer 等待。

判定：

- ABC 也卡 → 优先归因 App Store/macOS；记录 Apple 侧现象，产品侧只做规避；
- 只有 Lampyris 卡，且 sample 显示 Lampyris 在 IMK client 调用/候选窗等待 → 产品与 App Store 的兼容问题，
  需要进一步减少同步 caret/窗口操作或增加诊断；
- 只有冷启动首次卡，暖宿主不卡 → 冷启动/懒加载路径，按冷首键协议复测并优化；
- 远程会话中才卡、本机不卡 → 远程输入链路，不作为产品缺陷结论。

## 临时规避

- 在 App Store 搜索时临时切到 ABC；
- 先在 TextEdit 等普通文本框输入一次，再切到 App Store；
- 卡住时等待或强制退出 App Store，避免连续发键；
- 检查 macOS/App Store 更新；远程复现时改用本机直接操作对比。

## 下一步

- 需要用户提供**精确发生时间**或按上述 A/B 复现一次；
- 在拿到 sample 前不修改输入法同步路径，不把本次现象写成“已修复”或“系统已知 bug”；
- 若确认 Lampyris 侧等待，再按 ADR 评估减少每键同步 caret 查询/候选窗重排的方案与性能回归。
