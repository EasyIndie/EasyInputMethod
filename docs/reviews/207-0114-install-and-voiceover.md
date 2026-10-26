# 207 0.1.14 装机复验：候选选择与上屏播报（真机 VoiceOver）

## 1. 背景与两轮候选

| 候选 | 执行 SHA | 结果 |
|---|---|---|
| 0.1.14 build 22（`51b34d4`） | `5e6071ac…` | ❌ 装上后 VoiceOver **仍然什么都不念**；`axobserve` 收到 **0 条** `AXAnnouncementRequested`，`axsel` 读到 `AXSelectedChildren = []` |
| 0.1.14 build 23（`0b2aa24`） | `a165f05c…` | ✅ 真机 VoiceOver 复听通过（用户确认），探针也能客观抓到通知 |

**build 22 的真因**：候选文档视图从来不是 AX 元素。面板 AX 树是 `AXScrollArea → 候选按钮`（容器被拍平），所以
`accessibilitySelectedChildren()` 实现的视图对辅助技术不存在，`.announcementRequested` 也发在一个不可见元素上。
ADR-291 已按此补硬约束：**容器必须自己是 AX 元素**。

build 23 的改动（PR #186，`docs/决策记录.md` ADR-291 第 3 条同步）：

- 候选文档视图 `setAccessibilityElement(true)`（role `group`、label「候选字词」）→ AX 树变成 `滚动区 → 组 → 候选`；
- 选中候选同时设 `AXSelected`，选中变化时 post `.selectedChildrenChanged`（发在容器上）；
- 滚动区子类保留同样的选中信息，供直接读滚动区的客户端；
- 新增 `tools/macos-probe/axsel.swift`（打印 `AXSelectedChildren` 与逐项 `AXSelected`）、`axobserve` 的注册深度改成参数（默认 4）。

## 2. 真机播报复验（装机版 0.1.14 build 23）

客户端：探针自带测试窗口（`lampyris-imetype.app`，走真实 IME 往返）；按键：`wq` → → → 空格。

`axobserve cn.jokerhub.inputmethod.Lampyris`（深度 5）实测：

```
t=5.666  AXAnnouncementRequested   role=AXGroup        desc=候选字词   ← 方向键换候选：第2项，像，五笔
t=5.666  AXSelectedChildrenChanged role=AXGroup        desc=候选字词
t=8.735  AXAnnouncementRequested   role=AXApplication                 ← 上屏：像，已上屏
```

`axsel cn.jokerhub.inputmethod.Lampyris`：

| 时刻 | `AXSelectedChildren` | 逐项 `AXSelected` |
|---|---|---|
| 组合 `wq` 后 | `第1项，你，五笔，键盘焦点，首选` | `[false]`（滚动区）/ `[true,false,…]`（组） |
| 按一次 → | `第2项，像，五笔，键盘焦点` | 第 2 项 true |

对比 0.1.13（报告203）：同一条链路上 `AXAnnouncementRequested` / `AXSelectedChildrenChanged` 均为 0，`AXSelectedChildren` 不可读。

**VoiceOver 人耳确认**：换候选念「第2项，像，五笔」，上屏念「像，已上屏」，面板弹出念「输入编码 wq」仍正常。用户答复「A」。

## 3. 装机与受影响验收（历史 PASS 不继承，全部在 build 23 上重跑）

换包方式：**未再让用户移除输入源**——同一 bundle 身份、仅版本号变化（`macos-imk-dev.py` 的 `comparable()` 也只把这些字段视为可演进），
按 ADR-230「原地换包」停宿主 → 替换 bundle → 校验 → 新宿主启动即新包。旧 build 22 备份在 `uninstalled/bundle.160547`，
0.1.13 备份在 `uninstalled/bundle.aPZKev`/`bundle.6MMjbg`。

