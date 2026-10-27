# HANDOFF — 当前状态

## 0. 元信息

- 更新：2026-10-27 19:00 / pi（**air 本机**）。阶段：**本轮更新链路验收收口**——报告 213 的 7 项：**6 PASS + 1 BLOCKED**（第 4 项「真实升级」：无 publish 作业、无私钥、两份候选同为 build 23）。P1/P2 已修并出候选 `6d89821`（PR #202），用户已在本机完成菜单点击、窗口卸载、注销回读：无任何残留。**air 当前没有安装萤火虫**（按验收流程卸掉了），数据（config `3bc1117c…`、词库 713 行 `8dbd41f4…`）完整保留。
- 分支：`dev` = `main` = `6d89821`（PR #201/#202 均 merge commit 合入）；开放 PR **0 个**。最近 `make verify` + 离线 54/54（297 例）+ updater/installcore **PASS**。
- 已装包（air）：**无**（验收结束时按流程卸载，残留检查全清）。重装用候选 ZIP `90ed224d…`（run `40486038131` @ `6d89821`，宿主 `0669f249…`/更新程序 `fbbbc11b…`）。pro 仍是旧包 `a165f05c…`。
- 换设备：仍是 **air 为主**（§4.1）；pro 上的 CLT SDK 损坏是**那台机器本地问题**，air 离线回归 54/54 全 PASS。

## 1. 设备与数据

| 设备 | 已装包与执行 SHA | 数据 / 输入源 | 恢复点 |
|---|---|---|---|
| **air**（arm64 / macOS 27.0.1 / Xcode 27，用户 `joker`；pi 跑在 Background 会话，驱动不了 GUI 点击） | **未安装**（2026-10-27 验收后按流程卸载，TIS/菜单/进程/缓存均无残留）；最后验证过的包 = ZIP `90ed224d…` / 宿主 `0669f249…` / 更新程序 `fbbbc11b…` | config `3bc1117c…`（8 个显式 `hotkey.*`）、词库 **713 行** `8dbd41f4…`（保留数据卸载后完好）；输入源仅 ABC + 搜狗 | 重装：候选 ZIP `90ed224d…` 的 `scripts/install.sh`；注意 `/tmp` 备份已随重启清理，用户数据本身在原位 |
| **pro**（Intel / macOS 13.7.8，用户 `bot`） | 0.1.14/build 23，执行 `a165f05c…`（Notarized） | config `6f699c4b…`（**有 9 个显式 `hotkey.*` 项**）、词库 575 行、输入源 `Lampyris.default`、宿主 PID 26989 | `uninstalled/bundle.160547` 等若干旧包 |

- 未安装任何新候选包；两台机器的 config / 词库 / 输入源本轮均未改动。

## 2. 本轮完成

| 范围 | 结果 |
|---|---|
| ADR-294（按 bundle id 定位更新程序） | PR #200 已合并（main `e0a27ca`）。宿主菜单与卸载器只按 `cn.jokerhub.Lampyris.WebsiteUpdateCheck` 查找，正式名固定 `LampyrisUpdateCheck.app`，取消手工改名。 |
| ADR-295（装包即带更新程序） | 同 PR。DMG 与 ZIP 都内含更新程序并装到 `~/Applications`；更新器自更新 + 「重新打开更新程序」；`ci-sign.sh --also` 同一次公证两个 app；安装实现收敛为 `platforms/macos/InstallCore`。 |
| 候选包（main `e0a27ca`，run `40437912815`） | `Lampyris-0.1.14-universal.zip` = `452ce9ba…`（6,952,843 B，build 23）；内含 `LampyrisUpdateCheck.app`（执行 `dbf9a8ea…`，universal，`stapler validate` PASS，`spctl` = Notarized Developer ID），宿主执行 `b52de5e3…`。**未安装**。 |
| ADR-296（自卸载） | `dev` `84caf48`，PR #201 四项检查 PASS（macos 8m40s）。更新窗口「卸载萤火虫…」+ CLI `--uninstall [--purge-data]`；卸载逻辑并入 `InstallCore.UninstallerCore`，DMG 卸载器改为调它；自删除用 detached `/bin/sh`（无额外依赖）；隔离构建拒绝卸载生产。 |
| 同轮修复 | 窗口/CLI 改用 `InstallLocation.home`，不再读 `homeDirectoryForCurrentUser`（否则「隔离构建不得回退真实目录」回归会挂）。 |

