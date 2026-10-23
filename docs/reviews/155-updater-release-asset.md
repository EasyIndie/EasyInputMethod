# 155 更新程序作为 Release 资产（ADR-274）

## 变更

- `packaging/macos/ci-sign.sh` 新增 `--app <path.app>`（默认仍是主应用），可对**更新程序**单独签名/公证。
- Release 工作流新增两步：
  1. 用 Developer ID + `--options runtime --timestamp` 签名并公证 `LampyrisUpdateCheck.app`；
  2. 打包 `LampyrisUpdateCheck-<version>.zip` + `.sha256`，与二进制/源码/appcast 一并上传。
- Release 说明补充：安装更新程序到 `/Applications` 后，输入法菜单「检查更新…」会直接打开更新窗口。
- 输入法宿主仍零网络：菜单只经 LaunchServices 启动更新程序或浏览器。

## 验证

| 项 | 结果 |
|---|---|
| `ci-sign.sh` 回归 | 缺失配置/成功/公证失败/无身份 四路径通过（`--app` 夹具） |
| YAML | `release.yml` 可解析 |
| 现有门禁 | `make verify`、`make macos-offline-tests`、`macos-updater-tests` 通过 |

## 边界

- 尚未打新 tag，因此 Release 上还没有更新程序资产；下一次 Release（v0.1.1 候选）才会带上。
- 更新程序不自动启动、不做后台检查；用户需自行安装到 `/Applications`。
- App Store 渠道不打包更新程序（ADR-257）。
