# HANDOFF — 当前状态

## 0. 元信息

- 更新：2026-10-26 01:30 / pi（在 **pro 本机图形会话**里，用户已授权重启宿主与卸载重装）。阶段：0.1.13 已发布并双机装机；**pro 的自动化项全部已绿**（键入/客户端/内存门禁/久用/离线回归/本地验收/对比度/真实卸载→重装），只剩纯人工项（VoiceOver、多屏/缩放、睡眠唤醒）。
- 分支：`dev` = `main` = `179501b`（PR #177 已合并，0 开放 PR，工作树 clean）；最近 `make verify` **PASS**。具体提交以 `git log --oneline -1 origin/main` 为准。
- 发布：`v0.1.13`（`9296fb5`），执行 SHA `c3b533e4…`，air/pro 相同；ZIP `130f3098…`、DMG `2f22120c…`。
- 自动验收：air 上 `make macos-auto-acceptance` 全绿（p95 6.99 ms、稳态 5.5 MiB、0 外联）；质量样本 `quality-samples.sh` **16/16 PASS**。pro 上同样两项已全绿（报告198：p95 2.41 ms、4/4 客户端、16/16 样本）。

## 1. 设备与数据（2026-10-26 01:28 重采；数据可能继续变化）

| 设备 | 已装包与执行 SHA | 数据/输入源 | 恢复点 |
|---|---|---|---|
| **air**（本机），arm64/macOS 27.0.1 | **0.1.13/build21**（Release ZIP），执行 `c3b533e4…`，Notarized/accepted | config `809e2cae…`（mode=mixed、标点中文、半角、简体、`show_wubi_learning=true`）；词库 602 行 / `70cd11c2…`；宿主 PID 92498；输入源当前 ABC | 回滚：`/tmp/lampyris-rollback-0112/`、`-0113-prev/` |
| **pro**（Intel/macOS 13.7.8，`ssh pro`，用户 `bot`） | **0.1.13/build21**（Release DMG），执行 `c3b533e4…`；仓库 `~/Documents/EasyInputMethod` | config `2bd3fde6…`、词库 482 行（含 `show_wubi_learning` 学习写入）；宿主 PID 22911（报告199 收尾重启，冷态 footprint 2.9M）；探针 `bin/` 13 个 x86_64、0 告警 | 回滚：pro 上 `/tmp/lampyris-rollback-0112/` |

- **同一 main `73d468b6b3fea246704972e8327b9fd530c659d5` 的两份未安装附件**：宿主 run `40098075131` ZIP `3b4fb9b97025d172f50abb4bbacf1faca31bb297d64b062b61e227c9c3a8decb`、执行 `867add9fd2ced6c4c1262fac102bfd6f543316101c05507c3865a4f4915b5433`、源码 tar `5c8b8c84287863dca3995243739a5b1059e83c39ad66d062b9de51678c5ccf24`；独立更新程序 run `40098104120` ZIP `962e05c5fb5c7a949f278606829a4a3520d1123ae8483c29b53d053ea7a6c988`、执行 `0710987b30d430baf2faddd3af52349aec25ea9133f144e94011c0b14d419388`。均仍 build20，**不能冒充正式新版本/生产替换**；见报告180。

## 2. 最近完成