## 3. 未决

- **P1/P2 已修并复验**（PR #202，main `6d89821`）：`--purge-data` 现在清掉整个数据根；`updaterURL()` 改为安装目录优先。复验证据见报告 213 §7。
- **P3 待澄清**：`--uninstall`（保留数据）仍留下 `uninstalled/`，与 DMG 文案「移除更新备份」不完全一致。
- **第 1/5/7 项差一次图形会话动作**：先手动把「萤火虫」加回输入源 → 菜单「检查更新…」端到端点击 → 更新窗口「卸载萤火虫…」→ 注销回读。pi 在 Background 会话，`AXPress`/`CGEvent` 到不了 Aqua（`cgwins` 也读不到窗口）。
- **两个候选都是 build 23**：`macos-acceptance` 不自动递增构建号，按构建号比较的「更新程序版本同步」无法在两份候选间演示；第 4 项闭环时应换更高构建号。
- **第 4 项 BLOCKED**：无高于 0.1.14 的已签名发布 + 生产私钥不在本机 + ADR-288 说的 drill publish 作业在当前工作流里**不存在**（只有 `build`）。
- **pro 工具链损坏是 pro 本地问题**：air 上 `make macos-offline-tests` **54/54 文件 297 例 PASS**，`test-controller-menu`/`test-sandbox-config` 均过；pro 的 2 项 FAIL 仍待重装 CLT（未授权）。
- **未定位异常**：09:27 回读生产包执行 SHA 变成旧包 `a165f05c…`（09:12/09:28 两次安装后都是 `add68cc6…`）。期间本会话未执行安装，可能与他人操作有关；证据见报告 213 §5-P5，注意复现。
- ADR-296 自删除**已真机验证 PASS**（更新程序退出后本体被 detached `/bin/sh` 删除）。
- 旧账（与本批无关，仍开放）：`install.sh` 的「已自动注册到输入源」在 macOS 13 是假成功（报告201）；air 上开 VoiceOver 时装机版输入上下文掉回 ABC（报告210）；合成按键切不动多 Space（报告205）；IT-15 第三方重建、IT-23 五工作日试用。

## 4. 下一步（按顺序）

1. **重装（可选，按需）**：air 上现在没有萤火虫；要恢复日常使用就解压候选 ZIP `90ed224d…` 跑 `scripts/install.sh --app …/Lampyris.app`，再到系统设置加回输入源。
2. **P3 取舍**：`--uninstall`（保留数据）仍留 `uninstalled/`，要不要算「更新备份」一并清掉。
3. **第 4 项闭环**：先补 ADR-288 的 drill publish 作业（并单独授权一次 Pages 部署），用**高于 23 的构建号**验「升级后更新程序版本同步 + 重新打开更新程序」。
4. 发布门禁不变：IT-15 第三方重建、IT-23 五工作日试用先做，再谈 tag/Release。

## 4.1 换到 air 后怎么开工

| 项 | 值 |
|---|---|
| 系统 / 架构 | macOS 27.0.1 / arm64，用户 `joker`，SSH 别名 `air` |
| 仓库 | `~/Documents/EasyInputMethod`（先 `git switch dev && git pull --ff-only`） |
| 已装包 | **无**（2026-10-27 验收后卸载） |
| 重装来源 | 候选 ZIP `90ed224d…`（run `40486038131` @ `6d89821`，宿主 `0669f249…`/更新程序 `fbbbc11b…`） |
| ⚠️ 输入源 | 卸载器已停用 `Lampyris*`，重装后系统未自动注册 —— **需手动在系统设置加回「萤火虫」** |

```sh
cd ~/Documents/EasyInputMethod && git fetch origin --prune && git switch dev && git pull --ff-only
git log --oneline -1                       # 记下这个提交，写进验收记录
./scripts/handoff-status.sh --for=device   # 重采：已装包执行 SHA / config / 输入源 / 词库行数
make verify                                # cargo 门禁
make macos-offline-tests                   # air 上 54/54 全 PASS（pro 的 2 项 FAIL 是那台机器本地 SDK 损坏）
make macos-probe-build                     # 探针（arm64，约 1 分钟）
./tools/macos-probe/acceptance-preflight.sh # ready=true 才能跑键入类验收
```

**air 已知平台差异（别当 bug）**

