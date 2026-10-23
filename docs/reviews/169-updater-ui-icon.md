# 169 更新程序图标与窗口美化

## 变更

- 更新程序内嵌 `assets/icons/yinghuo-official-app.icns` 为 `AppIcon.icns`，
  `CFBundleIconFile=AppIcon`，并在启动时设置 `NSApplication.applicationIconImage`；
- 更新窗口固定 520pt 宽，版式为：图标 + “萤火虫” + 当前版本 → 分隔线 →
  状态标题 → 说明 → 进度条 → 右对齐主/次按钮 → 底部验签说明；
- 主按钮“下载并安装”使用强调色与回车键，未发现新版本时禁用。

## 验证

- `lipo -archs = x86_64 arm64`；
- 启动后 `NSRunningApplication.icon` 为官方图标（非通用占位）；
- 窗口尺寸 520×290（含标题栏），浅色/深色均使用系统动态颜色；
- `make macos-updater-tests`、`make verify` 通过。

## 版本

0.1.7 / build15。