| 项 | 结果 |
|---|---|
| codesign / 公证 | `codesign --verify --strict --deep` PASS；`spctl` = `accepted source=Notarized Developer ID` |
| 版本 | 0.1.14 / build 23；执行 SHA `a165f05c…`（= 候选包） |
| `make macos-auto-acceptance` | **PASS**：混输+标点 `你你好。`、Shift 英文/中文、⌥P `。`、⌥F `１２12`、⌥T `學習`→`学习`、⌥M、客户端矩阵 4/4（跳过 1）、p50 1.29ms / p95 2.52ms / max 3.52ms、RSS +0.0MB、**0 外联连接**（`/tmp/lampyris-acceptance-b23`） |
| `quality-samples.sh` | **16/16 PASS**（`/tmp/lampyris-quality-b23b`） |
| `memory-gate.sh`（ADR-263） | **PASS**：3 轮 footprint 20.6–20.9M、稳态点 `six-words`/`idle-8s`（`/tmp/lampyris-memory-b23b`） |
| `make verify` / 离线回归 / 本地验收 | PASS / 50 套件 / 71 用例 |

### 3.1 首轮 quality-samples 的两个 FAIL 是环境问题（已定性，非产品回归）

第一次跑报 `切输入源不丢字`、`失焦再回来不丢字` FAIL（实得 `你abc` / `你abc`）。原因是**上一轮排查残留了两个 TextEdit 实例**：
`new_doc()` 用 AppleScript 建新文档（打到其中一个实例），而 `axtext` 读的是前台窗口（另一个实例），于是读回旧文档内容。
`pkill -x TextEdit` 后重跑 16/16 PASS。**这两个用例依赖「TextEdit 只有单实例」**，后续应加前置检查（见 §5）。

## 4. 本轮环境坑（写进报告，避免下次再撞）

| 坑 | 现象 | 处置 |
|---|---|---|
| 裸跑 `imetype` | 默认 `--source com.apple.keylayout.ABC`，会把当前源**切回 ABC**，之后所有键入都是裸 ASCII | 只用 `type-session.sh`（显式 `--source`），或直接用 `keytopid`；排查时别再裸跑 |
| 第三方输入源切不动 | `TISSelectInputSource`/`selsrc`/`tissrc select`/⌃Space/⌃⌥Space 都可能“返回 0 但不生效”；`AppleCurrentKeyboardLayoutInputSourceID` 仍是 ABC | 报告095 的老结论；本轮补一条：**AXPress 输入法菜单项**（`axmenu press '[1]'`）能改全局标记，但已运行的 App 与新建 App 仍按 ABC 上下文走 |
| 装了新包后已运行 App 的 IME 上下文是旧的 | TextEdit/备忘录打出来都是裸 ASCII，没有候选窗 | 重开 App（或换用探针测试窗口）；本轮 TextEdit 即使重启也没恢复，最终用 `lampyris-imetype.app` 做播报复验 |
| `axmenu` 的 `dump` 路径与 `press` 的路径差一层 | `press '[0,1]'` 报 `PATH_MISMATCH` | `dump` 的路径把菜单自身算作第 0 层；`press` 用 `'[1]'` 才是第 2 个条目（已在报告记下，未改工具） |
| `keytopid` 未收录的键名会被当文本打出来 | 发 `'escape'` 实际输入了 `esc` | 只用已收录键名（`space`/`right`/`left`/`delete`/`ctrl`…） |
| `axobserve` 注册深度不够 | 深层元素的 `AXAnnouncementRequested` 收不到 | 深度参数（默认 4），候选窗用 5 |

## 5. 待做

1. `quality-samples.sh` 增加前置：`pgrep -x TextEdit` 实例数 >1 时先关掉（或直接判 BLOCKED），避免再次误判。
2. `axmenu` 的 `press` 路径语义与 `dump` 统一（差一层）。
3. `clean-install.sh` 的「已自动注册到输入源」在 macOS 13 是假成功，改为回读 `tissrc list` 再决定措辞（报告201 的建议，仍未做）。
4. 0.1.14 尚未打 tag / 未发 Release；发布前需按 `docs/发布说明.md` 流程再走一次候选包（build 23）验收。
