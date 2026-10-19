# HANDOFF — 当前状态

## 0. 元信息

- 更新：2026-10-19 18:10 / pi（deepseek-flash）· **HUD 全矩阵通过（报告 096）；Finder 搜索框已修**
- 分支：`main` @ `bc0347e`（本轮末尾另提交报告 094）
- 阶段：A 装 `a278d70`（执行 `0198bda1…`）；Finder 桌面不显示 ✔、Finder 搜索框显示 ✔、TextEdit 文末/空文档 8pt ✔、Terminal 显示 ✔
- 最近验证：`make verify` 全绿（212 产物）；A 的 D2/D3 （设置首开分区、关于瞬时不出窗）本轮均未复现

## 1. 安装与数据

| 设备 | 系统 | 已装包 | 状态 |
|---|---|---|---|
| A（`bot`，Intel / macOS 13.7.8） | x86_64 | `17053e1`（`535d546f…`） | 报告 094；`--purge-data` 全新安装，旧包/旧数据在 `uninstalled/bundle.PuMacz`、`uninstalled/data.xLySk8`；`config` SHA `3bc1117c…`（全模板、`mode=mixed`、`alt+f`、零 `ctrl+shift`）、词库 5 行、输入源 ABC、宿主 6164 |
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

- **发键事故与铁律（报告 099）**：验收中 QQ 抢到前台，按键可能进了用户输入框（未发送）。已加 `guard-focus.sh`，
  技能写明「每批发键前必须过闸门、失焦即终止记 BLOCKED」。真实 IMK 验收只在私有数据根（ADR-215）+ 自建文档下跑。
- **A 工具链差异（影响验收方式）**：`make macos-offline-tests` 在 A 必红——Swift 5.8.1 编译不了若干测试（异质字面量）
  + 高负载下 `swiftc` 超时；Swift 侧以 CI（Swift 6.3.3）为准，A 只跑 Rust `make verify`、Python 离线回归与原生探针。
- **HUD 已收口（报告 095/096）**：D7（Finder 桌面误显示）、D12（终端不显示）、Finder 搜索框不显示、TextEdit 文末偏移
  全部修复并在 A 真机确认。判据均为通用属性：客户端属于前台应用 / 光标在屏内 / **光标落在前台应用普通窗口（层号≥0）内** /
  `attributes` 两趟回退后才退 `firstRect`。剩余差异仅「Terminal 垂直约 16pt」（客户端矩形语义）。
- **A 机平台差异已清**：D2（设置首开分区）与 D3（关于瞬时不出窗）本轮均未复现；新记 D9（面板 531×70 vs B 538×70 字体度量）、D10（⇧ 合成事件成对）、D11（HUD 不在 AX 树内）。
- **终端 Meta 冲突**：裸 `⌥+字母` 与 zsh/readline 的 `M-f/M-b/M-d/M-t/M-l/M-p/M-m/M-a/M-,` 重叠；改 `⌃⌥`（VO 冲突）或英文模式让位，待用户决定。
- **发布门禁**：I1 已完成；I0（IT-01/03）、I2（IT-10/11、16…22）、I3（IT-12/23）、I4（IT-13…15）未关闭。IT-13 对 `17053e1` 的 dry-run 已通过。
- **A 平台差异**：macOS 13 的设置默认分区（D2）与关于窗口瞬时不出（D3）需在 A 复验。
- **IT-12 真实性能/IT-23 五日试用**：需先完成 IT-01 隔离验收再采真实 IMK 证据。
- **TCC 副作用**：排查截图时执行过 `tccutil reset ScreenCapture`，各应用录屏授权可能需重新勾选。

## 4. 下一步

### 4.1 A 机全新安装 + 验收 — ✅ 已完成（报告 094）

安装：重启后用 `clean-install --input-source-removed --purge-data`，旧包/旧数据进 `uninstalled/`；
执行 SHA `535d546f…`；用户在系统设置添加「萤火虫」后 `selsrc` 选中；验收后输入源还原 ABC。
结果：a–g、i、j 全 PASS；h 只有「无焦点」「空文档」两项仍弹 HUD（D7/D8）。

### 4.2 下一步

1. ✅ HUD（D7/D12/Finder 搜索框/TextEdit 8pt）已完成，见报告 095/096。
2. **IT-01（进行中）**：报告 097 已在 A 拿到原生 TextEdit 所有权协议真实通过（normal/failure）与四路径 PASS，
   并修好 macOS 13「关闭文档后窗口对象被销毁」导致的误判；**未关闭**的子项：
   IMK 学习数据隔离、独有身份包注册/TIS 枚举、Safari/Terminal 协议、完整剪贴板与输入源恢复实机证据、微信草稿（BLOCKED）。
3. ✅ **ADR-215 已真机验证（报告 098）**：`LAMPYRIS_SUPPORT_DIR`（绝对路径）可把宿主数据根重定向到私有目录，
   配置与词库都随之一并隔离 → 之后即可安全地跑真实 IMK 验收（IT-01 的核心前提）。
   实测：宿主 `ps eww` 带该变量，私有根写入 config+词库，真实目录无新增；还原后真实 config/词库 SHA 与装前一致
   （`3bc1117c…` / `d6054fc7…`）。**验收结束必须 `unsetenv`**；本地换包不想动用户数据时用 `--keep-data`。
4. ✅ **真实 IMK 验收已在隔离根跑通（报告 099）**：`wq→你`、`nihao→你好`、Esc 取消、候选头（输入码/页码/五笔·拼来源/状态芯片）、
   配置热更新（外部改 count 7→5 页数 39→54→39）全部 PASS；真实 config/词库 SHA 与装前一致。
   **发键铁律**：每批 `typekeys`/`keymod` 前先 `guard-focus.sh TextEdit`（本轮曾因 QQ 抢前台出过事故，已修）。
