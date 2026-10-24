# 173 DMG 卸载器与安装/卸载说明

## 交付

- `platforms/macos/Uninstaller`：通用（arm64 + x86_64）AppKit 卸载器，无网络；
- 两个模式：
  - **保留配置与词库**：删除应用、`~/Applications/Lampyris Update.app`、
    `Lampyris-install-backups`、`updates/`、`uninstalled/`、缓存、偏好、保存状态、
    诊断日志；只留 `config.toml` 与 `user-dictionary.tsv`；
  - **彻底清理**：再删除整个 `~/Library/Application Support/Lampyris/` 并核验无残留；
- 两种模式都会调用 helper `switch-abc`/`disable`，退出宿主与更新程序；
- DMG 增加 `卸载萤火虫.app`，说明升级为 `安装与卸载说明.txt`（安装、两种卸载、数据位置、常见问题、隐私/许可）。

## 验证

- 临时 home 夹具实测：
  - 保留模式后只剩 `config.toml`、`user-dictionary.tsv`；缓存/偏好/更新备份均删除；
  - 彻底清理后应用、更新程序、数据目录、缓存、偏好、诊断日志全部不存在；
  - 与生产无关的 `LampyrisPreview` 诊断日志保留（不误删开发数据）。
- 安装器/卸载器双架构构建通过；DMG 内含两个工具和说明；
- `make verify`、离线回归、`test-ci-sign.py` 通过。

## 版本

0.1.11 / build19。
