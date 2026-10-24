# 180 独立更新程序签名诊断附件：静态核验（未安装）

## 来源与权限边界

- ADR-286 / PR #144 在 head `861f95c79b567e011ff8ad935223a0b31d3741bc` 四 CI PASS 后，以 merge commit `73d468b6b3fea246704972e8327b9fd530c659d5` 合入 main；固定 dev 已快进同步。工作流仅 main 手动触发，未创建 tag/Release/appcast。
- `Update Signing Check` 手动 run **`40098104120`**，head `73d468b6b3fea246704972e8327b9fd530c659d5`，success：通用构建、Developer ID 签名与公证、入库公钥/私钥临时负载验签及篡改拒绝、诊断 ZIP 附件均 PASS。
- 下载到忽略目录 `platforms/macos/build/acceptance-180-updater/`；**未安装/注册程序、未请求真实 feed、未切输入源/发键或写真实配置与词库**。该附件保存 7 天，仅供诊断；不是网站 Release 或给用户升级的版本。

| 对象 | 实际结果 |
|---|---|
| Artifact | `Lampyris-updater-diagnostic-73d468b6b3fea246704972e8327b9fd530c659d5` |
| ZIP SHA-256 | `962e05c5fb5c7a949f278606829a4a3520d1123ae8483c29b53d053ea7a6c988`，随附 `.sha256` 校验 PASS |
| SOURCE-COMMIT | 附件内 `SOURCE-COMMIT.txt` = `73d468b6b3fea246704972e8327b9fd530c659d5` |
| 执行 SHA-256 | `0710987b30d430baf2faddd3af52349aec25ea9133f144e94011c0b14d419388` |
| 元数据 | `cn.jokerhub.Lampyris.WebsiteUpdateCheck`，0.1.12/build20，`x86_64 arm64`；`SUPublicEDKey` 与仓库公钥一致 |
| Apple 信任 | `codesign --verify --strict --deep`、`xcrun stapler validate`、`spctl --assess --type execute` 全 PASS（Notarized Developer ID） |

本地离线执行签名程序的**无参数路径**返回“默认关闭”，无请求；以该 ZIP 与非法签名调用 `--verify-payload` 返回 1，提示“不安装”。有效私钥签名与篡改拒绝由工作流内临时夹具完成；本机未获取私钥、未生成真实签名或安装产物。签名程序有显式网络能力，**不是输入宿主**，不应套用宿主零网络符号断言。

## 同一 main 提交的宿主附件（静态交叉核验）

main `73d468b6…` 的自动 `macOS Acceptance Package` run **`40098075131`** 也已 success；下载**但未安装**到 `platforms/macos/build/acceptance-180-host/`。ZIP `Lampyris-0.1.12-universal.zip` SHA `3b4fb9b97025d172f50abb4bbacf1faca31bb297d64b062b61e227c9c3a8decb`；对应源码 tarball SHA `5c8b8c84287863dca3995243739a5b1059e83c39ad66d062b9de51678c5ccf24`；宿主执行 SHA `867add9fd2ced6c4c1262fac102bfd6f543316101c05507c3865a4f4915b5433`。附件摘要 PASS，bundle 与源码 `SOURCE-COMMIT` 均为 `73d468b6b3fea246704972e8327b9fd530c659d5`；`x86_64 arm64`、Developer ID、公证、Gatekeeper PASS。两片均无 ADR-285 的已知网络导入且保留 IMK 控制器类符号。

因此**宿主与独立更新程序现可绑定同一源码提交**，但附件分属独立诊断与验收流程，并非一个已发布 DMG 或有效新版本；两者仍是与生产相同的 build20，未运行新宿主或更新 UI。静态 PASS 不继承为动态/安装/发布 PASS。

## 未完成 / 禁止误用

1. 该更新程序与已发布版本同为 build20，但执行 SHA 不同；**不能**覆盖 `~/Applications` 的正式已装更新程序，也不能冒充新版本发布或作为真实 feed 升级包。
2. 本轮只关闭“同 main 源码签名程序附件/双 SHA/签名公证/离线验签”的**静态与夹具门禁**；没有在新签名程序上点击 UI 下载/取消/失败/成功，没有实机安装/回滚/目录清理证据。已有 XCTest PASS 仍只证明离线行为。
3. 后续需先决定非生产身份、独立私有配置根/本地受控 feed 与版本隔离；若改变应用身份/测试协议，先写 ADR，再在安全自有夹具内复验。最终 RC 生产升级与动态零外联另按同候选验收，不能从这次诊断继承。
