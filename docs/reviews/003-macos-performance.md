# macOS 核心性能测量（2026-10-08）

环境：macOS 27 arm64、Rust 1.98.1；release staticlib，经 C ABI 调用，使用隔离配置和空用户词库。脚本 `platforms/macos/tests/run-perf.sh`，2200 次按键，包括 wq、nihao、zhongguo、zz 通配、a、kwwl；每次包含配置消费和候选转换。

| 场景 | 持续输入物理 footprint | 峰值 RSS | P95 延迟 |
|---|---:|---:|---:|
| 优化前、仅五笔 | 194.45 MiB | 202.02 MiB | 10.28 ms |
| 有界 top-k、仅五笔 | 6.69 MiB | 10.59 MiB | 0.445 ms |
| 有界 top-k、核心拼音 256KiB | 16.78 MiB | 20.67 MiB | 0.471 ms |

第三项样本最大延迟 1.322 ms；100 轮后内存稳定。默认核心拼音词表 12403 条、262131 字节，规则及校验和见 `data/generated/pinyin-core-report.json`。原全量词表 340k 条，不默认装载。

这些结果只覆盖引擎 ABI，不包含 Swift/AppKit/IMK 的事件分发、候选 UI、客户端、最大用户词库或长时间 GUI 会话；完整宿主常驻内存与端到端延迟仍需在发布候选包验收，不能据此勾选完整 Phase 1 性能 DoD。
