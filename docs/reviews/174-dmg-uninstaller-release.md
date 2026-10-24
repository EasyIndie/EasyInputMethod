# 174 v0.1.12：DMG 卸载器上线

## 发布

- **0.1.12 / build20**；
- `Lampyris-0.1.12-universal.dmg`（9.55 MB，SHA-256 `1f48477d…`），
  已签名、公证并装订；
- DMG 内容：
  - `Lampyris.app`（0.1.12/build20，universal）
  - `安装萤火虫.app`（universal）
  - `卸载萤火虫.app`（universal，build20）
  - `安装与卸载说明.txt`
- 说明文档覆盖：系统要求、安装步骤、两种卸载方式、数据位置、
  常见问题、隐私/许可。

## 卸载器

- **保留配置与词库**：只保留
  `~/Library/Application Support/Lampyris/config.toml` 和 `user-dictionary.tsv`；
  删除应用、更新程序、`Lampyris-install-backups`、`updates/`、`uninstalled/`、
  缓存、偏好设置、保存状态、诊断日志（含隐藏文件）。
- **彻底清理**：再删除整个 `Lampyris` 数据目录，并核验目标路径无残留。
- 两种模式都会切回 ABC、禁用输入源、退出宿主/更新程序；提示注销以完成菜单清理。

## 验证

- 临时 home 夹具：
  - 保留模式后只剩 `config.toml`、`user-dictionary.tsv`；更新备份、隐藏文件、缓存、偏好、诊断日志均删除；
  - 彻底清理后相关路径全部不存在；
  - 与生产无关的 `LampyrisPreview` 崩溃日志保留。
- DMG 内两个工具均 `codesign --verify --deep --strict` 通过，双架构；
- `.sha256` 与 DMG 内容一致；
- 本机与 `pro` 均升级到 0.1.12/build20（旧 build19 备份），配置/词库按预期保留。

## 备注

- 输入源注册表由 macOS 管理，卸载器调用 `TISDisableInputSource` 并提示注销；
  不直接改写 HIToolbox 偏好。
- 下载的 DMG、用户主动导出的文件不在清理范围内。
