# T-ITER-12：IMK宿主性能与功耗基线

- 状态：进行中（隔离FFI/渲染子步有证据，真实IMK待安全隔离）
- 前置：IT-01/02；不能对真实学习词库合成打字。
- 目标：测冷启动、长组合、满词库、首次简繁/回切、面板、空闲的宿主延迟/内存/CPU/唤醒；实测违规才优化。
- 本轮环境：设备B macOS27/arm64，Xcode27；源码c294b67加未提交工作树，仅开发验证，不是锁定正式候选。
- 命令：`bash platforms/macos/tests/run-render-perf.sh`，临时配置/词库，Swift warnings-as-errors，运行退出0、临时资源自动清理。
- 结果：window_activation_ms=194.988；2200keys，cold_ms=15.827、warm_p95_ms=4.413、warm_max_ms=7.419、keys_at_or_above_16ms=0、footprint_mib=21.49。
- 边界：同步FFI/候选layout/show，不包括IMK dispatch或合成器完成；不覆盖完整首次进程启动、目标客户端、满容量、全部简繁路径、空闲CPU/唤醒。不能由此关闭IT-12或宣称真实输入延迟达标。
- 下一步：完成IT-01隔离IMK驱动后测以上场景，保存绑定最终候选的原始采样；不以单次探针数值替代产品门禁。
