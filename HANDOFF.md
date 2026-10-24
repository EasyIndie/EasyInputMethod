# HANDOFF — 当前状态

## 0. 元信息

- 更新：2026-10-24 / pi；固定 `dev` 本地 `58eefa8`（更新可靠性/隐私门禁说明），本地 `origin/main` / `origin/dev` 均为 `d3e941a`（#141）；本轮 HANDOFF 同批提交，尚未推送/合并/发版。真实远端状态再次执行前须 fetch 核对。
- 正式渠道仅网站/DMG（ADR-284）；最近发布记录 v0.1.12/build20（报告174）。本轮只改源码、测试、文档；**未安装/切源/发键/写真实用户数据**。
- 审计修复：Swift 下载结果持有私有 ZIP 并在释放时清理；安装器前置失败清 staging、首次安装后置失败撤销新包、已有包回滚失败保留备份且显式报错；静态隐私门禁不再冒称动态验证。完整 `make verify`、顺序执行的 `make macos-offline-tests`、`make macos-updater-tests`（28+7 项）、`make macos-updater-build` 均 PASS。

## 1. 设备与数据（2026-10-24 19:45 只读采集）

| 设备 | 已装包与执行 SHA | 数据/输入源 | 恢复点 |
|---|---|---|---|
| 本机 B，arm64/macOS 27.0.1 | 生产 v0.1.12/build20，Developer ID / Gatekeeper accepted；执行 SHA `c09c2d11749dea9a4347930972817e5262e682c971653f0618c420e7ad9e77a3` | config SHA `3bc1117cc337…`（显式 8 个 hotkey；mode=mixed）；词库 313 行 / `c8004f17175b…`；宿主 PID 78677（采集瞬间）；脚本未解析出输入源，**未知**，禁止推断为 ABC | 本轮无安装/切源；已装包维持原样 |
| Intel `pro`（历史记录，未远程重采） | 报告174称已升级 v0.1.12/build20，**本轮不把历史证据视为当前 SHA** | config/词库与源当前值未知 | 执行前独立重采 |

- 本轮无待装 ZIP、无新签名包；ZIP SHA **不存在**，不得用已装执行 SHA 冒充 ZIP SHA。最终包仅从合并后的 main 明确提交构建。

## 2. 最近完成

| 范围 | 结果/证据 |
|---|---|
| 既有发布 | 报告174：v0.1.12/build20 DMG 含图形安装/卸载；Pages 仅网站/DMG 路径；不以发布关闭最终 RC 门禁 |
| 本轮审计 | 更新可靠性回归旧版失败、新版 28+7 项 PASS；`make verify`、顺序执行 `make macos-offline-tests` 与 `make macos-updater-build` PASS。并行跑 verify/offline 曾有一次离线缺依赖缓存失败，顺序重跑 PASS（不作为代码通过的证据）；磁盘满时只清理可再生的 `target/debug/incremental`。未实机换包。 |

## 3. 未决

- 本批代码/测试/文档已在固定 dev 提交 `58eefa8`；HANDOFF 同批提交，未推送/未入 main，未装包。下一步唯一 dev→main PR 四 CI 跟进，不能以本地绿灯宣称用户已获修复。
- App Store 搜索框首次输入偶发卡顿（报告177）：A/B、sample 与精确时间待取证，暂不归因。
- 最终 RC 同包：真实三模式与目标客户端/辅助功能/多屏/睡眠/A-B、p95<16ms、稳态≤30MiB、升级异常与卸载、独立第三方重建/零外联及五工作日试用；历史包 PASS 不继承。
- `make verify-no-network` 只做静态扫描，不抓包；签名最终包宿主动态外联核验仍 BLOCKED（未执行）。

## 4. 下一步

1. `git status --short --branch` 确认本批差异、`git diff --check`；代码/文档再动则重新运行对应门禁（本轮顺序执行的 updater/offline/verify/updater-build 已 PASS）。
2. 推送固定 dev 并开唯一 dev→main PR；跟进当前 head 四项 CI、权限与冲突直到 merge commit 合入并快进同步 dev。遇权限阻断应记录真实远端状态，不虚报完成。
3. 仅在合并 main 后安排新签名候选；先完成更新 UI 取消/失败/成功与升级回滚的受影响路径，再锁最终 RC 执行完整矩阵。`ROADMAP.md` 未勾项继续开放。

## 5. 边界

- 核心零网络/遥测；配置只经 ime-config；不能修改真实 config/词库、UserDefaults 或 HIToolbox，不清用户数据。未经授权不换正式包、切源、发键、重启或创建 tag/Release。
- 如需实机换包/验收，先读 `.agents/skills/iterate-macos-ime/SKILL.md`，记录 main 提交、ZIP SHA 和执行 SHA；当前轮仅离线测试。

## 9. 会话日志（最近）

- 2026-10-24 / pi：审计后修 Swift 下载清理、首次安装回滚与预检清理；回归先红后绿（28+7 项）；verify、顺序离线回归、updater-build PASS。并行离线测试一次因 Cargo 缓存瞬时失败，顺序重跑通过；磁盘满只删可再生编译缓存。未换包/切源。
- 2026-10-24 / pi：v0.1.12/build20 DMG 安装/卸载发布与两机升级见报告174；正式渠道仅网站/DMG（ADR-284）。
- 2026-10-24 / pi：App Store 搜索卡顿调研见报告177，尚无归因。
