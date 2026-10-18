# HANDOFF — 当前状态

## 0. 元信息

- 更新：2026-10-18 23:00 / pi（deepseek-flash）· **A 机换包前置已就绪，等用户注销后执行第 ① 条命令**
- 分支：`main` @ `9581b39`（已推送；工作树 clean；仅 main）
- 阶段：A 已下载并核验 `17053e1` 包（zip `02b70dfd…` / 执行 `535d546f…`），预检 dry-run 通过；**未安装**，宿主 67948 仍活（未注销）
- 最近验证：`make verify` 全绿（182 产物）；`CI` + macOS 出包对 `17053e1` 均 success；IT-13 dry-run 通过

## 1. 安装与数据

| 设备 | 系统 | 已装包 | 状态 |
|---|---|---|---|
| A（`bot`，Intel / macOS 13.7.8） | x86_64 | `a234ef31…`（旧） | 报告 071；`config` SHA `48259b19…`（`mode=mixed`、标点中文、`full_width=true`、显式 hotkey 仅 `toggle_mode=ctrl+shift+m` 残留）；词库 996 行；输入源 ABC；宿主 67948；**未做全新安装** |
| B（`joker`，arm64 / macOS 27） | arm64 | `17053e1`（`535d546f…`） | 报告 093：UI 验收通过；`config` SHA `3bc1117c…`（`mode=mixed`、`alt+f`、显式 hotkey 8 项）、词库 17 行、输入源 ABC、宿主 17339 |

- B 最终包：`packaging/out/header-type/candidate-bZTrDz/`（zip `02b70dfd…`、执行 `535d546f…`、Notarized Developer ID）。
- A 取包：`gh run download 39135852935 -n Lampyris-macos-acceptance-17053e1e914b258d814e085f59a8460c0853179e`。
- 输入源经验：安装后必须在「系统设置 → 键盘 → 文字输入」添加（`TISEnableInputSource` 返回 0 不生效）；`selsrc` 只选中已启用源。

## 2. 本轮完成（新 UI 收尾）

| 提交 | 内容 | 报告 |
|---|---|---|
| `fba09ba` | 全/半角默认 `⌥Space` → `⌥F`（ADR-210） | 079 |
| `99c9841`…`ae84601` | 状态 HUD + 候选内联两字芯片 + 光标跟随/可见性修复（ADR-211/213） | 080–087 |
| `1932c69` | pinyin-data 固定到 commit `923b108d`（Unicode 17.0.0），修 CI SHA 漂移 | 090 |
| `60a3751`…`ba767ac` | 候选头部中心线对齐、翻页光学上提 1.5pt | 088/089/091 |
| `17053e1` | 头部字号统一 12pt、芯片高 20/留白 12、候选悬停 6/2pt | 092/093 |
| `f842262` | 记录用户 UI 验收通过 | — |

## 3. 当前未决

- **A 机新 UI 安装/验收（当前阻塞点：需要一次注销）**：A 上「萤火虫」输入源已从系统列表移除（TIS enabled 只剩 ABC / Sogou / 字符面板），但宿主 67948 自 10-18 03:42 起未退出（`uptime` 1d3h，本轮未注销）——按边界**停止在安装前**。用户注销/重启后即可续跑 §4.1。
- **终端 Meta 冲突**：裸 `⌥+字母` 与 zsh/readline 的 `M-f/M-b/M-d/M-t/M-l/M-p/M-m/M-a/M-,` 重叠；改 `⌃⌥`（VO 冲突）或英文模式让位，待用户决定。
- **发布门禁**：I1 已完成；I0（IT-01/03）、I2（IT-10/11、16…22）、I3（IT-12/23）、I4（IT-13…15）未关闭。IT-13 对 `17053e1` 的 dry-run 已通过。
- **A 平台差异**：macOS 13 的设置默认分区（D2）与关于窗口瞬时不出（D3）需在 A 复验。
- **IT-12 真实性能/IT-23 五日试用**：需先完成 IT-01 隔离验收再采真实 IMK 证据。
- **TCC 副作用**：排查截图时执行过 `tccutil reset ScreenCapture`，各应用录屏授权可能需重新勾选。

## 4. 下一步

### 4.1 A 机全新安装 + 验收（跨设备）— **已完成 0–1，剩 2–6**

0. ✅ 已做（本轮）：`git pull`（HEAD `9581b39`）、`make -C tools/macos-probe`、
   `gh run download 39135852935 …` 到 `packaging/out/a-17053e1/candidate-bZTrDz/`、
   解压到 `…/extracted/Lampyris-0.1.0-universal/`。
   核验：zip SHA `02b70dfd…` ✔、执行 SHA `535d546f…` ✔、`codesign --deep --strict` ✔、`stapler validate` ✔。
   证据：`platforms/macos/build/acceptance-a-094/00-pre-install-state.txt`、`01-clean-install-dry-run.txt`。
   注：`scripts/clean-install.sh` 正式执行**必须**带 `--input-source-removed`（Makefile 用 `ARGS=` 传）。
