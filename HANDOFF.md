# HANDOFF — 当前状态

## 0. 元信息

- 更新：2026-10-27 17:40 / pi（**air 本机**）。阶段：**PR #201 已合并，候选包已在 air 装包复验，验收发现 1 个真 BUG**——ADR-294/295/296 的合批候选（main `e10e6ed6`）7 项里 2/3/5 PASS、1/7 PARTIAL（只差图形会话点击/注销）、4 BLOCKED（无 publish 作业）、**6 FAIL：`--uninstall --purge-data` 不清配置与词库**。详见 `docs/reviews/213-updater-ships-with-package.md`。
- 分支：`dev` = `main` = `e10e6ed6`（PR #201 用 merge commit 合入，dev 已快进）；开放 PR **0 个**。最近 `make verify` **PASS**。
- 已装包（air）：**0.1.14 / build 23，执行 `add68cc6…`** = 本轮候选（含 ADR-294/295/296）；**输入源已被卸载器停用，需手动加回**。pro 仍是旧包 `a165f05c…`。
- 换设备：仍是 **air 为主**（§4.1）；pro 上的 CLT SDK 损坏是**那台机器本地问题**，air 离线回归 54/54 全 PASS。

## 1. 设备与数据

| 设备 | 已装包与执行 SHA | 数据 / 输入源 | 恢复点 |
|---|---|---|---|
| **air**（arm64 / macOS 27.0.1 / Xcode 27，用户 `joker`；pi 跑在 Background 会话，驱动不了 GUI 点击） | 0.1.14/build 23，执行 **`add68cc6…`**（= 候选，Notarized）；更新程序执行 `02bc110f…`。**输入源当前未注册**（卸载器停用后重装未自动加回） | config `3bc1117c…`（8 个显式 `hotkey.*`）、词库 **706 行** `2dcea8f1…`；输入源仅 ABC + 搜狗 | `uninstalled/bundle.*` 11 份（0.1.13 等）、`/tmp/lampyris-verify-backup2/`（config+706 行词库）；旧包整包 `/tmp/rollback-a165f05c.zip` 已随重启的 /tmp 清理，回滚靠候选 ZIP `58bf1549…` |
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

- **P1 缺陷（必须先修）**：`--uninstall --purge-data` 只删 `…/Lampyris/updates`，`config.toml`/`user-dictionary.tsv`/`uninstalled/` 全留，却打印「已彻底清理」。根因：更新程序把 `InstallLocation.support`（= `…/Lampyris/updates`）传给 `UninstallPaths.support`，而 `UninstallerCore` 把它当数据根（DMG 卸载器传的是 `…/Lampyris`）。修法见报告 213 §5-P1。
- **第 1/5/7 项差一次图形会话动作**：菜单「检查更新…」端到端点击、更新窗口「卸载萤火虫…」按钮、卸载后注销回读。pi 在 Background 会话，`AXPress`/`CGEvent` 到不了 Aqua（`cgwins` 也读不到窗口）。
- **第 4 项 BLOCKED**：无高于 0.1.14 的已签名发布 + 生产私钥不在本机 + ADR-288 说的 drill publish 作业在当前工作流里**不存在**（只有 `build`）。
- **pro 工具链损坏是 pro 本地问题**：air 上 `make macos-offline-tests` **54/54 文件 297 例 PASS**，`test-controller-menu`/`test-sandbox-config` 均过；pro 的 2 项 FAIL 仍待重装 CLT（未授权）。
- **未定位异常**：09:27 回读生产包执行 SHA 变成旧包 `a165f05c…`（09:12/09:28 两次安装后都是 `add68cc6…`）。期间本会话未执行安装，可能与他人操作有关；证据见报告 213 §5-P5，注意复现。
- ADR-296 自删除**已真机验证 PASS**（更新程序退出后本体被 detached `/bin/sh` 删除）。
- 旧账（与本批无关，仍开放）：`install.sh` 的「已自动注册到输入源」在 macOS 13 是假成功（报告201）；air 上开 VoiceOver 时装机版输入上下文掉回 ABC（报告210）；合成按键切不动多 Space（报告205）；IT-15 第三方重建、IT-23 五工作日试用。