| 范围 | 结果/证据 |
|---|---|
| 既有发布 | 报告174：v0.1.12/build20 DMG 含图形安装/卸载；Pages 仅网站/DMG 路径；不以发布关闭最终 RC 门禁 |
| 本轮审计 / #142 | `58eefa8` 更新可靠性修复、`98c93d0` 固定 D4 原始提交；回归 28+7 项/verify/离线/双架构构建和精确 head 四 CI PASS，main `56c2457`。 |
| 报告178/179、ADR-285 | 旧 main `56c2457` 签名宿主导入 socket/connect；新 main `612020d` 签名宿主两片无这些导入，签名/公证/Gatekeeper/源 SHA、控制器符号静态 PASS；未安装、未动态验证，更新程序不在附件中。 |
| ADR-286 / #144 / 报告180 | main `73d468b` 手动诊断 run `40098104120` 成功，签名独立更新程序 ZIP/执行/SOURCE-COMMIT SHA、双架构/公证/Gatekeeper/公钥 PASS；临时负载签名与篡改拒绝 CI PASS。本地无参默认关闭、非法签名拒绝；未运行 UI/下载/安装。 |
| ADR-287 / #145 / main `37323e9` | 安装目标契约（生产固定 + UUID 隔离身份）；生产 UI 显式选择生产目标，离线私有目录安装/回滚不碰生产哨兵。updater 33+7、build/verify 与 head 四 CI PASS；离线第一轮因真实词库用户并发变化导致旧快照测试失败，顺序重跑 PASS。未签名/安装隔离程序。 |
| ADR-287 第二阶段 / #146 / 报告181 | 隔离构建需三字段（TestOnly/UUID 身份/私有根）且根为属主 0700、带 owner 标记、非符号链接、位于私有 T 或开发根，否则停用更新且不回退生产；`build.py` 拒写隔离键。updater 38+7、生产 Info.plist 无隔离键、3 项结构回归、离线/verify 与 head 四 CI PASS，main `d1e39b2`；未签名/未装包。 |
| ADR-288 / #148 / #149 / #151 / 报告182 | drill feed 定案项目 Pages 子路径；main-only `Isolated Update Drill` 用临时 Ed25519 密钥生成隔离更新程序（build = 载荷-1）、公证隔离载荷与 appcast，artifact 合并部署 `/drill/`；`--drill-run install|cancel|tamper` 仅供隔离构建。run `40112167780`/`40112916703` build+publish success；本地结构/updater 39+7/verify PASS。 |
| ADR-288 实测 / #152 #153 / 报告183 | drill 真实网络：`--drill-run cancel`（清理 false）、`tamper`（拒绝+清理）、`install` 两轮（备份/替换/receipt 0600/落地验签公证）全 PASS；修复 drill 引用别名与载荷包名不一致。生产执行 SHA/config 前后一致，未留临时目录。 |
| 报告183 UI/收尾 | 用户图形会话点击更新窗口显示「已安装构建 905」，新增 receipt/备份与落地 SHA 一致；`Pages` run `40140062574` 后 `/drill/` 404、首页 200；私有根整体删除；生产执行 SHA/config 未变。UI「取消」按钮未单独取证。 |
| 报告184 / #154 / main `167a644` | ADR-289：安装器在停宿主前以 `domainMissing` 拒绝缺失目标目录（XCTest 覆盖）；`--drill-run rollback` 在真实公证载荷上落地后注入失败 → 旧包 SHA `c9f05b97…` 恢复、work 0→0、无 receipt、临时目录清理。updater 40+7、离线/verify、四 CI PASS。 |
| 遗留清理（报告183） | 旧隔离测试源 `…IMKTest.d4fcecfb-….default` 仍启用；子源 disable 无效，改停父源后条目消失；PID 1311 精确 SIGTERM 并删除 bundle。生产源/宿主/执行 SHA/config 未变，输入源列表无 IMKTest。 |
| 报告185/186 / #155 / main `2d9c509` | 0.1.12/build20 候选静态核验（ZIP `430da00b…`）；版本递增为 0.1.13/build21 后 acceptance run `40145382687` 出正式候选（ZIP `f86959d6…`/执行 `a3faf05c…`），静态门禁与 30 秒启动零外联抽样 PASS；未安装、未发 tag/Release、站点未改。 |
| 报告187 | 用户授权后原地替换生产位为 0.1.13/build21：执行 SHA `a3faf05c…`、codesign/spctl PASS、宿主 PID 67087（11:30 采集）；空闲 30 秒 + 会话后 20 秒网络抽样 0 连接，RSS 7.8 MiB；用户人工键入报告正常，词库 519→520 学习写入，config 仅第 12 行 `show_wubi_learning` 变化。 | 配置变更只落在 `show_wubi_learning` 一行（用户有意测试 ⌥L），注释与其余 29 行不变。
| 报告188 | 键入自动化探针入库：五笔上屏「你」、拼音兜底「你好」、四码自动上屏、标点「。」、全角「１２」；键入期 28 次采样 0 连接、RSS 17–35 MiB、宿主 PID 67087（11:30 采集） 无崩溃；config 还原到 `809e2cae…`。修饰键热键须用 `keytopid --hid`；**单按 Shift 类热键要用 `shiftc`（真正的 flagsChanged）**，报告188 的「Shift 异常」已结案为探针问题（报告190）。 | 第二轮：`--hid` 通道修复 ⌥M 丢按；单按 Shift 仍异常。
| 报告189 | 客户端矩阵脚本化：TextEdit/Safari/Chrome/Ghostty 同一按键串上屏均「你你好。」（AX/标题/文件三通道回读），`tools/macos-probe/client-matrix.sh` 逐客户端 guard-focus；Xcode BLOCKED（首次启动无编辑器焦点）。一次未 guard 的投递把 `wq ` 打进用户 Ghostty（无回车、未执行命令），教训已写进脚本与报告。 |
| 报告190 | 热键矩阵自动化：Shift 中英、⌥P 标点、⌥F 全角、⌥T 简繁、⌥M 模式循环全部 PASS；`shiftc`/`type-session.sh` 入库；Xcode 纳入客户端矩阵后五客户端全绿；config 结束回到 `809e2cae…`。 |
| 报告191 | 一键自动验收 `make macos-auto-acceptance`：热键/上屏 8 项、五客户端、160 键延迟（p50 2.23ms / p95 6.43ms）、稳定态 RSS 11.8 MiB、全程 0 外联，全部 PASS；延迟测量改用 `NSText.didChangeNotification`（轮询会把 p95 抬到 33ms）。 |
| 报告192 | 久用与持久化自动化 `make macos-soak`：5 分钟 111 轮约 1.7k 键，全程 0 外联、词库 568 行重启前后一致、RSS 稳态 20.0 MiB（峰值 56.3 瞬时，尾部低于热身段 ⇒ 无单调增长）。报告说明 RSS 波动与采样时刻陷阱。 | 另新增 `test-uninstall-script.py` 6 项离线回归（假 HOME + 假 pgrep），覆盖 dry-run/保留数据/清理数据/标识不符/符号链接/未安装。
| 报告193 | 夜间回归 `macos-nightly.yml`（ADR-290）：每日 verify/离线回归/updater XCTest/探针构建/shell 语法，真实键入用 preflight 判定（78=SKIP）；发布材料 `docs/releases/0.1.13.md` 含身份表与 8 步 checklist。 | 首次运行即抓出 `test-ci-sign.py` 两处隐式依赖本地构建产物（PR #163/#164 修），第三次 run `40164726091` 全绿，验收步骤按设计 SKIP 并写明原因。
| 报告194 | **0.1.13 已发布**：tag `v0.1.13`（`9296fb5`），Release run `40166565905`；资产 ZIP `130f3098…`（= 装机复验的那个包）、源码 `f5df1166…`、更新程序 `cd34358f…`、appcast v21 签名可验、错签被拒；DMG 签名+staple 通过；站点（Pages 需手动 dispatch）与 `releases/latest` feed 均指向 0.1.13；DMG 内含安装器/卸载器/说明。 |
| 报告195 | 两台设备已装 0.1.13：air 用 Release ZIP、pro（Intel/13.7.8）用 Release DMG（sha256 校验通过），执行 SHA 均为 `c3b533e4…`；pro 数据未动（config `2bd3fde6…`、词库 474 行）、空闲 0 外联/RSS 9.7MiB。pro 上键入类自动化 BLOCKED（SSH 会话窗口拿不到前台、第三方源切不动），待用户本机执行。 |
| 报告196/197 | 固定输入质量样本集脚本（14 项，`quality-samples.sh`，执行待图形会话）+ UI 快照对比度自动化（26 张 15.58–19.77:1 全过，`make macos-ui-contrast`）+ `docs/发布说明.md` 绑定 0.1.13。本轮未动产品代码。 |
| 报告196/197 | 质量样本集扩到 16 项（含切源/失焦）在 0.1.13 上 **16/16 PASS**；同日 `acceptance-auto` 复跑全绿（p95 6.99ms）（在文本编辑里键入 + AX 回读；探针窗口对长拼音不可靠，已知坑）；UI 快照对比度 26 张全过；`docs/发布说明.md` 绑定 0.1.13。 |
| **报告198 / pro 自动化** | pro 本机图形会话跑验收：首轮 3 项 FAIL 全部归因为探针/环境 —— ① `imetype` 读出口从启动起算（慢机器截尾，`keys_seen=9/10`），② macOS 13 拒绝 `open -a Safari 'data:…'`，③ macOS 13 `ps rss` 计入共享库页（51 MiB，footprint 仅 38.7M，且再打 160 键节点数下降）。修探针三处后**全 PASS**：热键 8 项、客户端 **4/4**（TextEdit/Safari/Chrome/Ghostty，Xcode 未装 SKIP）、160 键 p50 1.29/p95 2.41 ms、25 次采样 0 外联、RSS 增长 0.2 MiB；`quality-samples.sh` **16/16 PASS**。产品代码未动。 |
| **报告199 / pro 内存门禁 + 久用** | 用户授权重启宿主后按 ADR-263 测 3 轮（新脚本 `memory-gate.sh`）：稳态 footprint **21.4–23.1M**、私有已提交 **21.7–23.2M**，均 ≤30MiB → **PASS**（冷态仅 2.9M）。`make macos-soak`（5 分钟 114 轮）PASS：0 外联、RSS 增长 0.1MiB、词库重启前后一致。同时发现并修掉报告198 的 **5 处探针回归**（`DispatchWorkItem.cancel` 对 `asyncAfter` 无效、`NSApp.terminate` 卡在 NSQuietSafeQuit、preflight 不重建旧测试 App、type-session 重发导致重复上屏与死锁、Ghostty 测试窗口残留），修后两轮 acceptance 连过。 |
| **报告200 / pro 其余自动化** | 离线回归从失败修到 **50/50 PASS**：系统 python3 是 3.9（套件要 ≥3.11 的 `tomllib`）→ `Makefile` 新增 `PYTHON`；沙盒测试把结果路径写死成新系统行为（macOS 13 在 `/var/folders/…/T/<id>`）→ 两处都查；本地验收 `candidate` 必测清单落后三个场景（方向键浏览/批量状态/内容分阶段）→ 一直全机器 BLOCKED，补上后 **6 套件全 PASS、70 用例**。另：`make macos-ui-contrast` **28/28 PASS**（最低 10.00:1）；`soak` 10 分钟带 footprint 采样 23.4→24.6M、后半段 +0.1MiB。 |
| **报告201 / pro 卸载重装** | 用户授权后真跑：DMG `2f22120c…`（= Release `.sha256`）→ `uninstall.sh`（空跑 `--dry-run` 后执行；首次因宿主未退被正确拒绝）→ bundle 移入 `uninstalled/`、`config.toml` 与词库**逐字节保留** → `install.sh` staple/spctl/codesign 全过、执行 SHA 仍 `c3b533e4…`、config `2bd3fde6…`、词库 SHA 不变 → 用户手动添加输入源后键入冒烟 2/2、质量样本 16/16、0 外联。另发现 `install.sh`「已自动注册」在 macOS 13 是假成功（建议 0.1.14 复核）。 |
## 3. 未决

