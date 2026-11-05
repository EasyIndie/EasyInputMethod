# HANDOFF — 当前状态

## 0. 元信息

- 更新：2026-11-06 / pi（**air 本机**）。阶段：**1.0.0（MVP）与补丁 1.0.1/1.0.2 均已发布；1.1.0 / build 38 候选已装 air，待「装机复验 → tag/Release」**。
- 分支：`dev` @ `393318c`（= `origin/main`，PR #223 merge）；开放 PR **0 个**。本轮复跑：`make verify` PASS（107 产物零网络符号）、`make macos-offline-tests` **56 文件 / 303 例 PASS**、`tools/check-level1-codes.py` PASS、`make eval-candidates` 与报告 228 数字一致。
- 版本：`Cargo.toml` = **1.1.0**、`packaging/build-number` = **38**；站点仍为 `v1.0.2 · 构建 37`（1.1.0 未发布），最新 tag `v1.0.2`。
- 1.1.0 候选身份（CI success @ `393318c`）：ZIP `448d3170fdcb…`、源码 `e0b9536b2994…`、宿主执行 `d3c5a2efd1ae…`。

## 1. 设备与数据

| 设备 | 已装包与执行 SHA | 数据 / 输入源 | 恢复点 |
|---|---|---|---|
| **air**（arm64 / macOS 27.2 / Xcode 27，用户 `joker`；pi 跑在 Background 会话，驱动不了 GUI 点击） | **1.1.0 / build 38**（候选），宿主执行 `d3c5a2ef…`，宿主 PID 59867；输入源 `Lampyris.default` 在用 | config `5d4271fb…`（`full_width=half` 已是 ADR-305 枚举形态）、词库 1139 行（用户在用，行数会变） | `uninstalled/`、`updates/` 可回滚到 1.0.0…1.0.2 |
| **pro**（Intel / macOS 13.7.8，用户 `bot`，SSH 别名 `pro`） | **1.0.0 / build 34**，宿主执行 `94394884…`（**未升到 1.1.0**） | config 与词库保持 1.0.0 基线（`show_wubi_learning=true` 是用户有意设置） | 升级前有 `uninstalled/bundle.*` |

## 2. 本轮完成（2026-11-05，1.0.0 → 1.1.0/build 38）

| 范围 | 结果 |
|---|---|
| **1.0.1（ADR-305 / 报告 225，build 35）** | `input.full_width` Bool → 枚举（半角/全角，标题「字符宽度」），⌥F 改为写配置与 ⌥P/⌥T 对齐，旧布尔配置只读兼容。 |
| **1.0.2（ADR-306 / 报告 226，build 37）** | `stopHost` 在自更新时把自己 SIGTERM 掉 → 已修；1.0.0→1.0.1 真机演练 + 1.0.2 复验闭环（回执 `payloadSHA256=732756e5…`、更新程序 bundle 被替换并备份、staging 清理、进程未自杀）。 |
| **B 基线采集（报告 227）** | `tools/eval/` 200 条样本（单字/两字词/三四字/混排长句/一级二级简码）+ `ime-eval` 评测器 + `baselines/1.0.2-build37.json` 入库，任意包可一键复跑。 |
| **1.1.0 代码（ADR-304 / 报告 228，build 38）** | D17 一级简码 25 条入表（`data/sources/wubi86-level1-codes.tsv` + `tools/check-level1-codes.py`）+ `personalize` 改「有界位次上移」（首选位保护、不跨精确/补全分块）。评测：`jianma1` 命中 56%→100%、首选 32%→100%，ALL 命中 92.0%→97.5%、首选 85.5%→94.0%，其余类别零劣化；5 条核心单测改动/新增。 |
| **air 装机** | 1.1.0/build 38 候选已装 air（执行 `d3c5a2ef…`），证据 `platforms/macos/build/acceptance-air-1.1.0-b38/`。 |
| **自动探针（报告 229）** | 用户授权后跑 `acceptance-auto.sh`：热键/上屏 **8/8 PASS**、TextEdit 实键入 `你你好。` PASS、已装包=候选包与数据表 25 条简码 PASS；**性能门禁改判 BLOCKED**（自投递不计 IME，见 §3），Safari/Chrome/Xcode 回读为空 BLOCKED。工具链三处缺陷已修：相对 `OUT` 导致测速空结果、性能项排在客户端矩阵之后（矩阵结尾还原 ABC 会抢源）、终端项误投用户 shell。 |

## 3. 未决

