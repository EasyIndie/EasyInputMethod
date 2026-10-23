# 161 v0.1.3：简化安装/卸载随包 helper 上线

## 发布

| 资产 | 说明 |
|---|---|
| `Lampyris-0.1.3-universal.zip` | build 11；**内含 `Contents/Helpers/LampyrisTIS`**；已签名/公证 |
| `LampyrisUpdateCheck-0.1.3.zip` | 更新程序 build 11（静态链接） |
| `appcast.xml` | `sparkle:version=11` |

修复：签名顺序必须先 helper 后 app，否则外层签名封印被破坏、公证失败（已在验收流水线验证通过）。

## 实机验证

- 解包后 ZIP 内 helper 存在，`codesign --deep --strict`、`stapler validate`、`spctl` 均通过；
- 用 ZIP 内 `scripts/install.sh` 覆盖本机生产包：
  - 输出「安装完成，已自动注册到输入源。现在用 ⌃Space 或输入法菜单选中…」；
  - 未改变当前输入源（仍为 Sogou），说明安装不会擅自抢源；
- 安装后：0.1.3/build11（执行 `d489dd79…`，universal、公证），helper 位于 app 内；
- 配置 `809e2cae…`、词库 `f3e2eef…`（69 行）与安装前一致；旧 build10 备份在 `updates/build11-backup/`。

## 现在的安装/卸载

- 安装：一条命令 → 自动注册+启用 → 用 ⌃Space/菜单选中一次（macOS 不允许程序代选第三方输入法）；
- 卸载：一条命令 → 自动切 ABC、禁用输入源、备份并移除应用；配置/词库默认保留；
- helper 缺失或失败时仍回退到原手动说明。

## 边界

- 输入源菜单显示名/首装条目在个别系统上仍可能需要一次重新登录刷新（系统缓存）；
- 系统域（`/Library/Input Methods`）仍需要管理员；
- 未在本机实际执行“卸载→重装”完整链路（会移除用户输入源），仅通过 helper 实测与脚本回归覆盖。

## 证据

`docs/reviews/161-v013-evidence/00-install.txt`。
