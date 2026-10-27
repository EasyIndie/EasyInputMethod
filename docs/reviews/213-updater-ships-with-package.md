# 213 更新程序随包分发 + 自卸载：候选包实机复验（0.1.14 / build 23 / 执行 `add68cc6…`）

设备：air（`joker`，arm64 / macOS 27.0.1）。候选来自 main merge commit `e10e6ed68f1417c9998a0b43129b14affd85b97a`，验收 run `40472068259`：

| 产物 | SHA-256 |
|---|---|
| `Lampyris-0.1.14-universal.zip` | `58bf1549309c433c8ee42c3738f4ba98cb80be651f58614160a011a7c8095182`（7,019,769 B） |
| 宿主执行 `Lampyris.app/Contents/MacOS/Lampyris` | `add68cc6125ff87ce4262d56f3771722736da76c689a87cc22b42cd9f5763217` |
| 更新程序执行 `LampyrisUpdateCheck` | `02bc110f44df3fba88f8feb1a2af4644bb2dab5516cacb536cebcb397c23bfdb` |
| 本地组装的 DMG（同一候选 app + 本地构建的安装器/卸载器） | `ea0b9e42471587c0a8b46912bc792c7609f84cd971195106c852741eb99d988d` |

证据目录：air 上 `platforms/macos/build/acceptance-air-e10e6ed/ev/`（不入库）。

## 1. 结论

| # | 验收项 | 结果 | 证据 |
|---|---|---|---|
| 1 | 装完 → 菜单「检查更新…」直接开更新窗口，不跳网页 | **PASS**（ZIP/CLI 装包路径；DMG 路径未验——本机无 CI 公证 DMG） | `01a-menu-press.txt`、`01b-installed-updater-window.txt`、`ev-04` |
| 2 | `~/Applications/LampyrisUpdateCheck.app` 存在；旧名迁走留备份 | **PASS** | `02-post-install.txt`、`03-cli-overwrite.txt` |
| 3 | CLI 覆盖升级不再报「已有不同版本」 | **PASS** | `03b-production-cli-overwrite.txt`、`03-cli-overwrite.txt` |
| 4 | 真实升级一次 → 更新程序版本同步 + 「重新打开更新程序」 | **BLOCKED** | 见 §5-P4 |
| 5 | 更新窗口「卸载萤火虫…」→ 保留数据卸载 + 更新程序自删 | **PASS**（窗口按钮，用户执行；另有 CLI 同核心证据） | `05-cli-uninstall-keepdata.txt`、`ev-04` |
| 6 | `--uninstall --purge-data` 彻底清理；隔离构建必须拒绝 | **FAIL（purge 未清数据）/ 拒绝面 PASS** | `06c-purge-data.txt`、`06d-data-integrity.txt`、`06a-isolated-refuses-uninstall.txt` |
| 7 | 卸载后注销重登录，输入法菜单无残留 | **PASS** | `ev-04-residual-after-logout.txt` |

**一句话**：ADR-294/295 的三条装包后行为在真机上成立，ADR-296 的自删除也成立；`--purge-data` 的「彻底清理」在 build 23 首候选上**不成立**（只删 `updates/`），已在本报告 §5-P1 定位、§7 修复并复验；7 项里 6 项 PASS，第 4 项仍 BLOCKED（无 publish 作业）。

## 2. 与上一份报告的差异

- 新增：0.1.14/build 23 候选在 air 上的装包后行为（旧名迁移、CLI 覆盖、自删除）首次取得真机证据。
- 推翻/修正：
  - **HANDOFF §3 的「pro 工具链损坏 = 项目环境共性」不成立**：air 上 `make macos-offline-tests` **54/54 文件、297 例全 PASS**，`test-controller-menu` / `test-sandbox-config` 均通过 → 那 2 项 FAIL 是 **pro 机器本地的 CLT SDK 损坏**（`CVBuffer.h` 含 NUL 字节），不是代码问题。
  - **ROADMAP 第 12 行所述「publish 作业合并 `site/drill/` 部署 Pages」在当前工作流里不存在**：`.github/workflows/isolated-update-drill.yml` 只有 `build` 作业，没有 publish。这是第 4 项无法就地复验的直接原因（见 §5-P6）。
- 不变的：零网络/零遥测门禁（`make verify` 25s PASS，含 `verify-no-network`）。

## 3. 过程（可复现）

```sh
git fetch origin --prune && git switch dev && git pull --ff-only
make verify && make macos-offline-tests
gh run download 40472068259 -n Lampyris-macos-acceptance-e10e6ed… -D platforms/macos/build/acceptance-air-e10e6ed/
# 生产位 CLI 覆盖（候选包自带入口；宿主需已退出，当前源先切 ABC）
tools/macos-probe/bin/tissrc select com.apple.keylayout.ABC
pkill -x Lampyris
bash …/candidate-kX7GlH/ex/Lampyris-0.1.14-universal/scripts/install.sh \
     --app …/candidate-kX7GlH/ex/Lampyris-0.1.14-universal/Lampyris.app
# 卸载 / 清理
~/Applications/LampyrisUpdateCheck.app/Contents/MacOS/LampyrisUpdateCheck --uninstall
…/LampyrisUpdateCheck --uninstall --purge-data
```

