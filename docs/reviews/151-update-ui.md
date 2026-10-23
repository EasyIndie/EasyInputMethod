# 151 更新界面与 Swift 安装器（ADR-271）

## 交付

- **更新窗口**（`--ui`，AppKit 最小实现）：当前版本 → 检查更新（主源→镜像）→ 新版本/大小/来源 → 下载进度 →
  验签 → 确认框（说明会短暂停止宿主、自动备份、失败回滚）→ 安装 → 结果/失败原因。
  没有后台检查、没有静默安装；只有点击“检查更新”才联网。
- **Swift 安装器** `UpdateInstaller`：与 `packaging/macos/upgrade.py` 语义一致
  （验签 → 解包（支持发布包装目录）→ 候选校验 → 只停精确宿主（忽略 lsd 等持有者）→ 备份 → 原子替换 → 落地复验 → 回滚 → 0600 receipt）。
- **下载器** `UpdateDownloader`：https-only、同主机直链或 GitHub 资产主机重定向、256MB 上限、0600 临时文件、进度回调。
- 生产环境校验/停宿主封装在 `DefaultInstallEnvironment`（codesign/stapler/spctl/PlistBuddy + lsof/ps/SIGTERM）。

## 验证

| 项 | 结果 |
|---|---|
| 更新程序测试 | 22 项全过：新增安装器 6 项（全新安装/升级备份/落地复验失败回滚/坏签名/ dry-run/歧义包装与符号链接）+ 下载策略 2 项 |
| 构建 | `make macos-updater-tests`、`build.py` 严格 release 通过 |
| UI 冒烟 | 启动 `LampyrisUpdateCheck --ui`，窗口标题「萤火虫更新」可见，进程随后精确停止 |
| 既有回归 | `make verify`、`make macos-offline-tests` 全绿 |

## 边界

- UI 未本地化、未做取消/断点续传/自动检查；镜像选择仍走配置（设置 → 更新）。
- 未在真实网络下点完「检查→下载→安装」全流程（签名与安装逻辑已分别用真实包/夹具验证）。
- Swift 与 Python 安装器需同步演进；改动必须同时补两侧测试。
- 未发新 Release、未改动已装 v0.1.0 生产包。