- **pro 侧人工验收未做**：VoiceOver、多屏/缩放、睡眠唤醒（自动化、内存门禁、久用、离线回归、本地验收、对比度、卸载重装均已全绿，见报告198-201）。air 侧可自动化项同样已全绿。
- **长会话内存**（报告200 §4）：新宿主 21–23M，连续键入 10 分钟只 +1MiB（footprint 23.4→24.6，后半段 +0.1），「打字越多越涨」不成立；数小时尺度的收敛性需更长观测窗口，不阻塞当前候选。
- **`install.sh` 的「已自动注册到输入源」在 macOS 13 上是假成功**（报告201 §5）：`TISEnableInputSource` 返回 0 但不生效，用户必须手动添加输入源。建议 0.1.14 用 `LampyrisTIS status` 复核后再宣布成功（本轮未改代码）。
- **卸载备份待清**：`~/Library/Application Support/Lampyris/uninstalled/bundle.6MMjbg/`（执行 SHA `c3b533e4…`）确认无需回滚后可删。
- **air 侧剩余人工项**：VoiceOver、多屏/缩放/Spaces/全屏、睡眠唤醒、真实卸载→重装（air 上可照报告201 的步骤跑）。
- **pro 的平台差异**（实测，勿当 bug）：macOS 13 的 LaunchServices 不认 `open … 'data:…'`（已改成文件 URL）；`ps rss` 不能当内存口径用（见报告198）；`TISSelectInputSource` 只在**本机图形会话**里对第三方源有效。
- App Store 搜索框首次输入偶发卡顿（报告177）：未归因，暂不改代码。
- 最终 RC 仍需：第三方独立重建（IT-15）、五工作日试用（IT-23）。
- `make verify-no-network` 只做静态断言；动态零外联靠探针实测。