- **性能门禁口径待修（报告 229 §3.1，优先）**：`perf-session.sh --self-post` 把事件直接塞进测试窗口队列、绕开 IMK，`round-*.json` 里 `has_non_ascii=false`/`keys_seen=0` 却仍算出 `p95 7.19ms` 判 PASS——**历史 p95 数字（报告 191/199/207）不能直接继承，需在修好的 harness 上复核**。同一条 app 走 HID 时 `keys_seen=16`、`text=你你好学习。`，证明 IME 正常。现在已改成丢弃无效 round、无有效样本输出 `BLOCKED`（退出 78）。
- **1.1.0 装机复验未做**：IT-25 原生验收、IT-22 受影响行复跑（简码会改所有 1–2 码行为）、样本集四项指标在**装机包**上的对比、三天自用（计划 §4 轻量口径）。探针只能覆盖热键/TextEdit（报告 229）。
- **客户端回读缺口**：Safari（macOS 27 标题不随输入更新）、Chrome（Chrome 侧问题）、Xcode（编辑器未取焦点）在自动矩阵里是 BLOCKED，需人工补；终端项已从自动矩阵移除，走 IT-22 §3.5 人工。
- **pro 仍是 1.0.0/build 34**：未装 1.1.0；「两台设备同包」与「升级路径」未完成。建议让 pro 保持 1.0.0，等 1.1.0 Release 上线后**用它自带更新程序升级**（一次同时验证同包与升级链）。
- **D17-bis 二级简码 625 条未登记**：不入库就是不上线（报告 228 §4），`jianma2` 基线 93.3% 首选维持不动。
- **1.1.0 未发布**：无 tag/Release/Pages/`docs/releases/1.1.0.md`；站点仍 `v1.0.2 · 构建 37`。
- 旧账（与本批无关）：`install.sh` 新文案在 pro（macOS 13）复验；`AppleKeyboardUIMode=0` 导致设置面板 Tab 无效（系统默认，非缺陷）。
- 已知行为（写进发布说明）：⌥M 切到无候选的模式时，候选窗隐藏、编码以预编辑文本留在输入框，用户按 Esc 取消或继续补码。

## 4. 下一步（1.1.0 收尾，按顺序）

1. **机器可判部分（air，无需换包）**：
   ```sh
   make verify                 # fmt-check + lint + test + deny + verify-no-network
   make macos-offline-tests    # Swift/打包/脚本离线回归
   python3 tools/check-level1-codes.py
   make eval-candidates EVAL_JSON=/tmp/after.json   # 对比基线见 tools/eval/README.md §4
   ```
   判定：零诊断全绿；`jianma1` 命中/首选明显改善、其余类别 `hit%`/`first%`/`keys` 零劣化。
2. **装机复验（本机图形会话 + 用户在场）**：IT-25 原生验收（`docs/tasks/T-ITER-25.md`）、IT-22 受影响行复跑（`docs/tasks/T-ITER-22.md`，重点关注简码页、四码自动上屏、混输兜底位）。
3. **三天自用**：1.1.0 装包后自用 3 天再 tag（计划 §4）；期间不换包，「换包后确认新二进制」必做（报告 220 教训：`lsof … | grep -c deleted` 必须为 0）。
4. **发布（需用户明确授权）**：`git tag -a v1.1.0` 打在**验收候选提交** `393318c` → Release → 核对资产（ZIP `448d3170…` 逐字节一致、DMG staple/spctl、appcast `sparkle:version=38`）→ dispatch Pages → 写 `docs/releases/1.1.0.md` → 站点回读 `v1.1.0 · 构建 38`。
5. **pro 升级**：Release 上线后让 pro 用自带更新程序 `1.0.0 → 1.1.0`（同包 + 升级链一次闭环），升级后核 `payloadSHA256`、执行 SHA `d3c5a2ef…`、config/词库保留。
6. 之后：D 排序观察期（ADR-304 P2/P3，有证据才做）→ E 拼音深化 / F 平台扩展 / G 数据教学（`docs/MVP后执行计划.md`）。

## 4.1 换到 air 后怎么开工

| 项 | 值 |
|---|---|
| 系统 / 架构 | macOS 27.2 / arm64，用户 `joker`，SSH 别名 `air` |
| 仓库 | `~/Documents/EasyInputMethod`（先 `git fetch origin --prune && git switch dev && git merge --ff-only origin/main`） |
| 已装包 | **1.1.0 / build 38**（候选，宿主执行 `d3c5a2ef…`），输入源在用，不要重装 |
| 证据目录 | `platforms/macos/build/acceptance-air-1.1.0-b38/`（候选 ZIP/源码 + 安装记录）；旧候选目录已按用户决定清理 |

