# 167 更新程序改为 universal（修复 Intel Mac 无法打开）

## 现象

在 `ssh pro`（macOS 13.7.8 / Intel）升级到 0.1.5 后，菜单「检查更新」弹出：
“你无法打开应用程序‘Lampyris Update’，因为这台 Mac 不支持此应用程序。”

## 原因

0.1.5 的 `LampyrisUpdateCheck.app` 只构建了 **arm64**（`lipo -archs` 仅 `arm64`）。
更新程序由 `platforms/macos/Updater/build.py` 在 arm64 主机上构建，SwiftPM 默认只产出宿主架构；
主输入法包是 universal，所以这个问题只在 Intel 机器触发。

## 修复

- `build.py` 对 `arm64`/`x86_64` 分别构建 Swift 可执行文件，并各自链接
  `target/<triple>/release/libime_ffi.a`，最后 `lipo -create`；
- 构建结束断言两个架构都存在，否则失败；
- Release 工作流为 Rust 安装两个 target。

## 验证

- 本机构建输出 `lipo -archs = x86_64 arm64`；
- `make macos-updater-tests`、`make verify` 通过；
- 新版本装到 Intel 机器后打开更新窗口验证（0.1.6/build14）。
