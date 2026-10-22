# 136 冷首键定位与宿主内存复测

## 结论

- 冷首键（build5，135 干净采样：total 42.663ms，content 15.517 / window 9.556 / preedit 7.825 / status 5.149 / caret 3.709ms）
  的候选成本里，**本项目自己的渲染代码只占小头**：离屏分阶段探针实测稳态 `update` 1.10ms（render 0.186、arrange 0.827、属性设置 0.015、AX 0.010），
  首次调用 5.73ms（render 1.78、arrange 2.65、layout 0.69）。原生 content 稳态 4.15ms、首次 15.5ms，差额主要是可见窗口的 AppKit 布局/提交，
  不在本仓库可安全改写的路径上。
- 因此**本轮不改渲染代码**：试做的「render 复用 display 结果 + 序号宽度缓存 + arrange 复用已测宽度」在离屏对照中没有可重复收益
  （update p50 1.168→1.118ms，p95 反而 1.230→1.516ms），已回退，不留未经验证的微优化。下一步要动冷首键，必须先给 content/window
  增加 schema3 子阶段（或在原生宿主用不冻结进程的采样方式）再定位，而不是继续盲改。
- 内存复测（同一 build5 宿主，系统 swap 4.14GB、另有其它 Xcode 工程在跑）：
  冷态 29.9M/峰 29.9M → 首键后 32.4M/32.6M → 六词后 34.0M/34.8M → 静置 8s 33.9M/34.8M（换出 22.3M）。
  即 **build5 宿主在压力环境下的区间是 29.5–34.8M，30MB 仍不能关闭**；与 135 的 29.5/29.9M 差异来自换出/压缩时机，不是代码回退。

## 方法

- 离屏分阶段探针：临时复制 `CandidateWindow.swift`，在 `update(candidates:)` 的 state/reset/候选循环/arrange 处插桩，
  直接读取 `RenderProbe` 的 render/set/ax/select 分项；探针与 `ImeSession` 使用真实四表数据，`autoreleasepool` 包裹，40 轮 × 6 键。
- 原生堆栈采样：`sample <pid> 2 -file …` 覆盖首个按键。**结论：`sample` 会冻结目标进程，首个按键 total 被拉到 623ms
  （content 445ms），这批 trace 不可用于时延结论**，只保留作堆栈参考；下一次若要用采样，应在按键之间采样或改用
  `spindump`/ Instruments 的非冻结模式，并在报告中明确这一点。
- 内存：`vmmap -summary`（physical/peak/Writable regions 与换出）、`sysctl vm.swapusage`、`vm.loadavg`，在冷态、首键后、
  六词后、静置 8s 四个时点保存；同一 PID、同一安装包、同一输入源。
- 收尾：marker 删除、config 语义校验、ABC 后精确停止宿主；生产包/生产数据/开发 config 未变，开发词库仅正常学习。

## 证据

- `platforms/macos/build/acceptance-136/`：`10-memory-cold-vm.txt`、`11-memory-early.txt`、`13-memory-settled.txt`、
  `14-memory-late.txt`、`12-sample-first.txt`、`15-sample-steady.txt`、`perf-136/trace.jsonl`、`sample-136.sh`。
- 离屏对照探针与其 before/after 源码在 `/private/tmp/lampyris-137`（临时，不入库）；收益不成立，故未提交源码改动。

## 边界

- 不据此关闭 16ms/30MB；不把离屏数字当原生结论；不用被 `sample` 干扰的 trace 作为性能证据。
- 冷首键优化建议单独立项：先做 schema3 子阶段（content 内的文本测量/属性设置/可见布局分层）或在低压力环境用 Instruments 抓首次绘制，
  再决定改动点。
