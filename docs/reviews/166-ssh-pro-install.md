# 166 通过 `ssh pro` 升级第二台设备到 0.1.5

## 设备

- 连接别名 `pro`（`ssh pro`），macOS 13.7.8，Intel `x86_64`；
- 控制台登录用户与 SSH 用户一致，输入法已启用；
- 升级前：`0.1.2/build10`，执行 `37decc06…`，宿主正在运行（另有一个从 AppTranslocation 启动的旧副本进程）。

## 过程

1. 远端下载 `Lampyris-0.1.5-universal.zip`，SHA-256 与 Release 的 `.sha256` 一致（`33c09aab…`）；
2. `codesign --verify --deep --strict`、`stapler validate`、`spctl` 均通过；
3. 校验宿主进程路径后停止旧宿主；旧 bundle 备份到
   `~/Library/Application Support/Lampyris/updates/ssh-build10-backup/Lampyris.app`；
4. 用发行包内 `scripts/install.sh --app …` 安装；
   `LampyrisTIS` 自动注册并启用输入源；
5. 停止从 AppTranslocation 启动的旧 `0.1.2` 副本进程（路径校验后），避免同标识双宿主；
6. 安装 `LampyrisUpdateCheck-0.1.5.zip` 到 `~/Applications/Lampyris Update.app`（SHA-256 `356e7a26…`）。

## 结果

| 项 | 值 |
|---|---|
| 版本 | `0.1.5/build13` |
| 执行 SHA-256 | `8d530aa8…` |
| 配置 | `2bd3fde6…`（升级前后一致） |
| 用户词库 | `ee1d9aed…`（升级前后一致） |
| 旧版备份 | `ssh-build10-backup`（`37decc06…`） |
| 输入源 | `enabled`，当前 `cn.jokerhub.inputmethod.Lampyris.default` |
| 更新程序 | `0.1.5/build13` |

未改动远端用户配置与词库；未自动切换当前输入源（`TISSelectInputSource` 对第三方源的既有边界）。
