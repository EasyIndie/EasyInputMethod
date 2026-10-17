# 063 — 标准模式菜单实机复验：候选产品菜单未呈现，输入源需重新登录

> **更正（报告 064）**：本报告的“候选产品菜单未呈现”被**替换动作本身**污染——同一正式包换回后同样只剩 10 项、连源项都不在菜单里。该判定撤回为 INCONCLUSIVE（测试方法无效）；原始 result.json 与失败证据保留不改。旧轮 056/059/060 与 052 的结论也需在无热替换的干净会话重测。**报告 065 进一步证明**：候选菜单其实完整，缺的是“按键激活控制器”这一采集前提。

2026-10-17，用户手动解锁 B 并把会话从 SSH 切到本机 Terminal（pi + deepseek-flash）。按 062 已授权范围执行 RC-UI-01：候选 `df661d3`，执行 SHA `3099a293bfffcb38eee5584172011e3093d837f8e82900cdafc91927bb3ca87a`，本地签名未公证。A 未操作。

## 当轮基线与前置

新采基线：正式宿主 `ed2a2ea…ea96c1`、PID 15444；`mode=mixed`；输入源 `cn.jokerhub.inputmethod.Lampyris.default`；config SHA `65643c64…40c7c`；词库 SHA `51356a5f…d0ac643`。

词库 SHA 与 062 记录的 `9f6116fd…cfc9` 不同，说明两次会话之间用户实际使用过输入法；按本轮实测值作基线，不回写旧值。

授权核验：本机 Terminal 已获辅助功能（`AXIsProcessTrusted()=true`）与屏幕录制（`screencapture` 成功）；`focus-owned` 在自有文档 `menu-test.txt` 上通过。正式包 23 项菜单（`输入模式：混输` + 四状态 + 设置 + 关于）通过，`formal_baseline_menu_verified=true`，才进入候选替换。

## 实测结果

候选启动并注册后，系统输入源状态回读为 `萤火虫`；按既有流程经系统菜单重选同一源后读取产品菜单，8 秒内重复读取均为：

- 菜单共 16 项：输入源 4 项、名称头 `萤火虫`、一个标题为 `..........` 的条目，其余是系统项（编辑自定义短语、表情与符号、虚拟键盘、隐藏输入法名称、打开键盘设置）。
- 正式包同路径为 23 项，`[0,0,6] = 输入模式：混输`（含混输/五笔/拼音三个子项）、四状态、设置、关于齐全。
- 候选中上述产品项一个都没有出现，`..........` 也没有子菜单。

因此**候选在产品菜单层就没有呈现**，未进入任何模式点击：`cases=[]`、`text_sent=false`、`result.json` 记 `BLOCKED` 且 `error=test-wubi-mouse-readiness failed 3`，退出码 4（restoration_errors 非空）。不记为"模式选择 FAIL"，因为选择动作从未执行；也不据此推断根因（IMK 菜单代理、子菜单父项、ad-hoc 签名中哪一项导致，尚未定位）。

观测到该现象即按 061 约定停止：不再沿 df661d3 追加诊断补丁，PR #53 保持草稿，不合入、不发布。（该停止决定在 064 之后维持，但理由改为“测试方法待重建”。）

证据：`platforms/macos/build/native-mode-menu-20261017/live-b/` 的 `005-007`（正式基线）、`014-031`（候选菜单 AX 树）、`result.json`、`failure-trace.txt`。

## 恢复与遗留

`run-live.py` 的 finally 完成：正式包 `ed2a2ea…` 回归并通过 strict 签名核验、`mode=mixed` 恢复、config 与词库字节与基线一致（`dictionary_unchanged`/`config_bytes_unchanged` 为真）。同时 `restoration_errors` 记录 `safe source: select-ABC failed 3` 与 `final audit: final-source-status failed 3`（菜单打开后前台类别变为 lampyris，保护工具拒绝继续），保留原始错误，不改写为全绿。

更关键的遗留：恢复正式包后，本会话内系统不再提供该输入法模式源。

- `TISSelectInputSource` 对 `cn.jokerhub.inputmethod.Lampyris.default` 返回 `-50`（paramErr），输入菜单只剩 ABC。
- 已尝试并能复现的恢复手段均未成功：重启 `TextInputMenuAgent`（菜单栏标签短暂恢复为"萤火虫"后再次退化为 ABC）、`lsregister -f` 重登记 bundle、`TISEnableInputSource` 重新启用、手动启动/停止宿主。
- 期间有一次 `TISDisableInputSource`/`TISEnableInputSource` 循环，父源一度从启用列表消失；重新启用后父源与 `.default` 都在完整列表中，但模式仍未被系统采纳。
- 这些是对 062 之后首次出现的"恢复后源不可用"的**恢复尝试**，不是产品动作；未改动 config/词库，未新增权限，未注销/重启。

结论：正式包与数据是干净的，缺的是系统级输入法注册。`install.sh` 本身要求安装后"注销/重新登录"，此处同样需要**手动注销并重新登录**（或重启）才能恢复，不自动执行。重新登录后应在系统菜单确认正式包的产品项（输入模式 + 四状态 + 设置 + 关于）齐全，再决定下一步；该机制已在 064 中与热替换关联。

## 重启后复核

用户于 21:33 手动重启。登录后复核：

- 宿主由系统启动，PID 1276，执行 SHA `ed2a2ea…`（正式包）；候选不在盘上。
- TIS 当前源恢复为 `cn.jokerhub.inputmethod.Lampyris.default`；输入菜单 AX 树恢复 23 项：`输入模式：混输`（三子项）、中文/半角/简体/中文标点、设置、关于，与实机基线一致。
- config 仍 `65643c64…`、`mode=mixed`；词库 SHA 由 `51356a5f…` 变为 `0d0c231a…`（重启前后写入，未判定原因，下次动作前重采）。
- 因此"恢复后输入源不可用"是本会话内的一次性系统状态，不是包损坏：注销/重登即可恢复。

## 附加诊断（不构成候选菜单证据）

为确认"`..........` 是 AX 假象还是真实渲染"，另做了一次有界检查：临时换入候选、打开输入菜单、AX 读取 + 截图、再换回正式包（`inspect-menu.py`，记录 `d00-d05`、`diagnostic-candidate-menu.png`）。该轮里候选宿主未被系统采纳为输入源（菜单无"萤火虫"项），因此截图只显示 ABC 与系统项，**不能**作为候选菜单的证据；候选菜单结论以上面 run-live 的 AX 树为准。该脚本同样在 finally 中换回正式包并核验 SHA。

## 后续

1. 用户手动注销/重新登录；登录后先确认系统菜单恢复"输入模式：混输 + 四状态 + 设置 + 关于"，并把输入源切回萤火虫。（已完成：重启后复核通过）
2. df661d3 路径停止。若继续 RC-UI-01，需要新 ADR 选择方案（回到父项可点击+子菜单、或系统平铺），再重新构建、采基线、实机验证；不接受在当前候选上继续打补丁。
3. 062 的文档（HANDOFF/ROADMAP/报告 062）与本报告一并提交；PR #53 保持草稿。
