# HANDOFF — 当前状态

## 0. 元信息

- 更新：2026-10-25 07:50 / pi（会话收尾）。阶段：更新通道原生验收关闭，进入最终 RC 门禁前夜。
- 分支：`dev` @ `1584b47`（= main `167a644` + 文档归档，无代码差异）；最近 `make verify` PASS（07:44，含 lint/test/deny/产物级网络断言）。
- 隔离更新六条路径（取消/篡改/安装/备份/回滚/UI 取消）均有真实网络证据（报告183/184）；`/drill/` 已 404、私有根已删、生产侧未变。
- 正式渠道仅网站/DMG（ADR-284）；最近发布记录 v0.1.12/build20（报告174）。本轮只改源码、测试、文档；**未安装/切源/发键/写真实用户数据**。
- #142 更新可靠性修复入 main；ADR-285 在 #143 入 main 后，签名公证 run `40096030727` 的两架构最终宿主网络导入均无命中且 IMK 控制器类保留；源码重建通过。**这仅为签名静态 PASS**，新包未运行，动态外联/更新程序/最终 RC 均未验。

## 1. 设备与数据（2026-10-25 07:45 只读重采；数据可能继续变化）

| 设备 | 已装包与执行 SHA | 数据/输入源 | 恢复点 |
|---|---|---|---|
| 本机 B，arm64/macOS 27.0.1 | 生产 v0.1.12/build20，Developer ID / Gatekeeper accepted；执行 SHA `c09c2d11749dea9a4347930972817e5262e682c971653f0618c420e7ad9e77a3` | config SHA `3bc1117cc337…`（显式 8 个 hotkey；mode=mixed）；词库 516 行 / `902e3a92d0d2…`（07:45 采集瞬间，用户持续输入，禁止还原或假设恒定；本轮未操作）；宿主 PID 78677（采集瞬间）；脚本未解析出输入源，**未知**，禁止推断为 ABC | 本轮无安装/切源；已装包维持原样 |
| Intel `pro`（历史记录，未远程重采） | 报告174称已升级 v0.1.12/build20，**本轮不把历史证据视为当前 SHA** | config/词库与源当前值未知 | 执行前独立重采 |

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

## 3. 未决

- 报告180 的签名宿主/更新程序绑定旧 main `73d468b`、build20，已被 drill 体系取代；drill 产物只用于隔离验收，不能冒充正式发布包。
- **本会话为 SSH `Background` 会话**：GUI 程序无窗口服务器连接（`!cgsConnection`）、AX 窗口为 0、`screencapture` 被拒；凡需点击的 UI 验收都必须由用户在图形会话执行（本会话两次均已请用户代点）。
- ADR-289 已定：目标目录缺失时安装器显式失败、不自建（生产该目录恒存在）。
- App Store 搜索框首次输入偶发卡顿（报告177）：A/B、sample 与精确时间待取证，暂不归因。
- 最终 RC 同包：真实三模式与目标客户端/辅助功能/多屏/睡眠/A-B、p95<16ms、稳态≤30MiB、升级异常与卸载、独立第三方重建/零外联及五工作日试用；历史包 PASS 不继承。
- ADR-285 的最终宿主静态导入门禁已由 main `612020d` 新公证包两架构核实；`make verify-no-network` 自身仍不扫描签名 `.app`，`build.sh` 单独检查。旧宿主单时点 lsof 为空不关闭新候选的动态零外联门禁。

## 4. 下一步

1. 文档归档（报告183/184、ROADMAP、HANDOFF）在固定 dev，不为纯归档单开 PR，随下一批改动一起走 `dev → main`。
2. 下一批建议按 `ROADMAP.md` 顺序推进最终 RC 门禁，先做**新候选包**（新构建号、双架构签名公证）：`make macos-release` → 记录 ZIP/执行/SOURCE 三 SHA → 再谈安装与动态验收。
3. 可选先做不依赖新包的一项：报告177 的 App Store 搜索框首次输入卡顿 A/B + sample 取证（只读，不动用户数据）。
4. 大项未动：三模式真实客户端矩阵、辅助功能/多屏/睡眠、p95<16ms、稳态 ≤30MiB、宿主动态零外联、独立第三方重建、五工作日试用；历史包 PASS 不继承。

## 5. 边界

- 核心零网络/遥测；配置只经 ime-config；不能修改真实 config/词库、UserDefaults 或 HIToolbox，不清用户数据。未经授权不换正式包、切源、发键、重启或创建 tag/Release。
- 用户授权按隔离方案推进，但**还没有可以安全安装的隔离更新器**。如需实机换包/验收，先读 `.agents/skills/iterate-macos-ime/SKILL.md`，记录 main 提交、ZIP SHA、执行 SHA，验证新包只会写私有根；本轮仅离线测试。

## 9. 会话日志（最近）

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