## 4. 下一步

1. **pro 剩余项**：手测 VoiceOver、多屏/缩放/Spaces/全屏、睡眠唤醒。自动化项已全部完成（含卸载重装，报告201），勿重跑。
2. 回 air 后补同样的手测项；两边结论写进 `docs/reviews/195-two-device-install.md` 或新报告。
3. 启动五工作日试用（IT-23）；安排第三方离线重建（IT-15）。
4. 任一 FAIL：修 → 出 0.1.14 → 受影响的 PASS 全部重跑（历史 PASS 不继承）。

## 4.1 已在 Pro 上完成的部分（报告198/199/200，勿重跑无谓项）

在本机图形会话（不是 SSH）跑过并全绿：`make macos-probe-build`（13 个 x86_64 探针、0 告警）、`make macos-auto-acceptance`、`./tools/macos-probe/quality-samples.sh`、`./tools/macos-probe/memory-gate.sh`（ADR-263）、`make macos-soak`、`make macos-offline-tests`、`make macos-local-acceptance`、`make macos-ui-contrast`。

修过的探针行为（换机器复跑时注意）：

- `imetype` 读出口现在**从最后一个按键起算**（防抖），慢机器不再截尾；
- 客户端矩阵用 `OUT/page.html` 文件 URL（macOS 13 不认 `data:`）；
- 内存门禁是「相对基线增长 ≤30MiB + 硬顶 96MiB」，ADR-263 的 30MB 另用 `./tools/macos-probe/memory-gate.sh`（会重启宿主，需授权）。

