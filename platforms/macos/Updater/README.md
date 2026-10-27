# 网站版独立更新检查程序（ADR-239/248/294/295）

这是与输入法宿主完全分离的独立程序（不链接宿主、不共享进程、不进入宿主的零网络边界），**自 ADR-295 起随 DMG 分发**：安装器把它装到 `~/Applications/LampyrisUpdateCheck.app`，宿主菜单按 bundle id 定位它（ADR-294）。它不安装后台服务、不建登录项、不做启动时自动检查；没有配置正式发布地址和公钥时保持关闭。不是静默/全自动更新：发现新版本后仍需用户在窗口里确认。

## 构建与检查

- `make macos-updater-tests`：仅离线解析/安全回归。
- `make macos-updater-build`：构建默认关闭的程序。
- 产物：`platforms/macos/build/website-updater/LampyrisUpdateCheck.app/Contents/MacOS/LampyrisUpdateCheck`。
- 不带参数只说明关闭状态；显式`--check`才可能联网。缺少合法签名包元数据会以2退出，不创建请求。

正式发布配置由构建提供：`python3 platforms/macos/Updater/build.py --feed-url <HTTPS地址> --public-key <32字节Ed25519公钥的Base64>`。这些是签名产物元数据，不是用户偏好；不得填写示例地址冒充生产。需要Developer ID签名/公证和发布包流程接入后才能分发，目前脚本只构建、不安装、不签名。

## 依赖与隐私

`Vendor/PROVENANCE.json`固定OrzAppUpdater无状态适配提交和源码/许可/测试SHA，保留Apache-2.0许可。基础源码来自固定上游；本轮为两个不可变值类型添加编译器检查的Sendable，PROVENANCE.json分别保留上游和本地摘要，verify-vendor.py反向移除这两行补丁后校验固定上游一致；未使用@unchecked。为避免构建时解析旧Sparkle依赖，采用本地Swift target，不引入Sparkle.framework。后续同步需更新来源与摘要。现有Sparkle控制器不使用、不实例化。

显式检查仅使用无缓存/凭据/cookie存储的临时HTTPS会话，无UserDefaults、检查时间记录、设备标识或遥测；不读输入缓冲、词库和真实配置。服务器仍会看到正常HTTP连接信息（例如IP），因此不能把启用后的独立检查程序宣传为零网络。输入引擎与IMK仍离线。

## 当前边界与下一步

只支持UTF-8、数字点分构建号、每项一个完整下载包的Sparkle RSS appcast子集。解析成功≠可安装：下载包必须通过 Ed25519 验签（ADR-256），候选还要过 codesign/Developer ID/hardened runtime/公证/Gatekeeper 校验（ADR-259/295），失败回滚并保留备份。已实现：`--check`、`--ui`（检查→进度→验签→确认→安装→结果）、`--verify-payload`、多源/镜像回退（ADR-270/264）、备份与回滚、0600 receipt。**不做**：增量更新、静默/后台自动更新、灰度与回滚策略、系统版本/架构筛选、App Store 构建。禁止调用现有持久化Sparkle控制器来绕过这些边界。

安装实现：替换/备份/回滚/验签与**自更新**（用负载自带的 `LampyrisUpdateCheck.app` 替换 `~/Applications` 里的本体，下次打开生效）都在共享库 `platforms/macos/InstallCore`（ADR-295），DMG 安装器也是它的调用方；本模块不再自带第二份实现。隔离 drill 构建不碰真实 `~/Applications`。任何用户偏好只能经ime-config新增Schema；不在本模块另存配置。

本轮恢复原型源码进入main不代表启用。严格并发/边界回归纳入CI，构建显示版本由Cargo workspace.package.version派生；默认构建号1仅为未发行原型占位，不替代ADR-240全局发行构建号分配。正式feed/公钥尚未提供，不以example.test测试样例启用请求。

版本由Cargo workspace派生，独立构建号只取`packaging/build-number`，与宿主共用；不再接受单独`--build`覆盖。每个新分发候选先递增构建号，同源码的双渠道及重建复用同号（ADR-249）。
