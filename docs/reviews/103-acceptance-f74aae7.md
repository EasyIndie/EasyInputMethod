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

`acceptance-results.py check` → **pass 11 / fail 0 / skip 0 / blocked 12**（门禁仍为 BLOCKED，符合预期）。

| 结果 | 用例 |
|---|---|
| PASS（11） | `resource-isolation`、`state-restoration`、`core-input`、**`focus`**、**`light-dark-layout`**、**`multi-display`**、`package-validation`、`intel-macos13`、`application-TextEdit`、`application-Safari`、`application-Terminal` |
| BLOCKED（12） | `long-composition`、`undo`、`mode-switch`（均未在新候选复验）、`sleep-wake`、`accessibility`、`imk-performance`、`arm64-macos27`、`independent-reproduction`、`one-person-five-days`、`application-Chrome`、`application-VSCode`、`application-WeChat` |

### 2.1 本轮新增的真机证据

- TextEdit / Safari / Terminal 各四路径（normal/failure/INT/TERM）共 12 次运行全部 PASS，
  每次都核对「输入源与启用集合还原」「真实 config/词库未变」：`103-evidence/103-probes.txt`。
- 面板探针（`run-installed-hud-probe.py --second-display`）PASS：
  候选 599×70 与 HUD 96×36 均 `onScreen=true`、跟随客户端窗口换屏、暗色下 HUD 可见、前台始终是 TextEdit：
  `103-evidence/103-hud-probe.json` 与三张截图。
- 离屏逐场景验收 67 个观测全绿（绑定当前源码树摘要）：`103-evidence/103-local-acceptance.txt`。

### 2.2 说明

- 设备 A 上的真机证据来自**同一份 IME 源码**的隔离身份包（本地构建，ad-hoc 签名）：
  CI 候选包不允许热替换用户的生产输入法，隔离包按 ADR-129/216 的流程使用；生产包与真实数据全程未动。
- `long-composition` / `undo` / `mode-switch` 在 101 候选上有证据，但本轮未在新候选复验，按规则记 BLOCKED。

## 3. 未决与下一步

| 项 | 现状 / 下一步 |
|---|---|
| `application-Chrome` | Chrome 不把页面按键路由给隔离输入法：同一 fixture 下字母原样落进 textarea（页面用标题通道自报状态），宿主在运行、源已选中。疑似 Chrome 输入上下文陈旧 → 需重启 Chrome 复测；探针与 fixture 已就绪（`run-installed-chrome-probe.py`、`chrome-fixture.py`） |
| `application-VSCode` | 无 AppleScript，需走 AX 通道；探针未写 |
| `sleep-wake` / `accessibility` | 需用户配合：让机器睡眠一次；允许开启 VoiceOver |
| `imk-performance` | 需宿主级 IMK 延迟/内存/唤醒采集（IT-12） |
| `arm64-macos27` / `independent-reproduction` / `one-person-five-days` / `application-WeChat` | 结构性阻断（B 机 / 第三方 / 5 日 / 微信无隔离草稿） |
