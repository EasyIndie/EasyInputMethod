# 112 — 相同状态重复布局的最小优化

2026-10-21，B arm64/macOS27；主线594c8c6基础上的独立改动，ADR-241，复用T-ITER-12。双高亮修复#63、版本顺序#65合并仍待明确授权；本批不安装新包，不扩大升级功能。

## 定位和改动

InputController.showCandidates每次更新依次调用updateStatus、update候选内容、show内部layout。原updateStatus即便五项状态完全不变，仍重新更新芯片并调用arrange。600组真实表输入×3轮基线，状态阶段P50为0.789–0.810ms，P95为0.899–0.978ms；这只是离屏定位依据，不是用户输入延迟。

最小改动仅让CandidateStatus使用编译器合成Equatable，并在updateStatus发现与已绘制状态相同时返回。比较模式/中英/宽度/简繁/标点所有五字段；不同状态仍执行原同步更新。候选输入内容、焦点、学习、外观、预编辑客户端、定位和可访问性契约不改。没有新增用户配置或第二个配置快照，保存的是既有视图状态。

## 三对交替测量

同一探针、同一release FFI、同一数据，baseline/candidate交替各三轮，每轮600样本；先准备引擎和字体。fixture输入w、wq、ni、nih、niha、nihao，private config；不会发送桌面按键、显示窗口或修改生产数据。

| 阶段 | 基线P50范围 | 修复P50范围 | 基线P95范围 | 修复P95范围 |
|---|---|---|---|---|
| 状态芯片更新/布局 | 0.748–0.833ms | <0.001ms | 0.910–0.979ms | <0.001ms |
| 候选内容更新 | 1.117–1.123ms | 1.116–1.140ms | 1.218–1.322ms | 1.215–1.234ms |
| 定位布局 | 0.664–0.788ms | 0.704–0.797ms | 0.933–1.000ms | 0.930–0.942ms |

首次状态仍实际渲染，修复侧状态最大值1.519–1.613ms，未消除必需的首次工作。不同阶段分位数不能相加当总P95。微小差异不作统计显著性结论，未声称优化其他阶段。观测到约0.75–0.83ms稳态重复工作被避免，**不能宣称历史21.2ms已降到16ms以下**。没有客户端setMarkedText、IMK调度和屏幕合成计时，原生耗时仍待新签名包。

## 验证与复现

- `python3 platforms/macos/tests/test-candidate-presentation.py`通过，9.155s；实际AppKit候选焦点/分页/状态变化/几何/亮暗等既有回归。
- `scripts/check-clean.sh platforms/macos/build.sh --strict`通过；本地ad-hoc构建未安装。
- `make verify`全绿，200项既有产物网络符号门禁通过。
- 探针：[112-evidence/phase.swift](112-evidence/phase.swift)；全数列/环境/源码与可执行/词表SHA见[summary.json](112-evidence/summary.json)。原始.stderr及三对结果保留本机`platforms/macos/build/perf-241/`。
- 用`swiftc -O -warnings-as-errors`编译探针及ImeSession.swift/Config.swift/CandidateWindow.swift，链接release libime_ffi.a与Cocoa；从仓库根运行，每次提供新临时config.toml路径。baseline使用594c8c6 CandidateWindow，candidate使用本报告同提交源码。每轮只使用私有根，临时根结束删除。

下一步合并审查后与双高亮修复同包，再定位真实客户端回写/窗口更新成本并复测。当前没有重写Rust引擎、放宽16ms或新增接受例外。