**环境事实**

| 项 | 值 |
|---|---|
| 系统 / 架构 | macOS 13.7.8 / x86_64，用户 `bot`，SSH 别名 `pro` |
| 仓库 | `~/Documents/EasyInputMethod`，本轮执行时 = `443c115`（以 `git log --oneline -1 origin/main` 为准） |
| 已装包 | 0.1.13 / build 21，执行 SHA `c3b533e4…`（与 air 相同），`spctl` Notarized |
| 数据 | `config.toml` `2bd3fde6…`、词库 482 行（含 `show_wubi_learning` 学习写入）；输入源 `Lampyris.default` 已启用 |
| 探针 | `tools/macos-probe/bin` 13 个（x86_64，0 告警）；旧副本 `~/lampyris-probe` 已无用 |
| 会话 | 验收必须在**本机图形会话**（有 Aqua/TCC）；SSH 会话只能做只读采集 |

**开工三步**

```sh
cd ~/Documents/EasyInputMethod && git fetch origin --prune && git switch dev && git pull --ff-only
git log --oneline -1        # 记下这个提交，写进验收记录
make macos-probe-build                     # 重新编译探针（x86_64，约 1 分钟）
./tools/macos-probe/acceptance-preflight.sh  # 应为 ready=true；78 = 环境不适合
```

**验收命令（在该机本地终端跑，不要在 SSH 里跑）**

```sh
make macos-auto-acceptance                 # 热键/上屏 + 客户端矩阵 + 延迟/内存/零外联
./tools/macos-probe/quality-samples.sh     # 16 项输入质量样本
./tools/macos-probe/memory-gate.sh         # ADR-263 30MB 门禁（会重启宿主，需授权）
MINUTES=5 ./tools/macos-probe/soak-session.sh   # 久用 + 词库持久化（会重启宿主）
```

**平台差异（已实测，别当 bug）**

- SSH 会话里窗口拿不到前台 → `keytopid --hid` 会打印 `BLOCKED 测试窗口未取得前台`；这是保护，不是产品问题。
- 在 SSH 会话里 `TISSelectInputSource` 对第三方源无效（本机图形会话里有效）。
- Xcode 若未安装，`client-matrix.sh` 会输出 `SKIP 未安装 Xcode`，客户端矩阵按实际尝试数判定（≥4 即可）。

**结论落点**：pro 的结果已在报告198（`docs/reviews/198-pro-automated-acceptance.md`）；手测项补进该报告或报告195。

## 5. 边界

- 核心零网络/遥测；配置只经 ime-config；不得改动真实 config/词库、UserDefaults 或 HIToolbox，不清用户数据。
- 未经授权不换正式包、不切源、不发键、不重启、不创建 tag/Release。本轮 tag/Release 已获授权并完成，后续版本仍需单独授权。
- 发键前必须 `guard-focus`（报告099/189 事故）；`--hid` 面向当前前台应用，前台可能被切走。
- `show_wubi_learning=true` 是用户有意设置，不要"还原"。
- 换包/验收前读 `.agents/skills/iterate-macos-ime/SKILL.md`，记录 main 提交、ZIP SHA、执行 SHA。

## 9. 会话日志（最近）

- 2026-10-26 / pi（pro，用户授权）：报告201 —— **真实卸载→重装（保留数据）PASS**。DMG `2f22120c…`（与 Release `.sha256` 一致）→ `uninstall.sh`（先被正确拒绝一次：helper `disable` 不停宿主）→ bundle 移入 `uninstalled/`、config/词库逐字节保留 → `install.sh` 公证/staple/spctl 通过、执行 SHA 仍 `c3b533e4…`、config `2bd3fde6…` 与词库 486 行 SHA 不变；用户手动添加输入源后键入冒烟 2/2、`quality-samples.sh` 16/16。
- 同轮发现：`install.sh` 打印「已自动注册到输入源」，但 macOS 13 上 `TISEnableInputSource` 假成功（`LampyrisTIS status` 随后为空）→ 必须手动添加；建议 0.1.14 复核后再宣布，README 措辞同步。
- 收尾状态：执行 SHA `c3b533e4…`、config `2bd3fde6…`、词库 486 行（学习计数原地累加）、输入源 `Lampyris.default` 当前、宿主 PID 69116、0 条 TCP/UDP；卸载备份 `uninstalled/bundle.6MMjbg/` 保留待清。

