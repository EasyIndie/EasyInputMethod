# 103 — 新候选 `f74aae7`（含 HUD 修复）设备 A 验收

2026-10-20，A（Intel / macOS 13.7.8）。候选来自 CI `macOS Acceptance Package`（run `39355475336`，全部步骤成功），
用于记录 ADR-217 之后的验收状态；候选 07bbb2f 的记录仍留在报告 101（其 `focus` 为 FAIL）。

## 1. 候选身份

| 项 | 值 |
|---|---|
| commit | `f74aae718c4f3df494854e2c5e974769aab9d2e8` |
| 包 | `Lampyris-0.1.0-universal.zip` · sha256 `fff5e539…b1c57`（`.sha256` 校验 OK） |
| 可执行文件 | `Contents/MacOS/Lampyris` sha256 `5cfb4c44…0743` |
| 架构 / 签名 | `x86_64 arm64` · `codesign --verify --strict` ✓ · `spctl` accepted（Notarized Developer ID）· `stapler validate` ✓ |
| 源码包 | `Lampyris-0.1.0-source.tar.gz`（同 run） |

证据：`103-evidence/103-candidate-identity.txt`。

## 2. 结果

`acceptance-results.py check` → **pass 18 / fail 0 / skip 0 / blocked 5**（门禁仍为 BLOCKED，符合预期）。

| 结果 | 用例 |
|---|---|
| PASS（18） | `resource-isolation`、`state-restoration`、`core-input`、**`focus`**、**`light-dark-layout`**、**`multi-display`**、`package-validation`、`intel-macos13`、**`long-composition`**、**`undo`**、**`mode-switch`**、**`sleep-wake`**、**`accessibility`**、**`imk-performance`**（基线）、`application-TextEdit`、`application-Safari`、`application-Terminal`、`application-VSCode` |
| BLOCKED（5） | `arm64-macos27`、`independent-reproduction`、`one-person-five-days`、`application-Chrome`、`application-WeChat` |

### 2.1 本轮新增的真机证据

- TextEdit / Safari / Terminal 各四路径（normal/failure/INT/TERM）共 12 次运行全部 PASS，
  每次都核对「输入源与启用集合还原」「真实 config/词库未变」：`103-evidence/103-probes.txt`。
- 面板探针（`run-installed-hud-probe.py --second-display`）PASS：
  候选 599×70 与 HUD 96×36 均 `onScreen=true`、跟随客户端窗口换屏、暗色下 HUD 可见、前台始终是 TextEdit：
  `103-evidence/103-hud-probe.json` 与三张截图。
- 离屏逐场景验收 67 个观测全绿（绑定当前源码树摘要）：`103-evidence/103-local-acceptance.txt`。
- **内嵌计时（ADR-218，公证隔离包）**：按键→候选窗更新完成 **p50 14.1–14.9 ms、p95 20.6–23.5 ms、max 32.7 ms**（n=45，两次运行）；
  引擎 **p50 1.0 ms / p95 1.5 ms**；面板 42 ms（设置）/ 165 ms（关于）。结论：**引擎远低于 16 ms，端到端 p95 超 16 ms**，
  瓶颈在 IMK 客户端回写与候选窗更新。证据：`103-evidence/103-perf-trace-summary.json`、`103-evidence/103-perf-trace.jsonl`。
- IT-12 矩阵（`run-installed-perf-matrix-probe.py`，AX 轮询上界）：冷启动 197ms（暖机 216ms，启动后 RSS 11.1MiB）；
  满词库 1 万条/1.97MB → p50 173ms/p95 209ms、RSS 11.0MiB；首次简繁切换后 p50 225ms（一处 480ms 离群未定因）；
  睡眠唤醒 RSS 29.4→29.5MiB、唤醒后首批提交 732/381/298/394ms 再回落 ~225–315ms；面板维度 BLOCKED（菜单 AX 树
  不含本宿主菜单项）：`103-evidence/103-perf-matrix.json`。过程中修掉两个工具缺陷（fixture 词库权限须 0600、
  宿主按需启动偶发失效时的 open 兜底）。
- 宿主级性能基线（`run-installed-perf-probe.py`）：提交时延 n=15，p50 217ms / p95 250ms / max 276ms，
  osascript 开销 p50 115ms；空闲 CPU 0.3%；宿主 RSS 29.5–29.7 MiB。方法为 AX 轮询（含客户端更新、不含 IMK dispatch），
  IT-12 的冷启动/满词库/面板/唤醒矩阵仍未覆盖：`103-evidence/103-perf-host.json`。
- 无障碍（VoiceOver 运行下）：候选面板 AX 面完整（输入编码/页码/五态芯片/翻页按钮），状态切换后客户端仍持有焦点：
  `103-evidence/103-accessibility.json`。
- 睡眠唤醒：`run-installed-sleep-wake-probe.py` 用已验证的 TextEdit 探针做判据，睡前与唤醒后各 PASS；
  唤醒时系统偶尔把输入源重置为 ABC（已记录），探针会把「原源」重新锚定后再验证：`103-evidence/103-sleep-wake.json`。
- 新探针 `run-installed-ime-features-probe.py` 复验长组合 / 撤销 / 模式循环三项：
  8 字母提交「中国」、20 字母以标记文本有界存在且 Esc 回到「中国」；提交「你」后 ⌘Z 回退为空；
  ⌥M 循环 mixed→wubi→mixed 并能从宿主配置读回。

### 2.2 说明

- 设备 A 上的真机证据来自**同一份 IME 源码**的隔离身份包（本地构建，ad-hoc 签名）：
  CI 候选包不允许热替换用户的生产输入法，隔离包按 ADR-129/216 的流程使用；生产包与真实数据全程未动。
- `long-composition` / `undo` / `mode-switch` 在 101 候选上有证据，但本轮未在新候选复验，按规则记 BLOCKED。

## 3. 未决与下一步

| 项 | 现状 / 下一步 |
|---|---|
| `application-Chrome` | **Chrome 侧问题**：页面文本框不使用任何输入法 —— 搜狗、生产 Lampyris、隔离包三种源下字母都原样落进页面（fixture 用标签页标题自报），地址栏等原生控件正常；同机 VS Code（Chromium/Electron）正常。先选源再重启 Chrome 仍复现。探针已就绪，待 Chrome 修复/换版本复测 |
| `application-VSCode` | ✅ 四路径 PASS：自有临时文件「组合期不落盘 → 空格提交 → ⌘S 落盘 = 你seed」 |
| `imk-performance` | 基线+矩阵已采集；面板维度与 in-process 计时待补 |
| `arm64-macos27` / `independent-reproduction` / `one-person-five-days` / `application-WeChat` | 结构性阻断（B 机 / 第三方 / 5 日 / 微信无隔离草稿） |
