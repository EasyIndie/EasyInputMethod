# 网站版独立更新检查（ADR-239/248）

这是开发接入阶段的独立程序，不进入输入法宿主或默认发行包，不安装后台服务。没有配置正式发布地址和公钥时保持关闭；不是自动更新或一键安装的完成品。

## 构建与检查

- `make macos-updater-tests`：仅离线解析/安全回归。
- `make macos-updater-build`：构建默认关闭的程序。
- 产物：`platforms/macos/build/website-updater/LampyrisUpdateCheck.app/Contents/MacOS/LampyrisUpdateCheck`。
- 不带参数只说明关闭状态；显式`--check`才可能联网。缺少合法签名包元数据会以2退出，不创建请求。

正式发布配置由构建提供：`python3 platforms/macos/Updater/build.py --feed-url <HTTPS地址> --public-key <32字节Ed25519公钥的Base64> --build <数字构建号>`。这些是签名产物元数据，不是用户偏好；不得填写示例地址冒充生产。需要Developer ID签名/公证和发布包流程接入后才能分发，目前脚本只构建、不安装、不签名。

## 依赖与隐私

`Vendor/PROVENANCE.json`固定OrzAppUpdater无状态适配提交和源码/许可/测试SHA，保留Apache-2.0许可。基础源码来自固定上游；本轮为两个不可变值类型添加编译器检查的Sendable，PROVENANCE.json分别保留上游和本地摘要，verify-vendor.py反向移除这两行补丁后校验固定上游一致；未使用@unchecked。为避免构建时解析旧Sparkle依赖，采用本地Swift target，不引入Sparkle.framework。后续同步需更新来源与摘要。现有Sparkle控制器不使用、不实例化。

显式检查仅使用无缓存/凭据/cookie存储的临时HTTPS会话，无UserDefaults、检查时间记录、设备标识或遥测；不读输入缓冲、词库和真实配置。服务器仍会看到正常HTTP连接信息（例如IP），因此不能把启用后的独立检查程序宣传为零网络。输入引擎与IMK仍离线。

## 当前边界与下一步

只支持UTF-8、数字点分构建号、每项一个完整下载包的Sparkle RSS appcast子集。解析签名格式不等于验证包签名；返回版本元数据不可信，程序不下载或执行payload。尚未实现系统版本/架构/频道筛选、签名包验证、下载进度、IME结束组合/退出/重载、备份回退、GUI入口、可选后台检查、App Store构建及双渠道切换。禁止调用现有持久化Sparkle控制器来绕过这些边界。

下一小步：配置正式feed和密钥后，先对签名测试包实现下载验证及目标版本/架构筛选，再连接已验证的固定身份退出/换包流程；只在可恢复测试环境验收。任何用户偏好只能经ime-config新增Schema；不在本模块另存配置。

本轮恢复原型源码进入main不代表启用。严格并发/边界回归纳入CI，构建显示版本由Cargo workspace.package.version派生；默认构建号1仅为未发行原型占位，不替代ADR-240全局发行构建号分配。正式feed/公钥尚未提供，不以example.test测试样例启用请求。
