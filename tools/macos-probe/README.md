# macOS 实机验证探针

从 `build/` 里反复重建的临时脚本整理而来（报告 069 的 P6）。**只用于验证，不进入产品、不打包。**

## 构建

```sh
make -C tools/macos-probe        # 产物在 tools/macos-probe/bin/
```

需要 Command Line Tools 的 `swiftc`。Intel/Apple Silicon 各自在本机构建即可。

## 工具

| 工具 | 用途 |
|---|---|
| `axtext read\|clear [pid]` | 读取/清空 TextEdit 当前窗口的文本（AX） |
| `axmenu open\|close\|dump` | 打开/关闭输入菜单并输出 AX 树 |
| `axmenu press <json path>` | 按 AX 路径点击菜单项（如 `'[6]'` 为模式行、`'[12]'` 设置） |
| `clickitem top <标题>` | 用真实鼠标坐标点击顶层菜单项 |
| `clickitem <json path> <子项标题>` | 展开子菜单并点击子项（历史方案，仅用于对照） |
| `typekeys <字符>` | 逐键输入（一次一个字符，键间留间隔） |
| `keymod <keycode> [cmd,ctrl,opt,shift]` | 带修饰键的按键（如 `keymod 6 cmd` = ⌘Z） |
| `selsrc <source id>` | 用 TIS 切换输入源并回读当前源 |
| `tissrc list\|select\|enable\|disable` | 输入源查看/选中/启停（`enable` 在 macOS 13 起对第三方输入法**不生效**，首次添加仍需系统设置） |
| `windows` | 列出 Lampyris 的窗口标题 |
| `axfocus` | 读取前台应用焦点元素的角色/文本（跨客户端回读，报告189） |
| `imetype --source <id> --keys <串> --settle <秒> [--out <json>]` | **自建窗口 + 进程内切源 + 合成按键 + 回读文本**，用于自动化「键入路径」验收（报告188） |
| `keytopid <pid> <按键串> [保持ms] [间隔ms] [--hid]` | 投递合成按键；`;` 分隔，支持普通字符、`opt+f`/`cmd+s`、单独修饰键 `shift`，以及发真正 `flagsChanged` 的 `shiftc`/`optc`/`ctrlc`/`cmdc`（报告188/190）；另有命名键 `left/right/up/down/esc/tab/return/delete/space`（组合键同样支持，如 `ctrl+right`；报告203/204，**别写成裸 `right`——那会被当成字母打进去**）。`--hid` 面向当前前台应用，且会先校验目标 PID 就是前台 |
| `imetype --keys <串> --self-post` | 自投递模式：把 `NSEvent` 交给自己的窗口，逐键测「投递→文本变化」，输出 `latency_ms` 与 `latencies_ms`（报告191） |
| `perf-session.sh` | 键入延迟 + 稳定态内存 + 网络采样，输出 JSON 并按阈值判定（`ROUNDS`/`THRESHOLD_MS`/`RSS_LIMIT_MB`=增长上限/`RSS_HARD_MB`=绝对硬顶，报告198） |
| `soak-session.sh` | 久用验收：连续键入 `MINUTES` 分钟，采样网络/RSS，重启宿主核对词库（报告192） |
| `memory-gate.sh` | **ADR-263 的 30MB 门禁**：重启宿主 → marker → 冷态/首键后/六词后/静置 8s 四点采 `vmmap`，判定 physical footprint 与私有已提交同时 ≤30MiB（`ROUNDS` 默认 3，报告199） |
| `acceptance-auto.sh` | 一键跑热键、上屏、五客户端、性能/网络；`make macos-auto-acceptance` 即调用它 |
| `screens` | 打印每块屏幕的 frame/visibleFrame/缩放/主屏（多屏验收的坐标基准，报告202） |
| `axwins [bundleID]` | 列出指定 App 的 AX 窗口位置/尺寸/角色；macOS 13 的候选窗是 `AXSystemDialog`，用它判落点（报告202） |
| `axdump [bundleID] [depth]` | 递归打印 AX 角色/描述/值，判断辅助技术能读到什么（报告203） |
| `axobserve [bundleID] [秒]` | 记录 AX 通知（含 `AXAnnouncementRequested`），判断变化时有没有告诉辅助技术（报告203） |
| `cgwins [owner]` | CGWindowList 版窗口列表；**没有「屏幕录制」授权时列表为空**，此时用 `axwins` |
| `displaymode list\|set <index> <WxH>` | 列/切显示模式；同尺寸优先选 HiDPI（pixelWidth 更大），否则会把 Retina 切成 1x（报告202） |
| `multi-display.sh` | 逐显示器 + 全屏各测一次候选窗落点；`make macos-multi-display` 即调用它 |
| `sleep-test.py [秒]` | 执行 `pmset sleepnow` 并用「进程挂起导致的时钟跳变」判定真的睡过+已唤醒，打印睡了多久（报告204） |
| `type-session.sh '<按键串>' [--settle N]` | 一条命令跑完「起测试窗口 → 等前台 → 激活 → 投递 → 回读上屏文本」，输出 JSON（报告190） |

### 一键矩阵（报告189）

```sh
KEYS='wq nihao .' ./tools/macos-probe/client-matrix.sh   # TextEdit / Safari / Chrome / Ghostty
```

脚本对每个客户端都先过 `guard-focus.sh`，不通过就 BLOCKED；结束后把输入源还原成 ABC。

### 自动化键入的组合方式（报告188）

`CGEvent` 是否生效取决于**投递进程的 TCC 信任**，而 IMK 的 mach 服务只在 Aqua 会话里可达。实测可行组合：

