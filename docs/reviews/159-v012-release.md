# 159 v0.1.2 发布：更新程序静态链接 + 检查更新快捷键

## 发布

| 资产 | 说明 |
|---|---|
| `Lampyris-0.1.2-universal.zip` | 5,231,027 B；build 10；universal；已签名/公证 |
| `LampyrisUpdateCheck-0.1.2.zip` | 470,128 B；更新程序 build 10；**静态链接**（`otool -L` 无 `libime_ffi.dylib`）、公证通过 |
| `appcast.xml` | `sparkle:version=10` |
| `Lampyris-0.1.2-source.tar.gz` | 对应源码 |

- 已移除 v0.1.1 的坏更新程序资产（启动会因缺 dylib 崩溃），避免用户下载。

## 修复与新增

1. **更新程序静态链接**：v0.1.1 的 dylib 依赖构建机绝对路径；改为链接 `libime_ffi.a`，其他机器可正常启动（本地 `--ui` 窗口验证）。
2. **查找更新程序优先 LaunchServices**，再回退 `~/Applications`、`/Applications`。
3. **新增 `hotkey.open_update`（默认 `alt+g`）**：设置「快捷键」分区可见、菜单「检查更新…」右侧显示、控制器按键与菜单点击同源。

## 本机安装（RC）

- 生产包升级到 **0.1.2 / build10**（执行 `37decc06…`，universal、公证），旧 build8（`3c9c199f…`）备份在 `updates/rc-build10-backup/`。
- 更新程序 0.1.2 已装到 `~/Applications/Lampyris Update.app`。
- **配置/词库 SHA 在升级后发生变化**（`809e2cae…` / `f3e2eef…`，词库 69 行）：属于新 Schema 键写入与用户正常学习，已记录为当前基线，不是数据丢失；`mode=mixed`、快捷键保持。

## 待实测

- 在生产输入源下按 **⌥G** 或点菜单「检查更新…」，应打开「萤火虫更新」窗口（当前 build10，应显示已最新）；
- 如快捷键与其他应用冲突，可在 设置 → 快捷键 → 检查更新 修改或设为 none。

## 证据

`docs/reviews/159-v012-evidence/01-release-and-install.txt`。