- 2026-10-26 / pi（pro）：报告200 —— 其余可自动化项跑完。离线回归 **50/50 PASS**（修了 python 3.9 无 `tomllib`、沙盒测试对 macOS 13 临时目录的假设、本地验收 `candidate` 必测清单落后 3 个场景导致全机器 BLOCKED）；本地验收 **6 套件/70 用例 PASS**；UI 对比度 **28/28**；10 分钟 soak 带 footprint 采样 23.4→24.6M（后半段 +0.1）→ 连续键入不涨。
- 本轮结论：pro 上除人工项与「真实卸载重装」外已无剩余自动化；产品代码未改，0.1.13 执行 SHA 未变。
- 入库：报告200 + 测试基础设施修复已进 main（PR #177，四 CI PASS），dev 已快进同步、0 开放 PR。

- 2026-10-25 / pi（pro，授权重启宿主）：报告199 —— ADR-263 内存门禁 **PASS**（3 轮新宿主：footprint 21.4–23.1M、私有已提交 21.7–23.2M，冷态 2.9M），`soak` 5 分钟 PASS（0 外联、RSS +0.1MiB、词库 482 行重启一致）。
- 同一轮抓出报告198 的 **5 处探针回归**并修好：`DispatchWorkItem.cancel` 对 `asyncAfter` 无效（防抖从未生效，改静默轮询）、`NSApp.terminate` 卡在 NSQuietSafeQuit（改 `exit(0)`）、preflight 只在目录缺失时重建测试 App（导致旧二进制）、`type-session` 重发导致重复上屏与死锁（只在前台失败时重试 + trap 杀在途 keytopid）、Ghostty 测试窗口残留抢前台（按 CAT_FILE 精确 pkill）。修后两轮 acceptance 连过、质量样本 16/16。
- 收尾状态：宿主新 PID 22911（soak 重启，冷态 2.9M）、config `2bd3fde6…` 未变、词库 482 行、输入源 ABC、无 imetype/keytopid/Ghostty 残留。
- 未决：长会话 footprint 从 ~21M 涨到 ~43M 需带 footprint 的长时 soak 定性（不阻塞）；人工项（VoiceOver/多屏/睡眠/卸载重装）仍待做。
- 入库：本轮探针修复 + 报告199 已进 main（PR #176，四 CI PASS），dev 已快进同步、0 开放 PR。

- 2026-10-25 / pi（pro 本机图形会话）：pro 自动化验收跑通（报告198）——首轮 3 项 FAIL 全是探针/环境（读出口竞态、macOS 13 `data:` URL、RSS 跨版本口径）；修 3 处探针后 `make macos-auto-acceptance` 与 `quality-samples.sh` 16/16 全 PASS，产品代码未动。
- 收尾状态：config `2bd3fde6…` 未变、词库 475→479（学习写入，不还原）、宿主 PID 85195 未重启、输入源还原 ABC、探针新增的 Safari/Chrome 标签已关闭。
- 入库：探针修复 + 报告198 已进 main（PR #175，四 CI PASS；首推漏 `Signed-off-by` 补上后重推），dev 已快进同步、0 开放 PR。

- 2026-10-25 / pi（换设备交接）：0.1.13 已发布并双机装机；air 侧自动化全绿（16/16 质量样本 + acceptance 全绿）。
- 下一步在 Pro（macOS 13.7.8/Intel）：`git pull` 到远端最新 → `make macos-probe-build` → 本地终端跑 `make macos-auto-acceptance` 与 `./tools/macos-probe/quality-samples.sh`，再手测 VoiceOver/多屏/睡眠/卸载重装。
- Pro 已知差异：SSH 里窗口取不到前台、TIS 切不动第三方源 → 必须本机终端执行；Xcode 缺失会被 SKIP。
- air 回滚点：`/tmp/lampyris-rollback-0112/`、`-0113-prev/`；Pro 回滚点：`/tmp/lampyris-rollback-0112/`。
- 交接提示词见 §4.1 + 本轮回复末尾的「继续」模板。

