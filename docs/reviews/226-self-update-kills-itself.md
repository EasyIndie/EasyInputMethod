# 226 更新器自更新把自己杀了（ADR-306）

> 背景：v1.0.0 → v1.0.1 的真机升级演练（第一次由 build 34 更新程序执行）。
> 目标：闭环长期挂着的验收项「更新器自更新」。

## 1. 现象（2026-11-05，air）

用户点「安装更新」后：

| 项 | 期望 | 实际 |
|---|---|---|
| 宿主 | 1.0.1/36 | **36** ✅ |
| 更新程序 | 36 | **34** ❌（bundle mtime 仍是 10-30） |
| `updates/receipts/` | 写入回执 | **目录不存在** ❌ |
| 备份 | 成功保留 | `upgrade-…/backup/Lampyris.app` = 1.0.0 ✅ |
| staging | 成功清理 | `upgrade-…/staging` 与 `~/Applications/.lampyris-install-…` 残留 ❌ |

同样的半成品状态复现了两次（两次之间把现场清理并装回 1.0.0/34）。

## 2. 排除"逻辑 bug"

用仓库里的 `UpdateInstaller.install` 在**临时目录**跑同一套参数（真实 1.0.1 包、appcast 里的
`edSignature`、包内 `SUPublicEDKey`）：

```
payloadSHA256 = cba74da4…   installedExec = 5d760c8a…
previous=nil                updaterBundle=…/Applications/LampyrisUpdateCheck.app
receiptsExists = true
```

再把它指向**生产路径**（宿主已在 36，替换为同版本）——同样成功，更新程序被换成 36、回执写入。
所以 `install` 逻辑本身没问题，差异在"更新程序正在替换它自己"。

## 3. 根因

`UpdateInstaller.replaceBundle` 在替换前统一调用
`environment.stopHost(destination/<target.executablePath>)`。
自更新传入的环境是 `DefaultInstallEnvironment.make(target: .updater)`，它的 `stopHost`
用 `lsof -t` 找该可执行文件的持有者并 `SIGTERM`——**持有者就是正在跑这次安装的更新程序**。
于是：宿主换好 → 尝试自更新 → 自己被杀 → 回执未写、staging 未清、`defer` 不执行。
这与 ADR-295 的注释「运行中的实例保持不动，下次启动生效」正好相反。

为什么以前没发现：单测用的是注入的假环境（`stopHost` 空实现）；隔离演练（`--drill-run`）里
`applications == nil`，根本不做自更新。所以真实路径从未被走过——这也解释了该验收项为何长期 BLOCKED。

## 4. 修法（ADR-306）

`DefaultInstallEnvironment.stopsRunningInstance(_:)` 成为唯一判定点：`.updater` → false（不停），
`.production` → true。`stopHost` 开头判定后直接返回。

## 5. 验证

- `install-core.swift` 新增两条断言（生产停、自更新不停）
- 真机复验：见本报告后续追加（将在 1.0.2 发布后执行：更新程序 ≥ 宿主版本的一次安装，
  检查回执写入、staging 清理、更新程序被替换且进程不再自杀）

## 5. 真机复验（2026-11-05，air，1.0.2 / build 37）

做法：装 1.0.2（宿主与更新程序都是 37，含修复），用仓库里既有的**演练专用**比较基准
`LAMPYRIS_UPDATE_CURRENT_BUILD=30` 启动更新程序，使它认为"有新版本 37"，从而走完整安装 + 自更新分支
（`WebsiteReleaseConfiguration.currentBuild` 注释即为此用途）。

在更新程序窗口里点「安装更新」后核对：

| 项 | 结果 |
|---|---|
| 回执写入 | `updates/receipts/2026-11-05T10-11-57Z.json` ✅ |
| `payloadSHA256` | `732756e5…` = **已发布的 1.0.2 ZIP** ✅ |
| 宿主执行 | `b0b3bf5c…`（1.0.2/37）✅ |
| 旧宿主备份 | `upgrade-2026-11-05T10-11-50Z-…/backup/Lampyris.app` ✅ |
| **更新程序被替换** | `~/Applications/LampyrisUpdateCheck.app` mtime = 负载内同名 bundle 的 mtime（17:35:44），旧版在 `.lampyris-updater-backup-2026-11-05T10-11-54Z`（4.3 MB，build 37）✅ |
| **进程未被自己杀掉** | 安装持续到写完回执（10:11:54 替换 → 10:11:57 回执）✅ |
| staging 清理 | `upgrade-…/` 只剩 `backup/`；`~/Applications/.lampyris-install-*` 无残留 ✅ |
| 用户数据 | config `5d4271fb…`、词库 1124 行，与升级前一致 ✅ |

**结论：ADR-306 的修复经真机验证通过；长期挂着的「更新器自更新」验收项闭环。**

## 6. 同批发现的两处记账/门禁问题（已修或已排期）

1. **回执漏记自更新结果**：`ReceiptPayload` 没有 `updaterBundle` 字段，导致本次只能靠 mtime 与备份目录反推"更新程序真被替换了"。
   已在源码补上该字段并加断言（`install-core.swift` 7b 段），随下个版本发布。
2. **发布工作流取产物失败**：`gh run list --commit X --status success` 对 1.0.2 的提交返回空，而两个条件单独都正常；
   改为只按提交过滤、在 jq 里判 `completed && success`（PR #220）。