1. 用 `open -n` 启动一个最小 `.app` 包（内含 `imetype`），让测试窗口落在图形会话；
2. `imetype` 在自身进程内 `TISSelectInputSource`（外部进程切源不会影响别的 App 的输入上下文）；
3. 从**受信任的终端进程**（有辅助功能授权）用 `keytopid` 向该窗口的 PID 投递按键。

直接从 SSH 会话跑 `imetype` 合成按键只会得到裸 ASCII（IME 不可达）；直接 `open` 的 App 自己发键会被 TCC 静默丢弃（`keys_seen=0`）。

**普通字符用默认 `postToPid` 即可；修饰键热键必须加 `--hid`**，否则绕过 IME 热键层。**单按 Shift 类热键要用 `shiftc`（真正的 flagsChanged）**，用 `keyDown(56)` 不会触发。

**测量延迟不要轮询字符串**：在主线程 `RunLoop` 里反复读 `textView.string` 会把 p95 从 ~8ms 抬到 ~33ms（测自己）。用 `NSText.didChangeNotification` 记时间戳。

**内存只看稳态**：宿主 RSS 会在 3–58 MiB 间上下波动（页面回收/首次触碰），阈值只对尾部均值生效；重启后立刻读数会偏高 10 倍。

**RSS 绝对值不可跨 macOS 版本比较**（报告198）：macOS 13 的 `ps rss` 计入共享库/映射文件页（同一宿主 51 MiB，而 `vmmap` footprint 38.7M），macOS 27 上同样负载只有 5–20 MiB。所以探针门禁改成「键入后相对基线的**增长**（`RSS_LIMIT_MB`/`GROWTH_LIMIT_MB`）+ 绝对硬顶 `RSS_HARD_MB`」，泄漏信号看增长。
规格里的 **`常驻内存 ≤30MB`（ADR-263）是另一套口径**：新启动宿主上 `vmmap` 的 physical footprint 与私有已提交同时 ≤30MiB，由 `tools/macos-probe/memory-gate.sh`（报告199）或 `platforms/macos/tests/run-imk-acceptance.sh` ⑪ 判定，不能拿探针 RSS 顶替。

**AX 坐标以主屏左上角为原点、y 向下**（其他屏可为负）；`NSScreen.frame` 是 y 向上的 AppKit 坐标，换算用**主屏高度**而不是包围盒高度（报告202 踩过）。

**显示模式切换或反复全屏后，已运行 App 的输入上下文可能变成裸 ASCII**（实测）：脚本每块屏开始前重置文本编辑、每次断言后清空正文，收尾按数量关掉自建空文档（报告202）。

**读出口按“静默”判定**（报告199）：`imetype` 每 0.25s 检查距最后一键是否已静默 `--settle` 秒，另有 `settle+30s` 上限兜底。不用 `DispatchWorkItem.cancel()` 做防抖——它不会阻止已排队的 `asyncAfter` 块。进程落盘后 0.8s `exit(0)`（`NSApp.terminate` 在 macOS 13 会卡在 `NSQuietSafeQuit`）。

**改完探针先重建测试 App**：`/tmp/lampyris-imetype.app` 里是 `bin/imetype` 的副本；`acceptance-preflight.sh` 会在二进制更新后自动重建（报告199 之前只在目录缺失时重建，导致“改了没效果”）。

**探针自建窗口对长拼音组合不可靠**（`zhonghua ` 会得到裸 ASCII，真实客户端正常），输入质量用例请用 `quality-samples.sh`（在文本编辑里键入 + AX 回读）。

跑矩阵前先确认 `mode=mixed`：`opt+m` 是持久化开关，停在五笔模式会让「拼音兜底」看起来像坏了。

## 使用守则

1. **先按键激活**：读菜单前必须先在焦点客户端里按一次键，否则读到的是系统通用菜单。
2. **一次一个字符**：多个按键在同一个进程里连发会被 IME 提前提交，`typekeys` 要逐次调用。
3. **不要热替换**：换包后重登；同一登录内只测一个包，并做 A/B/A 对照。
4. **状态还原**：测完把 `mode`、标点、字形、输入源还原，并核对 `config.toml` 字节。
5. **平台差异**：单个 `⌃.` 会被系统当取消键吞掉；菜单只渲染纯标题与真实快捷键。

## 一条命令跑完单机验收（报告212）

```sh
make macos-acceptance-full            # preflight → 自动验收 → 质量样本 → 内存门禁 → 状态回读
make macos-acceptance-full SKIP_MEMORY=1   # 跳过会重启宿主的内存门禁
```

产物在 `OUT=/tmp/lampyris-acceptance-full-<时间>/`：`00-preflight.json`、`01-auto.log`、`02-quality.log`、
`03-memory.log`、`steps.tsv`（每步状态）、`99-state.txt`（执行 SHA/build/宿主 PID/config/词库/连接数）。

前置检查（`acceptance-preflight.sh`）会先挡掉三类会把时间浪费掉的环境问题：**屏幕锁定**、
**客户端多实例**（TextEdit/Safari/Chrome）、**输入源未启用**；`session` 探针只读会话锁状态，也可单独跑。

## 证据索引（ADR-293）

```sh
make acceptance-evidence            # 本机已装包执行 SHA 已有的证据与仍缺项
make acceptance-evidence SHA=<sha>  # 指定 SHA
```

报告里写全执行 SHA-256 后，`scripts/acceptance-evidence.py` 会把 `docs/reviews/*.md`
按 SHA 归档并识别覆盖到的验收项（快捷键/客户端/质量样本/内存/久用/外联/VoiceOver/睡眠/多屏/Space/安装/复现/辅助功能）。
SHA 相同即可复用结论；SHA 变了必须重跑。
