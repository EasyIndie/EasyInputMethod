# 171 DMG 图形安装器

## 交付

- `platforms/macos/Installer`：通用（arm64 + x86_64）AppKit 安装器，无网络；
- 安装流程：校验同目录 `Lampyris.app` 身份与签名 → 停止旧宿主 → 备份到
  `updates/dmg-backup-<时间>` → 原子写入 `~/Library/Input Methods/Lampyris.app` →
  安装后复验/失败回滚 → `LampyrisTIS` 注册与启用；
- `packaging/macos/make-dmg.sh`：把已签名 app、安装器与说明打进
  `Lampyris-<version>-universal.dmg`；
- Release 工作流新增：构建安装器 → `--sign-only` 签名 → 生成 DMG → `--dmg` 签名/公证/装订 → 作为附件发布。

## 版本与显示

- 0.1.10 / build18；
- 更新窗口标题改为「更新」；版本显示统一为 `0.1.10 · 构建 18`（与关于页一致）。

## 验证

- 安装器双架构构建通过；临时目录实测新装与覆盖安装（备份生成、版本正确）；
- 安装器 UI 显示图标、版本、说明与主按钮；
- `make verify`、macOS 离线回归、`test-ci-sign.py` 通过；
- DMG 由 `hdiutil` 生成，发布前由 CI 签名/公证。