1. ✅ 已做：输入源已是 ABC；「萤火虫」已从系统输入源移除（TIS enabled 无 Lampyris）。
2. ⛔ **用户动作**：注销/重启（**这一步会终止 agent 会话**），重新登录后开 pi 说「继续 094」。
3. 登录后一条命令（在 `~/Documents/EasyInputMethod`）：
   ```sh
   git pull --ff-only
   rm -rf "packaging/out/a-17053e1"/candidate-bZTrDz/extracted   # 可选：重新解压更保险
   ditto -x -k packaging/out/a-17053e1/candidate-bZTrDz/Lampyris-0.1.0-universal.zip packaging/out/a-17053e1/candidate-bZTrDz/extracted/
   make macos-clean-install APP=packaging/out/a-17053e1/candidate-bZTrDz/extracted/Lampyris-0.1.0-universal/Lampyris.app ARGS=--input-source-removed
   ```
   判定：脚本打印执行 SHA = `535d546f…`；旧包/旧 config/词库进 `~/Library/Application Support/Lampyris/uninstalled/`。
   若脚本报「请先切换为 ABC…宿主退出」→ 宿主仍在跑，停下等用户注销（**不杀进程、不热替换**）。
4. 系统设置 → 键盘 → 文字输入 添加「萤火虫」，再 `tools/macos-probe/bin/selsrc cn.jokerhub.inputmethod.Lampyris.default`。
5. 验收（自建文档 `/tmp/lampyris-a/`，先按键激活；照报告 071 的探针流程，A 的菜单索引比 B 小 2，先 dump 再点）：
   a 菜单 7 行 + `⌥M/⇧/⌥F/⌥T/⌥P/⌥,/⌥A`；b 全新 config = `mode=mixed`、`⌥F`、**无** `ctrl+shift` 残留；
   c `wq`→你、`nihao`→你好、`kwwl`→中华人民共和国；d `⌘Z`（需先 `⌘A`+Delete 清空→方向键断组→两次提交，见 071）；
   e 四状态往返 + 模式三循环，每步回读 config；f 设置页快捷键 8 项、关于页按钮同行/文字居中；
   g 候选头部 12pt、芯片高 20/留白、翻页光学上提 1.5pt、悬停留白、面板 ≈538×70、行高 26；
   h HUD：聚焦文本框才显示、光标上方 8pt、空行回退最近字符、无焦点不显示；i 复核 D2/D3；
   j `⌃Space` 后立刻 Shift 不得变全角。
6. 还原：`mode=mixed`、标点中文、字形简体、输入源 ABC；核对 config 字节、宿主 PID、执行 SHA。
7. 写 `docs/reviews/094-device-a-17053e1.md`（PASS/FAIL/BLOCKED + 证据文件名），证据放
   `platforms/macos/build/acceptance-a-094/`；更新 HANDOFF/ROADMAP；`make verify` 全绿后提交推送。

### 4.2 发布门禁

顺序：**IT-01 隔离验收 → IT-03 正式逐项报告 → IT-12 性能 → IT-14/15 → tag/Release**。
下一步可先做 IT-01 的原生多应用所有权/AX/剪贴板/输入源恢复隔离验证（只用隔离测试应用，不碰真实文档）。

## 5. 授权与边界

- 不自动注销/重启/解锁；重启由用户执行。安装替换前必须切 ABC、移除输入源、宿主退出；禁止热替换。
- 配置只经 `ime-config`；不手改 `config.toml`、不写 `UserDefaults`；`--purge-data` 只移出、不删除。
- 不操作用户真实文档/聊天；失败即停并保留证据；截图/口头确认不记为正式 PASS。
- 一轮只测一个包；探针遵守 `tools/macos-probe/README.md`。
- 本轮经验：源未移除但宿主已停时可「移除源 → 终止孤儿宿主 → 安装 → 重新添加」，不等同热替换；TCC 改动需告知用户。

## 9. 会话日志

- 2026-10-18 / pi：**A 机换包前置就绪，停在注销前**。包已下载解压并核对 zip `02b70dfd…`/执行 `535d546f…`（codesign+staple OK），dry-run 通过；A 实际 config `48259b19…`（`mode=mixed`，显式 hotkey 仅 `ctrl+shift+m` 残留、词库 996 行），与旧 HANDOFF 写的 `907998e6…`/`mode=wubi` 不符，已按实测订正；萤火虫源已移除但宿主 67948 未退出，按边界不杀进程、不热替换。

- 2026-10-18 / pi：**交接：B 新 UI 验收通过、A 待装**。B=`17053e1`（执行 `535d546f…`），config `3bc1117c…`，ABC；CI/出包双绿；A 的 SSH 公钥被拒，待授权或本机执行；发布门禁 I0/I2/I3/I4 未关闭。
- 2026-10-18 / pi：**用户 UI 验收通过**。候选头部字号统一 12pt、芯片/悬停留白、翻页光学对齐均确认；CI/出包双绿。
- 2026-10-18 / pi：**头部字号/留白真机通过（报告 093，`17053e1`）**：输入码/芯片/页码 12pt，芯片高 20、留白 12，悬停 6/2pt；面板 538×70。
- 2026-10-18 / pi：**翻页光学对齐真机通过（报告 091，`ba767ac`）**：翻页组上提 1.5pt，AX 中心 132/132.5 vs 芯片 134。
- 2026-10-18 / pi：**修复 CI pinyin-data 漂移（报告 090）**：URL 固定到 commit `923b108d`，SHA 不变；生成物无 diff，CI 转绿。
- 2026-10-18 / pi：**状态 HUD 光标跟随真机通过（报告 087，`ae84601`）**：去掉动画（后台宿主 alpha 卡 0）、优先 `client()`、空行回退最近字符；无焦点不显示。
- 2026-10-18 / pi：**全/半角默认改 `⌥F`（ADR-210 / 报告 079）**：避开 ChatGPT `⌥Space` 冲突；已有显式配置不覆盖。