```sh
cd ~/Documents/EasyInputMethod && git fetch origin --prune && git switch dev && git merge --ff-only origin/main
git log --oneline -1                        # 记下这个提交
./scripts/handoff-status.sh --for=device    # 重采已装包执行 SHA / config / 输入源 / 词库行数
make verify                                 # cargo 门禁
make macos-offline-tests
```

**air 已知平台差异（别当 bug）**

- `q ` = 「多」（五笔一级简码），首个按键常被窗口激活吞掉 → 探针串看起来像「多你好。」。**1.1.0 起一级简码 25 字都是 1 键首选，探针串开头会多出简码字，属预期。**
- Safari 的输入区要读 AX（macOS 27 标题不随输入更新）；TextEdit 焦点属性读不到时回退窗口文本区。
- VoiceOver 掉 ABC 已复测**不可复现**（报告 215）；日志里 `Refusing connection name` 来自搜狗，与萤火虫无关。
- 内存口径用**私有已提交**（ADR-292），`footprint` 只作参考。
- 键入类验收必须在**本机图形会话**，不能 SSH。
- `launchctl setenv` 传不进 launchd 拉起的宿主，诊断开关用文件 `~/Library/Application Support/Lampyris/hud-diag`。

**air 验收命令（本机终端）**：`make macos-auto-acceptance`、`./tools/macos-probe/quality-samples.sh`、`./tools/macos-probe/memory-gate.sh`（会重启宿主，需授权）、`MINUTES=5 ./tools/macos-probe/soak-session.sh`。

## 5. 边界

- 核心零网络/零遥测；配置只经 `ime-config`；不手改 `config.toml`、不写 UserDefaults、不动 HIToolbox，不清用户数据。
- **未经授权不换包、不切输入源、不重启宿主、不创建 tag/Release**。装包/卸载/重启都要单独授权，且先读 `.agents/skills/iterate-macos-ime/SKILL.md` 记录 ZIP SHA + 执行 SHA。
- **卸载只允许**：隔离 drill 构建（私有根）、或用户明确授权后对生产位执行；删真实安装前先确认回滚备份存在。
- 改系统工具链（重装 CLT）需用户授权。
- 发键前必须 `guard-focus`（报告189 事故）；`--hid` 面向当前前台应用。
- `show_wubi_learning=true` 在 pro 上是用户有意设置，不要「还原」。
- 只用自建文档与自有会话；失败即停并保留证据。

## 9. 会话日志（最近）

- 2026-11-06 / pi（air）：**1.1.0 装机跑自动探针（报告 229）**。热键 8/8 与 TextEdit 实键入 PASS；性能门禁改判 **BLOCKED**——`--self-post` 不计 IME（ASCII 直通被当成 p95 7.19ms），历史 p95 需复核；客户端 Safari/Chrome/Xcode 回读为空。修工具链三处（相对 OUT、性能在矩阵前、终端项不再往用户 shell 打字）。输入源/config 已还原 `5d4271fb…`。
- 2026-11-06 / pi（air）：**交接对齐现实**。HANDOFF 原停在 1.0.0，实际已走到 1.1.0/build 38（1.0.1 ADR-305、1.0.2 ADR-306 自更新闭环、B 基线报告 227、C 简码+位次上移报告 228）。air 已装 38（`d3c5a2ef…`）、pro 仍 1.0.0/build 34；站点 `v1.0.2 · 构建 37`。下一步 = 1.1.0 装机复验 → tag/Release（§4）。
- 2026-11-05 / pi（air）：**1.1.0 代码入库（ADR-304 / 报告 228，build 38）**。一级简码 25 条（D17）+ 有界位次上移；`jianma1` 56%→100% 命中、首选 32%→100%，其余类别零劣化；PR #223 → main `393318c`，air 已装候选。
- 2026-11-05 / pi（air）：**B 基线采集（报告 227）**。200 条样本集 + `ime-eval` 评测器 + `1.0.2-build37` 基线 JSON 入库，改排序前后可一键对比。
- 2026-11-05 / pi（air）：**更新器自更新闭环（ADR-306 / 报告 226，1.0.2/build 37）**。`stopHost` 自杀缺陷修复后在真机复验通过，回执、备份、staging 清理全部核对。
- 2026-11-04 / pi（air）：**MVP 正式发布 `v1.0.0`**（tag → Release `41888742821`，ZIP `a7f89ee1…` 与候选逐字节一致，DMG staple/spctl 通过，appcast `sparkle:version=34`，Pages 上线 `v1.0.0 · 构建 34`）。
