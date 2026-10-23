# 156 RC 候选 build8（检查更新入口 + 更新程序分发）

## 候选

- 来源：main `45db5a2`（`macOS Acceptance Package` run `39924589316`），0.1.0/**build8**。
- 验收包：`Lampyris-0.1.0-universal.zip` SHA-256 `b0513b56…`；执行 `3c9c199f…`；`x86_64 arm64`。
- 静态核验：Developer ID（Team 2N62934Y28）、`codesign --deep --strict`、`stapler validate`、`spctl` accepted。
- 内容确认：二进制含 `checkForUpdates` 选择器（输入法菜单「检查更新…」入口已编入本候选）。

## 已安装（生产身份，RC 演练）

| 项 | 值 |
|---|---|
| 安装方式 | 停精确宿主 → 旧包移到 `updates/rc-build8-backup/` → `install.sh` 校验后安装 |
| 当前生产包 | 0.1.0/build8，执行 `3c9c199f…`，universal、已公证 |
| 旧包备份 | `updates/rc-build8-backup/Lampyris.app`（build6，执行 `5709716c…`） |
| 用户数据 | `config.toml` `3bc1117c…`、个人词库 `74f76e92…` 安装前后一致 |
| 输入源 | 仍为生产源 `…Lampyris.default`，未改动 |

## 未完成

- **带更新程序的 Release 尚未发布**：需要新版本号（v0.1.1）与新 tag；当前 Release 仍为 v0.1.0（不含更新程序资产）。
- 菜单项的实际点击效果需在已安装 RC 上验证：未安装更新程序时应打开 Releases 页面；安装更新程序后应直接打开 `--ui` 窗口。
- 完整 RC 矩阵（三模式/重启/客户端/VoiceOver/多屏/睡眠/五日/A-B）未开始。

## 证据

`docs/reviews/156-rc-build8-evidence/00-install.txt`、`01-artifact-and-install.txt`。