- `q ` = 「多」（五笔一级简码），首个按键常被窗口激活吞掉 → 探针串看起来像「多你好。」。
- Safari 的输入区要读 AX（macOS 27 标题不随输入更新）；TextEdit 焦点属性读不到时回退窗口文本区。
- 开 VoiceOver 时装机版输入上下文会掉回 ABC（菜单「正在加载…」），人耳验证改用同一份候选窗代码的调试窗口。
- 内存口径用**私有已提交**（ADR-292），`footprint` 只作参考。
- 键入类验收必须在**本机图形会话**，不能 SSH。

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

- 2026-10-27 / pi（air）：**报告 213 收口**——用户完成图形会话三项：菜单「检查更新…」直接开 `0.1.14/23` 窗口、窗口「卸载萤火虫…」保留数据卸载、注销重登录。注销后回读：TIS 无 `Lampyris*`、输入法菜单无「萤火虫」、app/更新程序/prefs/caches/logs/进程全无残留，数据 `3bc1117c…` + 713 行 `8dbd41f4…` 完好。7 项 = 6 PASS + 第 4 项 BLOCKED。air 现处于未安装状态。
- 2026-10-27 / pi（air）：**修 P1+P2 并出候选 `6d89821`**（PR #202，四项 CI PASS → merge commit）：`--purge-data` 改传真实数据根（`InstallLocation.dataRoot` + `uninstallPaths()`），菜单改为安装目录优先、LaunchServices 兜底；补 `InstallLocationTests` 与 `input-menu` 断言；`test-preview-menu.py` 把「并发键入导致词库追加」改为 SKIP。实机复验：purge 后数据根整个消失，还原后逐字节一致；`LS_resolved=~/Applications` build 23。离线 54/54（297 例）+ updater/installcore 全 PASS。
- 2026-10-27 / pi（air）：**PR #201 合并（`e10e6ed6`）→ 候选 ZIP `58bf1549…`/宿主 `add68cc6…`/更新程序 `02bc110f…` 已装 air 并复验 7 项**（报告 213）。PASS：旧名迁移、CLI 覆盖不再报「已有不同版本」、`--uninstall` 保留数据 + 更新程序自删、隔离构建拒绝卸载。**FAIL：`--purge-data` 不清配置/词库**（support 字段语义错位）。PARTIAL：菜单点击/注销回读缺图形会话。BLOCKED：真实升级（无 publish 作业）。air 离线回归 54/54 PASS → 修正「pro CLT 损坏是共性问题」的旧结论。
- 2026-10-27 / pi（换设备 pro → air）：交接文档重写为当前状态。**下一步从 air 开始**：合并 PR #201 → 出签名候选包 → 装到 air 复验 §4 步骤 2 的 7 项（含 ADR-296 自删除）。
- 2026-10-27 / pi：ADR-296 落地并推 `dev`（`84caf48`），PR #201 四项 PASS。卸载入口进更新程序（窗口按钮 + `--uninstall`），实现收敛进 `InstallCore.UninstallerCore`，自删除用 detached `/bin/sh`（无依赖），隔离构建拒绝卸载生产；顺手修掉窗口直接读 `homeDirectoryForCurrentUser` 破坏隔离回归的问题。`make verify` PASS。
- 2026-10-27 / pi：**pro 工具链异常**（非代码）：CLT SDK `CVBuffer.h` 损坏（4749 NUL 字节）→ 本地离线回归 2 项环境性 FAIL，其余 52 项 PASS；`make verify` 不受影响。修复需重装 CLT，未执行。
- 2026-10-27 / pi：**PR #200 已合并**（`e0a27ca`）：ADR-294 + ADR-295 一批。CI 全绿；main 验收 run `40437912815` 出候选 ZIP `452ce9ba…`（含签名公证的 `LampyrisUpdateCheck.app`，执行 `dbf9a8ea…`）。未安装。
- 2026-10-26 / pi：ADR-295（用户拍板不上 App Store）——DMG 与 ZIP 都带更新程序、更新器自更新 + 重开按钮、`ci-sign.sh --also` 单次公证、安装实现收敛 `InstallCore`；CLI `install.sh` 保留独立实现但语义一致。
- 2026-10-26 / pi：ADR-294——用户报「点检查更新只跳网页」：改为按 bundle id 定位，正式名固定 `LampyrisUpdateCheck.app`，卸载器兼容旧名，取消手工改名。