- 2026-10-25 / pi：图形会话恢复后跑完质量样本（扩到 16 项，含切输入源/失焦），全 PASS；同日 `make macos-auto-acceptance` 复跑全绿（p95 6.99ms、稳态 5.5MiB）。；顺带定位「探针窗口长拼音得裸 ASCII、真实客户端正常」，脚本改为 TextEdit 回读。
- 2026-10-25 / pi：补齐不依赖 pro 的部分（报告196/197）：质量样本集脚本、UI 快照对比度自动化（26 张全过）、发布说明绑定 0.1.13；质量样本执行因本机图形会话不可用而 SKIP（preflight=78）。
- 2026-10-25 / pi（收尾）：0.1.13 已发布并装上 air/pro（执行 SHA 同为 `c3b533e4…`，报告194/195）；nightly 与一键验收入库（报告191-193）。
- 决策：发布前先冻结 main、对最终候选装机复验再打 tag（版本号嵌提交，doc/CI 提交会产出同号不同包）；nightly 用 preflight 的 78=SKIP 区分环境缺失与真失败。
- 验证：`make verify` PASS；`make macos-auto-acceptance` 全绿（p95 8.68ms、稳态 10.1MiB、0 外联）；Release 资产 SHA/appcast 签名逐项核对。
- 清理：`/tmp` 与旧证据目录已删，仅留两份回滚副本；分支只剩 dev/main 且同步，开放 PR 0。
- 遗留：两台设备的人工验收（辅助功能/多屏/睡眠/卸载重装）；pro 键入自动化需本机执行。

