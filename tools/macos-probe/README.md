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
| `keytopid <pid> <按键串> [保持ms] [间隔ms] [--hid]` | 投递合成按键；`;` 分隔，支持普通字符、`opt+f`/`cmd+s`、单独修饰键 `shift`，以及发真正 `flagsChanged` 的 `shiftc`/`optc`/`ctrlc`/`cmdc`（报告188/190）。`--hid` 面向当前前台应用，且会先校验目标 PID 就是前台 |
| `imetype --keys <串> --self-post` | 自投递模式：把 `NSEvent` 交给自己的窗口，逐键测「投递→文本变化」，输出 `latency_ms` 与 `latencies_ms`（报告191） |
| `perf-session.sh` | 键入延迟 + 稳定态内存 + 网络采样，输出 JSON 并按阈值判定（`ROUNDS`/`THRESHOLD_MS`/`RSS_LIMIT_MB`） |
| `acceptance-auto.sh` | 一键跑热键、上屏、五客户端、性能/网络；`make macos-auto-acceptance` 即调用它 |
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

跑矩阵前先确认 `mode=mixed`：`opt+m` 是持久化开关，停在五笔模式会让「拼音兜底」看起来像坏了。

## 使用守则

1. **先按键激活**：读菜单前必须先在焦点客户端里按一次键，否则读到的是系统通用菜单。
2. **一次一个字符**：多个按键在同一个进程里连发会被 IME 提前提交，`typekeys` 要逐次调用。
3. **不要热替换**：换包后重登；同一登录内只测一个包，并做 A/B/A 对照。
4. **状态还原**：测完把 `mode`、标点、字形、输入源还原，并核对 `config.toml` 字节。
5. **平台差异**：单个 `⌃.` 会被系统当取消键吞掉；菜单只渲染纯标题与真实快捷键。
