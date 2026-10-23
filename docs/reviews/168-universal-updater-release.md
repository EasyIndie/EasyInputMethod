# 168 v0.1.6：通用更新程序上线与两台设备升级

## 发布

- **0.1.6 / build14**，主包 `38f83e99…`，appcast `sparkle:version=14`；
- `LampyrisUpdateCheck-0.1.6.zip`（`b35d3823…`）经 `lipo` 验证为 `x86_64 arm64`；
- 签名/公证/`stapler validate` 通过。

## Intel 设备（`ssh pro`）验证

- 旧 0.1.5 更新程序 `lipo -archs` 仅 `arm64`，LaunchServices 报“这台 Mac 不支持此应用程序”；
- 替换为 0.1.6 后，`open --args --ui` 进程保持运行、窗口正常创建，不再被系统拒绝；
- 主输入法升级到 0.1.6/build14，旧 0.1.5/build13 备份到
  `~/Library/Application Support/Lampyris/updates/ssh-build13-backup/`；
- 输入源保持 `enabled`，当前 `Lampyris.default`。

### 数据

| 时间点 | config | 词库 |
|---|---|---|
| 0.1.5 安装后（21:40） | `2bd3fde6…` | `ee1d9aed…` |
| 0.1.6 安装前（22:2x） | `31a0cc71…`（mtime 21:53） | `49bb857d…` |

两次升级脚本都不写配置/词库；中间的变化来自设备正常使用（配置在 21:53 被修改，早于本次升级）。

## 本机

- 主包升级到 0.1.6/build14（0.1.5/build13 备份到 `updates/build14-backup/`）；
- 更新程序替换为 0.1.6，`lipo -archs = x86_64 arm64`；
- Pages 安装命令指向 0.1.6。
