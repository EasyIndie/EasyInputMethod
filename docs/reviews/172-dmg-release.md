# 172 v0.1.10：DMG 图形安装与版本显示统一

## 发布

- **0.1.10 / build18**；
- `Lampyris-0.1.10-universal.dmg`（7,035,? B，SHA-256 `a2452aa8…`），已签名、公证并装订；
- DMG 内容：`Lampyris.app`（0.1.10/build18，universal）、`安装萤火虫.app`（universal）、`安装说明.txt`；
- `Lampyris-0.1.10-universal.zip`、`LampyrisUpdateCheck-0.1.10.zip` 同一构建。

## DMG 验证

- `shasum -a 256` 与 `.sha256` 一致（0.1.9 的摘要在签名前生成导致不匹配，已改为签名后生成）；
- `xcrun stapler validate`、`spctl --assess --type open` 通过；
- DMG 内安装器 `codesign --verify --deep --strict` 通过，双架构；
- 安装器在 Intel 机器 `pro` 上可正常启动并成为前台应用（未实际点击安装，避免打断当前输入法）。

## 版本显示

- 更新窗口标题：`更新`；
- 关于页 / 更新窗口统一为 `0.1.10 · 构建 18`。

## 本机与 `pro`

- 两台设备均由 CLI 升级到 0.1.10/build18（旧 build17 备份为 `build18-backup` / `ssh-build18-backup`）；
- 更新程序均替换为 build18；
- 配置未变（本机 `809e2cae…`，`pro` `31a0cc71…`）；词库未变。
- `pro` 的 DMG 保留在 `~/Downloads/Lampyris-0.1.10-universal.dmg`，可直接双击「安装萤火虫」体验图形安装。