## 4. 下一步（按顺序）

1. **修 P1**（`--purge-data` 数据根错位）：更新程序改传真实数据根，并在 `test-dmg-updater.py` 固化「purge 后数据根不存在」断言 → `make verify` → 出新候选 → 复验第 6 项。
2. **用户在图形会话补 3 个动作**：手动把「萤火虫」加回输入源 → 菜单「检查更新…」（预期直接开窗口）→ 更新窗口「卸载萤火虫…」→ 注销回读（第 7 项）。
3. P2/P3 取舍：更新程序定位是否优先 `~/Applications` 精确路径；`uninstalled/` 算不算「更新备份」。
4. 第 4 项要闭环需先补 ADR-288 的 drill publish 作业并单独授权一次 Pages 部署。
5. 发布门禁不变：IT-15 第三方重建、IT-23 五工作日试用先做，再谈 tag/Release。

## 4.1 换到 air 后怎么开工

| 项 | 值 |
|---|---|
| 系统 / 架构 | macOS 27.0.1 / arm64，用户 `joker`，SSH 别名 `air` |
| 仓库 | `~/Documents/EasyInputMethod`（先 `git switch dev && git pull --ff-only`） |
| 已装包 | 0.1.14/build 23，执行 `add68cc6…`（= 报告 213 候选，含 ADR-294/295/296）；更新程序 `02bc110f…` |
| 卸载备份 | `uninstalled/bundle.VQzkTh`（0.1.13）+ 10 份历史包；重装用候选 ZIP `58bf1549…` |
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

- 2026-10-27 / pi（air）：**PR #201 合并（`e10e6ed6`）→ 候选 ZIP `58bf1549…`/宿主 `add68cc6…`/更新程序 `02bc110f…` 已装 air 并复验 7 项**（报告 213）。PASS：旧名迁移、CLI 覆盖不再报「已有不同版本」、`--uninstall` 保留数据 + 更新程序自删、隔离构建拒绝卸载。**FAIL：`--purge-data` 不清配置/词库**（support 字段语义错位）。PARTIAL：菜单点击/注销回读缺图形会话。BLOCKED：真实升级（无 publish 作业）。air 离线回归 54/54 PASS → 修正「pro CLT 损坏是共性问题」的旧结论。
- 2026-10-27 / pi（换设备 pro → air）：交接文档重写为当前状态。**下一步从 air 开始**：合并 PR #201 → 出签名候选包 → 装到 air 复验 §4 步骤 2 的 7 项（含 ADR-296 自删除）。
- 2026-10-27 / pi：ADR-296 落地并推 `dev`（`84caf48`），PR #201 四项 PASS。卸载入口进更新程序（窗口按钮 + `--uninstall`），实现收敛进 `InstallCore.UninstallerCore`，自删除用 detached `/bin/sh`（无依赖），隔离构建拒绝卸载生产；顺手修掉窗口直接读 `homeDirectoryForCurrentUser` 破坏隔离回归的问题。`make verify` PASS。
- 2026-10-27 / pi：**pro 工具链异常**（非代码）：CLT SDK `CVBuffer.h` 损坏（4749 NUL 字节）→ 本地离线回归 2 项环境性 FAIL，其余 52 项 PASS；`make verify` 不受影响。修复需重装 CLT，未执行。
- 2026-10-27 / pi：**PR #200 已合并**（`e0a27ca`）：ADR-294 + ADR-295 一批。CI 全绿；main 验收 run `40437912815` 出候选 ZIP `452ce9ba…`（含签名公证的 `LampyrisUpdateCheck.app`，执行 `dbf9a8ea…`）。未安装。
- 2026-10-26 / pi：ADR-295（用户拍板不上 App Store）——DMG 与 ZIP 都带更新程序、更新器自更新 + 重开按钮、`ci-sign.sh --also` 单次公证、安装实现收敛 `InstallCore`；CLI `install.sh` 保留独立实现但语义一致。
- 2026-10-26 / pi：ADR-294——用户报「点检查更新只跳网页」：改为按 bundle id 定位，正式名固定 `LampyrisUpdateCheck.app`，卸载器兼容旧名，取消手工改名。
