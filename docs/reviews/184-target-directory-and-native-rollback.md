# 184 目标目录语义与原生回滚演练

## 1. ADR-289：目标目录缺失时显式失败

- 安装器在解包、停宿主之前检查目标目录（生产 `~/Library/Input Methods`，隔离 `<私有根>/Input Methods`）；不存在则抛 `InstallError.domainMissing(路径)`。
- 不自动创建目录、不停止宿主、不写 staging；更新器只负责替换既有安装。
- 新增 XCTest `testMissingTargetDirectoryIsRejectedBeforeStoppingHost`：断言错误类型、宿主未被停止、`support` 未被创建。updater 40 + 7 项 PASS。
- 起因：上一轮 drill 在空私有根上安装时报 Foundation 的模糊 “couldn't be moved … folder doesn't exist”，且当时已建 staging；现在错误可读且副作用为零。

## 2. 原生回滚演练（真实载荷、真实安装器）

- 隔离构建新增 `--drill-run rollback`：包装真实 `DefaultInstallEnvironment`，在候选包**落地后**的第二次 `validateCandidate` 注入失败，其余步骤（下载、验签、停宿主、备份、替换、回滚、receipt、清理）全部走产品代码。
- 运行：run `40141817920`（main `167a644`），载荷 `LampyrisIMKTest-906-arm64.zip`，更新程序 build 905；私有根 `…/T/lampyris-imk-871fd1e2-…`。

| 观测 | 值 |
|---|---|
| 演练前安装槽执行 SHA | `c9f05b977924ed2fcb6814caf44f3970692a205f2b8140f2628ff29c54cd5a21`（上一版 906 种子包） |
| 注入错误 | `候选校验失败：drill 注入：落地后校验失败` |
| 演练后执行 SHA | 同上（旧包已恢复） |
| work 目录数（staging/upgrade-*） | 前 0 → 后 0 |
| receipt | 0 份（失败不写 receipt） |
| 下载临时目录 | 已清理（系统临时目录仅剩 2026-10-23 旧遗留项） |
| 结论 | `result=rolled-back` |

- 期间生产侧未变：执行 SHA `c09c2d11…`、`config.toml` `3bc1117c…`。

## 3. 更新窗口「取消」按钮（用户图形会话，2026-10-25 07:40Z）

用户在桌面会话点击「检查更新 → 下载并安装 → 取消」，窗口状态显示 **「已取消」**。磁盘侧同步核对：

| 观测 | 值 |
|---|---|
| 安装槽执行 SHA | `c9f05b97…`（与演练前一致，未被替换） |
| receipt | 0 份 |
| `updates/upgrade-*` | 0 个 |
| 下载临时目录 | 无新增（系统临时目录仅剩 2026-10-23 旧遗留项） |
| 生产侧 | 执行 SHA `c09c2d11…`、`config.toml` `3bc1117c…` 未变 |

结论：UI 取消路径不安装、不写 receipt、不残留临时文件，与 `--drill-run cancel` 的清理证据一致。

## 4. 收尾（2026-10-25 07:42Z）

- 关闭残留的测试更新程序进程（精确路径 SIGTERM）。
- 普通 `Pages` 工作流（run `40143742966`，main `167a644`）重新部署：`/drill/appcast.xml` → **404**，站点首页 200。
- 私有根 `…/T/lampyris-imk-871fd1e2-…` 整体删除，无 `lampyris-imk-*` 残留。
- 生产宿主 PID 78677、执行 SHA `c09c2d11…`、`config.toml` `3bc1117c…` 未变；输入源仍为生产 `Lampyris.default`。

至此隔离更新通道的取消、篡改拒绝、安装、备份、回滚与 UI 确认六个路径均有真实证据。