| 步骤 | 结果 | 备注 |
|---|---|---|
| `make verify` | PASS（25 s） | fmt/lint/test/deny/verify-no-network 全绿 |
| `make macos-offline-tests` | **54/54 文件、297 例 PASS** | air 的 CLT SDK 正常 |
| 合并 PR #201 | merge commit `e10e6ed6` | `gh pr merge` 先返回 502 且残留 "merge already in progress" 锁；改用 REST `PUT /pulls/201/merge` 成功（`dev` 已快进） |
| 生产位 CLI 覆盖 | rc=0，`旧版本已备份：…/updates/install-backup-20261027T091235Z` | 无「已有不同版本」 |
| 私有 HOME 覆盖（对照） | rc=0，旧名 `Lampyris Update.app` → `install-backup-20261027T091237Z` | 与生产位行为一致 |
| `--uninstall`（保留数据） | 移除 25 项；app/更新程序消失；config 与 706 行词库保留 | 更新程序本体在进程退出后被 detached `/bin/sh` 删除 |
| `--uninstall --purge-data` | **移除 2 项，配置与词库未删** | 与打印文案矛盾，见 §5-P1 |
| 隔离构建 `--uninstall [--purge-data]` | 两种模式均 rc=2「隔离构建不允许卸载生产安装。」 | 生产执行/config/词库哈希未变 |

## 4. 环境与身份

| 项 | 值 |
|---|---|
| 设备 / 系统 / 架构 | air（`joker`）/ macOS 27.0.1（26A434）/ arm64 |
| 会话形态 | `launchctl managername` = **Background**（非 Aqua）→ AX 可读，`AXPress` / `CGEvent` 无法驱动 GUI |
| 已装包（验收中） | 0.1.14 / build 23 / 执行 `add68cc6…`（= 候选） |
| 更新程序（验收中） | 执行 `02bc110f…`，`spctl` = Notarized Developer ID，universal |
| 配置 / 词库 | `3bc1117c…`（8 个显式 `hotkey.*`）/ 706 行 `2dcea8f1…`；**全程未变**（purge 未生效，见 P1） |
| 输入源（验收后） | 卸载器已切 ABC 并停用 `Lampyris*`；重装后系统未自动注册 → 需手动添加 |
| 回滚点 | `uninstalled/bundle.*` 11 份（0.1.13 等）+ 候选 ZIP `58bf1549…`（重装）；config/词库备份 `/tmp/lampyris-verify-backup2/`。注：卸载前另有一份旧包整包 `/tmp/rollback-a165f05c.zip`，已随本轮重启的 `/tmp` 清理 |

## 5. 发现的问题与处置

| # | 现象 | 归因 | 处置 | 复验 |
|---|---|---|---|---|
| P1 | `--uninstall --purge-data` 打印「已彻底清理配置与个人词库」，实际 `config.toml`、`user-dictionary.tsv`、`uninstalled/` 全在；只删了 `updates/` | **产品缺陷**：更新程序传 `InstallLocation.support`（= `…/Lampyris/updates`）给 `UninstallPaths.support`，而 `UninstallerCore` 把该字段当**数据根**（DMG 卸载器传的是 `…/Lampyris`，所以两入口行为不同） | 记 FAIL，不在本验收批次改代码；建议修法：`InstallLocation` 增 `dataRoot`（或更新程序传 `home/Library/Application Support/Lampyris`），并在 `test-dmg-updater.py` 增加「purge 后数据根不存在」断言 | 待新候选 |
| P2 | 菜单动作按 bundle id 定位更新程序时，LaunchServices 在本机解析到**仓库里的旧 dev 副本** `platforms/macos/build/website-updater`（0.1.13/21） | 产品在 dev 机上的边界：`UpdateEntry.updaterURL()` 先问 `NSWorkspace.urlForApplication`，仓库构建产物也被注册 | 建议：优先 `~/Applications/LampyrisUpdateCheck.app` 精确路径，LaunchServices 仅作兜底；dev 机清理 `build/website-updater` | 待评估 |
| P3 | `--uninstall`（保留数据）保留了 `uninstalled/`（历史包/数据备份） | 与 DMG 文案「移除：…更新备份」不完全一致，语义未澄清 | 报告披露；需 ADR 级别澄清是否属于「更新备份」 | 待定 |
| P4 | 第 4 项无法就地复验 | 无任何高于 0.1.14 的已签名发布；生产更新私钥不在本机；隔离 drill 需要把 `/drill/` 发布到 `input.jokerhub.cn`，而该 publish 作业已不存在（P6） | 记 BLOCKED；离线侧本轮覆盖：更新程序 28+7 XCTest、`test-dmg-updater.py` 18 例、`test-installer2`/`install-core` 卸载断言 | 需单独授权补 publish 作业 |
| P5 | 09:27 回读生产包执行 SHA 为**旧包** `a165f05c…`（09:12 安装后回读为 `add68cc6…`） | 未定位：期间仅本会话执行过 pkill/重启宿主与 AX 菜单操作，未执行任何安装 | 不影响 09:12 / 09:28 两次安装证据（均为即时回读）；已记录，待复现 | 待复现 |
| P6 | ROADMAP 第 12 行称 drill 工作流会把 artifact 合并 `site/` 部署 Pages | 文档与实现不一致：工作流只有 `build` | 记文档 bug，随 ROADMAP 修正 | — |