- 2026-10-25 / pi：0.1.13 装上两台设备（报告195）：air=Release ZIP、pro=Release DMG，执行 SHA 同为 `c3b533e4…`，签名与数据保留核对通过；pro 的键入自动化因 SSH 会话限制 BLOCKED，需本机执行。
- 2026-10-25 / pi：**0.1.13 发布完成**（报告194）：冻结 main 后先对候选 `c3b533e4…` 装机复验（自动化全绿），再 tag `v0.1.13` → Release `40166565905`；资产 SHA/`.sha256`/DMG 公证/appcast 签名逐项核对，站点与 latest feed 已更新。
- 2026-10-25 / pi：夜间回归（ADR-290）合入 main，run `40164726091` 全绿（验收步骤按设计 SKIP）。
- 2026-10-25 / pi：nightly 首次运行抓出 `test-ci-sign.py` 两处隐式依赖本地构建产物（#163/#164），修后 run `40164726091` 全绿；验收步骤在无输入源的 runner 上按设计 SKIP。
- 2026-10-25 / pi：接入夜间 CI 与发布材料（ADR-290，报告193）：nightly 跑 verify/离线/updater XCTest/探针/shell 语法，真实键入以 preflight 的 78=SKIP 判定；`docs/releases/0.1.13.md` 记录身份表与 8 步发布 checklist（站点链接与 tag 同批）。
- 2026-10-25 / pi：久用与持久化自动化（报告192）：`make macos-soak` 5 分钟 1.7k 键 0 外联、词库重启不丢、RSS 稳态 20 MiB 无泄漏；顺带记录「RSS 读数随页面回收波动、重启后立刻读会偏高 10 倍」的判定陷阱。
- 2026-10-25 / pi：一键验收落地（报告191）：`make macos-auto-acceptance` 跑热键+五客户端+延迟/内存/零外联，全 PASS（p95 6.43ms、RSS 11.8MiB）；发现并修正「轮询字符串会把延迟测高 4 倍」。
- 2026-10-25 / pi：热键矩阵自动化（报告190）：`shiftc` 解决单按 Shift（原判断为探针缺陷，非产品 bug），⌥P/⌥F/⌥T/⌥M 全 PASS，Xcode 纳入客户端矩阵后五客户端全绿。
- 2026-10-25 / pi：客户端矩阵脚本化（报告189）：四个客户端的五笔/拼音兜底/标点上屏一致；Xcode 需用户首次启动后才可覆盖；一次未 guard 的投递落进用户 Ghostty（无回车未执行），教训入脚本。
- 2026-10-25 / pi：键入路径自动化落地（报告188）：`imetype` + `keytopid` 解决「进程内切源」与「TCC/会话」两个坑，五笔/拼音兜底/自动上屏/标点/全角上屏正确，键入期 28 次采样 0 外联；修饰键热键须用 `keytopid --hid`；**单按 Shift 类热键要用 `shiftc`（真正的 flagsChanged）**，报告188 的「Shift 异常」已结案为探针问题（报告190）。
- 2026-10-25 / pi：用户授权后把生产位换成 0.1.13/build21（执行 `a3faf05c…`），用户人工键入正常、词库学习写入、空闲与会话后网络抽样 0 连接（报告187）；合成键入不触发 IME，键入期仪表化仍缺。
- 2026-10-25 / pi：版本递增 0.1.13/build21（PR #155 → main `2d9c509`），acceptance run `40145382687` 出正式候选 ZIP `f86959d6…`/执行 `a3faf05c…`；签名公证/双架构零导入/30 秒启动 0 外联 PASS，未安装、未发版（报告186）。
- 2026-10-25 / pi（收尾）：隔离更新通道关闭——drill 真实网络 cancel/tamper/install×2 与用户 UI 安装/取消、注入回滚全部 PASS（报告183/184），`/drill/` 已 404、私有根已删。
- 关键决策：ADR-289 目标目录缺失时安装器显式失败、不建目录（停宿主前预检，XCTest 覆盖）。
- 验证：updater 40+7、`test-updater-isolation.py`、`make macos-offline-tests`、`make verify`、PR #154 四 CI PASS，main `167a644`。
- 生产侧全程未变：执行 SHA `c09c2d11…`、config `3bc1117c…`、宿主 PID 78677、输入源 `Lampyris.default`；旧隔离测试源与 bundle 已清理。
- 遗留：无小项；下一步是新候选包 + 最终 RC 矩阵（见 §4）。
- 2026-10-25 / pi：UI「取消」按钮已验证（窗口「已取消」，安装槽/receipt/临时目录均无变化）；`/drill/` 已 404、私有根已删、测试更新程序已退出，生产侧与输入源未变（报告184）。
- 2026-10-24 / pi：#146 head `39de72a` 四 CI PASS merge `d1e39b2`，固定 dev 同步，开放 PR 0。
- 2026-10-24 / pi：ADR-287 第二阶段落地：`IsolatedUpdate.swift` 解析三字段隔离绑定并校验根属主/权限/owner/符号链接/允许父目录，失败停用更新不回退；`build.py` 拒写隔离键。updater 38+7、生产 Info.plist 无隔离键、3 项结构回归、离线/verify PASS；未签名/未装包。
- 2026-10-24 / pi：#145 head `0b01926` 四 CI PASS merge `37323e9`，固定 dev 快进同步，开放 PR 0；main CI `40103642643` / 自动公证 `40103642650` success，未下载/安装新包。生产旧包/配置保留，隔离签名安装门禁仍 BLOCKED。
- 2026-10-24 / pi：先记 ADR-287，仅让安装/验证共用生产或 UUID 隔离目标契约；生产 UI 保持旧目标，私有域测试新包/旧包/生产哨兵与失败回滚。updater 33+7、build、离线顺序重跑、verify PASS；第一次旧 preview 测试遭用户写词库并发干扰，未改真实数据。隔离签名包/HTTPS feed 未具备，不安装。
- 2026-10-24 / pi：#144 head `861f95c` 四 CI PASS merge main `73d468b`；手动签名诊断 run `40098104120` 与自动宿主 run `40098075131` 均 success，分别核对更新程序 ZIP `962e05c5…`/执行 `0710987b…` 和同提交宿主 ZIP `3b4fb9b9…`/执行 `867add9f…`（报告180）；未安装、未测 UI/真实 feed。
- 2026-10-24 / pi：ADR-286 先定 main-only 手动签名诊断附件，工作流仅上传独立更新程序 ZIP/SHA/SOURCE-COMMIT（7 天，非 Release），本地结构测试/顺序离线/verify PASS。离线首轮因用户词库并发变化而快照断言失败，重跑 PASS；未触碰真实数据、未运行签名流程。
- 2026-10-24 / pi：#143 head `0141075` 四 CI 绿 merge `612020d`，dev 快进同步；公证 run `40096030727` 下载 ZIP `2a2e2497…`/执行 `ea8b3a39…`，两架构无网络导入、控制器类保留（报告179）。未安装、仍 build20/无更新程序，动态验收待。
- 2026-10-24 / pi：链接对照定位宿主网络导入来自 Rust staticlib 未引用代码；ADR-285 先记，`build.sh` 加 `-dead_strip` 和逐架构 nm 门禁，本地 strict universal 两片无 socket/connect 且保留 ObjC 控制器类；离线回归/verify PASS，未安装/未签名新包。
- 2026-10-24 / pi：从 main `56c2457` 的成功公证 run `40092840370` 下载并静态核验候选（报告178；ZIP `c5db6eb3…`/执行 `6f650629…`）；同 build20、只含宿主不含更新程序，未安装。新旧宿主均导入网络符号，旧 PID 单次 lsof 无连接，动态门禁仍开；词库持续变化，未碰真实数据。
- 2026-10-24 / pi：PR #142 head `98c93d0` 四 CI PASS，merge `56c2457`，dev 快进推送，开放 PR 0；本机仍旧 v0.1.12/build20，词库重采 319 行（用户活动，不改/不还原）。工程项完成、原生/动态零外联待新候选。
