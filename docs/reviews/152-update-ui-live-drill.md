# 152 更新 UI 真实全流程演练

## 结论

用真实 GitHub feed 在界面上跑通 **检查 → 下载 → 验签 → 确认 → 安装 → 结果**：
最终生产包仍为 v0.1.0/build6（`5709716c…`，universal、公证通过），配置与个人词库**字节未变**，输入源已还原 ABC。

## 步骤与结果

| 步骤 | 结果 |
|---|---|
| 启动 | `LampyrisUpdateCheck --ui`（本地构建，入库公钥），窗口「萤火虫更新」 |
| 检查 | 显示“发现新版本 build 6”，大小约 5.0 MB，来源 `github.com`（主源命中，未使用镜像） |
| 下载 | 进度条走完（5,223,049 B），自动验签通过 |
| 确认 | 弹出“安装 build 6？”（说明会短暂停宿主、自动备份、失败回滚） |
| 安装 | 成功：精确停止生产宿主 → 备份 → 替换 → 落地复验 → 写 receipt |
| 结果 | “已安装 build 6”，备份路径 `updates/upgrade-2026-10-23T06-14-34Z-2592AA70/backup/Lampyris.app` |

## 演练中发现并修复的问题

1. **候选标识比较未去空白**：`PlistBuddy` 输出带换行，导致合法包被判“标识不符”，安装失败；
   已在 `DefaultInstallEnvironment` 里 trim，并给 `InstallError` 实现 `LocalizedError`，界面显示可读原因而不是 `error 0`。
2. 新增**仅测试用**的 `LAMPYRIS_UPDATE_CURRENT_BUILD` 环境变量覆盖“当前构建号”，便于演练“有新版本”；
   正式包不设置即按 Info.plist，不影响用户。
3. 演练前一次失败（payloadMissing）由上述标识问题连带引发，修复后复测通过。

## 数据与安全校验

- 安装前后生产 `config.toml` `3bc1117c…`、词库 `74f76e92…`（29 行）不变；输入源 ABC；
- 生产包 `codesign --deep --strict`、`stapler validate`、`spctl` 通过，架构 `x86_64 arm64`；
- receipt 权限 `-rw-------`（0600）；旧包保留在备份目录；宿主与 UI 进程均已退出。

## 边界

- 只验证了“同版本重装”路径；未验证跨版本（build7+）与新版本首次启动；
- 未测试镜像回退下的 UI（主源可用）；
- 未处理取消/断点续传、自动检查与本地化。

## 证据

`docs/reviews/152-ui-flow-evidence/`：`01-check.txt`、`02-download.txt`、`03-install.txt`、`04-post.txt`、`05-cleanup.txt`。
