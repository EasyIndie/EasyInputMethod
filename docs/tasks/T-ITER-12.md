# T-ITER-12：IMK宿主性能与功耗基线

- 状态：进行中（宿主级基线 + IT-12 矩阵 + 内嵌计时已采；面板/合成器完成与 B 机仍缺）
- 前置：IT-01/02；不能对真实学习词库合成打字。
- 目标：测冷启动、长组合、满词库、首次简繁/回切、面板、空闲的宿主延迟/内存/CPU/唤醒；实测违规才优化。
- 本轮环境：设备B macOS27/arm64，Xcode27；源码c294b67加未提交工作树，仅开发验证，不是锁定正式候选。
- 命令：`bash platforms/macos/tests/run-render-perf.sh`，临时配置/词库，Swift warnings-as-errors，运行退出0、临时资源自动清理。
- 结果：window_activation_ms=194.988；2200keys，cold_ms=15.827、warm_p95_ms=4.413、warm_max_ms=7.419、keys_at_or_above_16ms=0、footprint_mib=21.49。
- 边界：同步FFI/候选layout/show，不包括IMK dispatch或合成器完成；不覆盖完整首次进程启动、目标客户端、满容量、全部简繁路径、空闲CPU/唤醒。不能由此关闭IT-12或宣称真实输入延迟达标。
- 下一步：完成IT-01隔离IMK驱动后测以上场景，保存绑定最终候选的原始采样；不以单次探针数值替代产品门禁。

## 2026-10-20 设备 A（Intel / macOS 13.7.8）补充

- 工具：`run-installed-perf-probe.py`（宿主级基线）、`run-installed-perf-matrix-probe.py`（冷启动/满词库/首次简繁/唤醒）、
  `run-installed-perf-trace.sh`（内嵌计时，ADR-218）、`isolated-imk/ax-text-wait.swift`（进程内 AX 轮询）。
- 宿主内实测（公证隔离包，n=45，两次运行）：**按键→候选窗更新完成 p50 14.1/14.9 ms、p95 20.6/23.5 ms、max 32.7 ms**；
  **引擎 p50 1.0 ms / p95 1.5 ms**；面板打开 42 ms（设置）/ 165 ms（关于）。
  即《技术方案》§12 的「按键→候选 < 16 ms」**引擎达标、端到端 p95 超标**，瓶颈在 IMK 客户端回写与候选窗 update/show。
- 矩阵（外部 AX 轮询上界）：冷启动 197 ms（启动后 RSS 11.1 MiB）、满词库 1 万条/1.97MB → p50 173 ms / RSS 11.0 MiB、
  首次简繁切换后 p50 225 ms、睡眠唤醒 RSS 29.4→29.5 MiB 且唤醒后首批提交 732/381/298/394 ms；空闲 CPU 0.3%。
- 面板维度的「打开耗时」已由内嵌计时覆盖；菜单驱动的 AX 路径在隔离身份下不可用（记录于报告 103）。
- 已知边界：采样不含 IMK dispatch 内部时延与合成器完成；单机 Intel；**同一会话反复 pkill 宿主后系统会停止按需拉起**，
  采样需在新登录会话进行（脚本已固化顺序与重试）。
- 下一步：①在 B（arm64/macOS 27）复采；②按 §12 决定是否把「端到端 p95 超标」列为需优化项（先写 ADR）。

