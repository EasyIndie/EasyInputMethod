# HANDOFF — 当前状态

## 0. 元信息

- 更新：2026-10-27 12:05 / pi（pro 本机）。阶段：**更新链路三件事已做完，卡在「装包复验」**——ADR-294/295（装包即带更新程序 + 按 bundle id 定位 + 更新器自更新 + 安装实现收敛）已合并 main（PR #200，`e0a27ca`）；ADR-296（已安装版本自带卸载）已推 `dev`（`84caf48`）并开 **PR #201，四项检查全绿，等用户决定合并**。
- 分支：`dev` @ 本轮交接提交；`main` = `e0a27ca`；开放 PR **1 个（#201）**。最近 `make verify` **PASS**。
- 已装包（pro 与 air 都是）：**0.1.14 / build 23，执行 `a165f05c…`** —— 旧代码，不含本批改动。
- 换设备：本次是 **pro → air**（场景 D），§4.1 是 air 的开工与验收指引。

## 1. 设备与数据

| 设备 | 已装包与执行 SHA | 数据 / 输入源 | 恢复点 |
|---|---|---|---|
| **air**（arm64 / macOS 27.0.1 / Xcode 27，`ssh air`，用户 `joker`） | 0.1.14/build 23，执行 `a165f05c…`（Notarized）。**数据为 2026-10-26 采集，换设备后先重采** | 上次记录：config `809e2cae…`、词库 646 行、输入源 `Lampyris.default`（另有搜狗源启用） | `uninstalled/bundle.VQzkTh`（0.1.13，执行 `c3b533e4…`） |
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

- **PR #201 待合并**（用户决定）；合并后才会有含 ADR-296 的签名候选包。
- **候选包实机复验未做**（见 §4 步骤 2 的 7 项），需用户授权装包。
- **pro 本机工具链损坏（非代码问题）**：CLT SDK 的 `CoreVideo.framework/Headers/CVBuffer.h` 有 4749 个 NUL 字节，任何走 AppKit/Cocoa 的本地编译都失败 → `make macos-offline-tests` 有 2 项环境性 FAIL（`test-controller-menu`、`test-sandbox-config`），其余 52 项 PASS；`make verify` 不受影响。修复要 `sudo rm -rf /Library/Developer/CommandLineTools && xcode-select --install`（未执行）。**air 上先跑一次离线回归确认是否同样存在**。
- ADR-296 的自删除**只在离线探针里验证过语义**，真实「退出后删掉自己」必须在装机版上验一次。
- 旧账（与本批无关，仍开放）：`install.sh` 的「已自动注册到输入源」在 macOS 13 是假成功（报告201）；air 上开 VoiceOver 时装机版输入上下文掉回 ABC（报告210）；合成按键切不动多 Space（报告205）；IT-15 第三方重建、IT-23 五工作日试用。

## 4. 下一步（按顺序）

1. **合并 PR #201**（`dev → main`，merge commit）→ 触发 `macos-acceptance` 出签名候选包；记录 ZIP、宿主执行 SHA、更新程序执行 SHA、`SOURCE-COMMIT`。
2. **在 air 装候选包并复验 7 项**（证据按 ADR-293 绑定执行 SHA）：
   - DMG 装完 → 菜单「检查更新…」**直接开更新窗口**，不跳网页
   - ZIP 装完 → `~/Applications/LampyrisUpdateCheck.app` 存在；旧名 `Lampyris Update.app` 被迁走并留备份
   - CLI 覆盖升级不再报「已有不同版本」
   - 真实升级一次 → 更新程序版本同步 + 「重新打开更新程序」生效
   - 更新窗口「卸载萤火虫…」→ 保留数据卸载成功，**更新程序本体在退出后被删除**
   - `LampyrisUpdateCheck --uninstall --purge-data` 彻底清理（隔离 drill 构建必须拒绝，单独取一次证）
   - 卸载后注销重登录，输入法菜单无残留项
3. 写 `docs/reviews/213-updater-ships-with-package.md`（或顺延编号），更新 HANDOFF/ROADMAP。
4. 发布门禁不变：IT-15 第三方重建、IT-23 五工作日试用先做，再谈 tag/Release。

## 4.1 换到 air 后怎么开工

| 项 | 值 |
|---|---|
| 系统 / 架构 | macOS 27.0.1 / arm64，用户 `joker`，SSH 别名 `air` |
| 仓库 | `~/Documents/EasyInputMethod`（先 `git switch dev && git pull --ff-only`） |
| 已装包 | 0.1.14/build 23，执行 `a165f05c…`（不含本批改动） |
| 卸载备份 | `uninstalled/bundle.VQzkTh`（0.1.13） |

```sh
cd ~/Documents/EasyInputMethod && git fetch origin --prune && git switch dev && git pull --ff-only
git log --oneline -1                       # 记下这个提交，写进验收记录
./scripts/handoff-status.sh --for=device   # 重采：已装包执行 SHA / config / 输入源 / 词库行数
make verify                                # cargo 门禁
make macos-offline-tests                   # 确认 air 的 SDK 是否也损坏（pro 上有 2 项环境性 FAIL）
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

- 2026-10-27 / pi（换设备 pro → air）：交接文档重写为当前状态。**下一步从 air 开始**：合并 PR #201 → 出签名候选包 → 装到 air 复验 §4 步骤 2 的 7 项（含 ADR-296 自删除）。
- 2026-10-27 / pi：ADR-296 落地并推 `dev`（`84caf48`），PR #201 四项 PASS。卸载入口进更新程序（窗口按钮 + `--uninstall`），实现收敛进 `InstallCore.UninstallerCore`，自删除用 detached `/bin/sh`（无依赖），隔离构建拒绝卸载生产；顺手修掉窗口直接读 `homeDirectoryForCurrentUser` 破坏隔离回归的问题。`make verify` PASS。
- 2026-10-27 / pi：**pro 工具链异常**（非代码）：CLT SDK `CVBuffer.h` 损坏（4749 NUL 字节）→ 本地离线回归 2 项环境性 FAIL，其余 52 项 PASS；`make verify` 不受影响。修复需重装 CLT，未执行。
- 2026-10-27 / pi：**PR #200 已合并**（`e0a27ca`）：ADR-294 + ADR-295 一批。CI 全绿；main 验收 run `40437912815` 出候选 ZIP `452ce9ba…`（含签名公证的 `LampyrisUpdateCheck.app`，执行 `dbf9a8ea…`）。未安装。
- 2026-10-26 / pi：ADR-295（用户拍板不上 App Store）——DMG 与 ZIP 都带更新程序、更新器自更新 + 重开按钮、`ci-sign.sh --also` 单次公证、安装实现收敛 `InstallCore`；CLI `install.sh` 保留独立实现但语义一致。
- 2026-10-26 / pi：ADR-294——用户报「点检查更新只跳网页」：改为按 bundle id 定位，正式名固定 `LampyrisUpdateCheck.app`，卸载器兼容旧名，取消手工改名。