5. ✅ **独有身份包注册已摸清（报告 100）**：软链方式 `lsregister` 失败 `-10811`（BLOCKED），**实体包方式 PASS**
   （枚举到 2 个自有身份，清理后用户源集合不变）→ 后续 IMK 隔离验收走实体包。
   工具修复：`source-state.swift` 显式字典类型（Swift 5.8 可编）、`isolated-imk.py` 支持 `LAMPYRIS_IMK_TEST_OPT`（A 上 `-Onone` 仍需 14 分钟）。
6. **实体独有包安装/启用 — BLOCKED（本机缺 Developer ID，报告 100 追加）**
   - 已构建并安装：`~/Library/Input Methods/LampyrisIMKTest-86bde0d0-217d-4a44-a6d4-38d0f60eda9e.app`
     （ad-hoc 签名、独有身份 `cn.jokerhub.inputmethod.LampyrisIMKTest.<UUID>`、已 `lsregister -f` 注册）；
   - 私根：`/private/var/folders/…/T/lampyris-imk-86bde0d0-…/`（含 `source-state` helper 与私有数据）；
   - 实测：该包 **ad-hoc 签名**、`spctl` rejected、本机 `security find-identity` = 0 个身份 →
     System Settings「＋」列表看不到它；`TISEnableInputSource` 仍返回 0 不生效。**不是重启问题**；
   - 已清理该 app 与私有根；用户源集合/真实数据未受影响（真实 config 内容仍为默认值，SHA 因重写变为 `809e2cae…`）；
   - **已决定（用户同意）**：Safari / Terminal 探针与 TextEdit 探针同源依赖「已装且 Developer ID 签名的独有包」，
     一并记 **BLOCKED（缺签名能力）**，转 **IT-14** 用最终签名包补验；不绕过、不伪造 PASS。
     IT-01 现有证据链：097 所有权 / 098 数据根 / 099 真实 IMK（正式包+私有根）/ 100 独有身份注册枚举。
   - 收尾：移除该输入源 → 删除该 app → `rm -rf <root>` → 复核用户源集合与真实数据 SHA。
7. 之后：IT-03 正式逐项报告 → IT-12 性能 → IT-14/15 → tag/Release。

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

- 2026-10-19 / pi：**HUD 预期澄清 + ADR-214 修复**。用户确认：空文档有光标应显示（撤销 D8）、终端有光标应显示（D12 缺陷）、Finder 无文本焦点不应显示（D7 成立）。改 `StateHUDCaretResolver`（firstRect 优先、attributes 仅 length>0 兜底）+ `candidate.hud-source` 断言；A 的 Swift 5.8.1 同源编译小程序 5/5 PASS；待新包复验。
- 2026-10-19 / pi：**A 机全新安装 `17053e1` 并验收（报告 094）**。重启后 `--purge-data` 安装（执行 `535d546f…`、旧数据进 `uninstalled/`），首次配置 `3bc1117c…`（全模板、`alt+f`、零 `ctrl+shift`）；a–g/i/j 全 PASS，D2/D3 未复现；**h 的两项 FAIL**：Finder 前台时 HUD 仍显示（(64,658)）、空文档仍显示（(98,46)）→ 记 D7/D8 待 ADR 定夺；macOS 13 上 HUD 不在 AX 树内，改用 CGWindowList + 像素 OCR 取证。

- 2026-10-18 / pi：**A 机换包前置就绪，停在注销前**。包已下载解压并核对 zip `02b70dfd…`/执行 `535d546f…`（codesign+staple OK），dry-run 通过；A 实际 config `48259b19…`（`mode=mixed`，显式 hotkey 仅 `ctrl+shift+m` 残留、词库 996 行），与旧 HANDOFF 写的 `907998e6…`/`mode=wubi` 不符，已按实测订正；萤火虫源已移除但宿主 67948 未退出，按边界不杀进程、不热替换。

- 2026-10-18 / pi：**交接：B 新 UI 验收通过、A 待装**。B=`17053e1`（执行 `535d546f…`），config `3bc1117c…`，ABC；CI/出包双绿；A 的 SSH 公钥被拒，待授权或本机执行；发布门禁 I0/I2/I3/I4 未关闭。
- 2026-10-18 / pi：**用户 UI 验收通过**。候选头部字号统一 12pt、芯片/悬停留白、翻页光学对齐均确认；CI/出包双绿。
- 2026-10-18 / pi：**头部字号/留白真机通过（报告 093，`17053e1`）**：输入码/芯片/页码 12pt，芯片高 20、留白 12，悬停 6/2pt；面板 538×70。
- 2026-10-18 / pi：**翻页光学对齐真机通过（报告 091，`ba767ac`）**：翻页组上提 1.5pt，AX 中心 132/132.5 vs 芯片 134。
- 2026-10-18 / pi：**修复 CI pinyin-data 漂移（报告 090）**：URL 固定到 commit `923b108d`，SHA 不变；生成物无 diff，CI 转绿。
- 2026-10-18 / pi：**状态 HUD 光标跟随真机通过（报告 087，`ae84601`）**：去掉动画（后台宿主 alpha 卡 0）、优先 `client()`、空行回退最近字符；无焦点不显示。
- 2026-10-18 / pi：**全/半角默认改 `⌥F`（ADR-210 / 报告 079）**：避开 ChatGPT `⌥Space` 冲突；已有显式配置不覆盖。
