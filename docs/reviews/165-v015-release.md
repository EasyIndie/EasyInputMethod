# 165 v0.1.5：关于页显示构建号

## 发布

- 版本 **0.1.5 / build13**，主包 `8d530aa8…`（已签名/公证），appcast `sparkle:version=13`；
- 更新程序 `LampyrisUpdateCheck-0.1.5.zip` 已替换安装到 `~/Applications`；
- 生产包已升级，0.1.4/build12（`17d2a3dc…`）备份在 `updates/build13-backup/`；
- 配置 `809e2cae…` 未变；词库 `8bdfc50a…` 随正常学习变化。

## 关于页

副标题显示 `0.1.5 · 构建 13 · 开源中文输入法`，构建号来自 `CFBundleVersion`，便于从截图直接定位构建。

## 验证

`make verify`、macOS 离线回归（含关于页亮/暗快照）通过；实机打开「关于」确认文案。
