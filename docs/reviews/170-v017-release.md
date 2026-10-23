# 170 v0.1.7：更新程序图标与窗口美化上线

## 发布

- **0.1.7 / build15**，主包 `d461da58…`，appcast `sparkle:version=15`；
- 更新程序 `LampyrisUpdateCheck-0.1.7.zip`（`2a95f634…`），`lipo -archs = x86_64 arm64`；
- 包内含 `AppIcon.icns`（官方图标），Info.plist `CFBundleIconFile=AppIcon`；
- 签名/公证/`stapler validate` 通过。

## 本机与 `ssh pro`

- 更新程序均替换为 0.1.7/build15；Dock 图标为官方图标（`NSRunningApplication.icon` 已验证）；
- 主包均升级到 build15：
  - 本机旧 build14 备份到 `updates/build15-backup/`；
  - `pro` 旧 build14 备份到 `updates/ssh-build15-backup/`；
- 配置未变（本机 `809e2cae…`，`pro` `31a0cc71…`）；词库随正常输入增长。

## 窗口

固定 520pt 宽：图标 + “萤火虫” + 当前版本、分隔线、状态、说明、进度条、
右对齐“检查更新/下载并安装”、底部验签说明；仅展示变化，不改更新流程。

## Pages

安装命令已指向 0.1.7。