## 6. 待做

1. 修 P1（`--purge-data` 数据根错位）→ 出新候选 → 复验第 6 项；顺带在 `test-dmg-updater.py` 固化「purge 后数据根消失」断言。
2. 用户在**图形会话**补一次第 1 项端到端点击（菜单「检查更新…」）、第 5 项窗口按钮、第 7 项注销后回读。
3. P2/P3 需要一次取舍（更新程序定位优先级、`uninstalled/` 是否算更新备份）。
4. 第 4 项要真正闭环，得先补 ADR-288 的 publish 作业并单独授权一次 Pages 部署。

## 7. 修复后复验（候选 `6d89821`，PR #202）

P1/P2 修复合入 main `6d898211b8494f65233aecd04ba4065a0e34ca02`（PR #202，四项 CI PASS），重新出候选并在 air 上装包复验：

| 产物 | SHA-256 |
|---|---|
| `Lampyris-0.1.14-universal.zip` | `90ed224d8aa6e2d020f1b5fd372b51875b0a858b57c503438165192052e8f3ae` |
| 宿主执行 | `0669f2493a293cafcb78e76aafd600f6ffe592d7434db758d42ea4e8ecd04fd1` |
| 更新程序执行 | `fbbbc11be28a638f5a358e8500317dbb849cd315d483e61ac20ec607fc6774ee` |

| 复验项 | 结果 | 证据 |
|---|---|---|
| **P1**：`--uninstall --purge-data` 真删数据 | **PASS** | 执行后 `…/Application Support/Lampyris` **整个不存在**（config、词库、`uninstalled/`、`updates/` 全清），宿主/更新程序/TIS 项同时清空（`ev-02-purge-fixed.txt`） |
| 数据可还原 | PASS | 从 `/tmp/lampyris-verify-backup3/` 还原后与备份逐字节一致：config `3bc1117c…`、词库 713 行 `8dbd41f4…`（`ev-03-restore.txt`） |
| **P2**：菜单定位到已装更新程序 | PASS（单元 + 实机） | `updaterURL()` 先扫 `~/Applications`→`/Applications`；实机 `LS_resolved=~/Applications/LampyrisUpdateCheck.app` build 23，仓库旧构建产物已清理（`ev-01-install.txt`） |
| 新候选装包 | PASS | 宿主 `0669f249…`、更新程序 `fbbbc11b…`（`ev-01-install.txt`） |

第 1/5/7 项的人工证据由用户在图形会话补齐，见 §8。

**注意**：本轮两个候选都是 build 23（`macos-acceptance` 不自动递增构建号），所以「更新程序版本同步」这类按构建号比较的行为无法在两份候选之间演示；它不影响 P1/P2 的复验，但第 4 项闭环时应使用更高的构建号。

## 8. 人工图形会话复验（用户执行，候选 `90ed224d…`）

pi 的会话是 Background（`AXPress`/`CGEvent` 到不了 Aqua），第 1/5/7 项由用户在本机操作，结果是「与描述一致」：

| 项 | 用户动作 | 结果 |
|---|---|---|
| 1 | 加回输入源 → 菜单「检查更新…」 | 直接弹出更新窗口 `当前版本 0.1.14 · 构建 23`，未跳网页、未命中旧 0.1.13 副本（同时验证 §5-P2 修复） |
| 5 | 窗口「卸载萤火虫…」→「卸载（保留配置与词库）」 | 卸载完成；`~/Applications/LampyrisUpdateCheck.app` 在进程退出后消失 |
| 7 | 注销重登录 | 见下 |

注销后回读（`ev-04-residual-after-logout.txt`）：

| 检查面 | 结果 |
|---|---|
| TIS 输入源 | 无 `cn.jokerhub.inputmethod.Lampyris*`（当前源为搜狗拼音） |
| 输入法菜单 | 无「萤火虫」条目 |
| `~/Library/Input Methods/Lampyris.app`、`~/Applications/LampyrisUpdateCheck.app`、旧名 `Lampyris Update.app` | 均不存在 |
| 进程 | 无 `Lampyris*` 进程 |
| Preferences / Caches / Logs | 无残留 |
| 用户数据（保留数据模式） | `config.toml` `3bc1117c…`、词库 **713 行** `8dbd41f4…`，与卸载前一致 |

结论：ADR-296「已安装版本自带卸载」的保留数据模式在真机上**全链路成立**，卸载后系统侧无残留。
