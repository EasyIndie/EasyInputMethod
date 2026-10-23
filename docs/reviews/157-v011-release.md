# 157 v0.1.1 发布（含更新程序资产）

## 发布内容

| 资产 | 说明 |
|---|---|
| `Lampyris-0.1.1-universal.zip` | 5,230,874 B；build 9；universal；已签名/公证 |
| `Lampyris-0.1.1-source.tar.gz` | GPL §6(d) 对应源码 |
| `LampyrisUpdateCheck-0.1.1.zip` | **已签名/公证的更新程序**（arm64，bundle `…WebsiteUpdateCheck`，build 9） |
| `appcast.xml` | `sparkle:version=9`、length 5230874、Ed25519 签名 |

- 默认更新源：`releases/latest/download/appcast.xml` 已指向 v0.1.1。
- 发布过程修复了两处流水线问题：`$signers）` 全角括号被 bash 当成变量名；新 job 引用了不存在的 `APPLE_ASC_API_ISSUER_ID`（应为 `APPLE_ASC_ISSUER_ID`）。

## 更新程序核验

- `codesign --deep --strict` 通过、`stapler validate` 通过、`spctl` = Notarized Developer ID（Team 2N62934Y28）；
- `SUPublicEDKey` 与仓库 `packaging/macos/update-public-key.txt` 一致；
- 已安装到 `~/Applications/Lampyris Update.app`（用户级，不需要管理员）。

## 当前机器状态

- 生产输入法：build8（`3c9c199f…`），菜单已含「检查更新…」；
- 更新程序已安装，菜单点击应直接打开更新窗口（此前未安装时会打开 Releases 页面）；
- 输入源为生产源；开发包仍为 build7；
- 未改动配置/词库。

## 待验证

- 菜单点击「检查更新…」→ 更新窗口的实际交互（需用户点击确认）；
- 跨版本升级（build8 → build9）与镜像回退 UI；
- 完整 RC 矩阵。

## 证据

`docs/reviews/157-v011-release-evidence/00-release.txt`。
