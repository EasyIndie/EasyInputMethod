# 110 — OrzAppUpdater无状态网站更新检查接入

2026-10-21，B arm64/macOS27；main594c8c6基础，ADR-239、T-ITER-13。用户指定使用OrzAppUpdater，确认尚无正式feed/公钥、保持默认关闭及配置唯一。

## 已完成

- 审阅OrzAppUpdater b23e0c4源码与Apache-2.0全文：原库是Sparkle控制器typealias/SwiftUI菜单及Info.plist诊断，不提供IME退出/重载或无状态偏好接口。默认startingUpdater=true；Sparkle会持久化检查时间等，不能直接接到本项目。
- 在指定库新增独立OrzAppUpdaterCore；上游适配PR https://github.com/OrzGeeker/OrzAppUpdater/pull/1 ，固定适配提交8d1d4b8。原控制器不变。本仓库逐字镜像新增模块/测试及许可，PROVENANCE记录源提交与SHA，构建不解析或链接Sparkle。独立目标不是复制另一套配置。
- 无状态HTTPS检查：仅显式调用，临时会话无缓存/持久cookie/凭据，拒绝HTTP和跨源重定向，最多1MiB UTF-8 XML，禁DTD/实体，限制深度/项数，数字构建号选择更高版本。返回版本提示不等于包验证通过；不下载/安装payload。
- 独立网站检查程序以签名包构建元数据读取渠道/feed/Ed25519公钥/构建号；App Store/开发渠道、缺失/无效配置拒绝请求。不带参数不检查；显式--check才进入配置守卫。当前配置缺失，退出2且没有创建请求。
- make macos-updater-tests/build及CI入口；来源摘要校验、许可随独立构建附件保留。输入法、预览和Rust核心均不链接此目标；不安装后台任务，不修改配置Schema。

## 验证与限制

离线5个XCTest通过：库4组覆盖版本/降级、地址/密钥/构建号、恶意/超大XML、重定向；消费方1组覆盖渠道/缺失发布参数。重定向测试只构造未resume的任务，不发请求。Swift构建/test以warnings-as-errors执行；release构建及默认/--check缺失配置冒烟通过；机器证据见[110-website-update-check-evidence.json](110-website-update-check-evidence.json)。日志/private/tmp/lampyris-239-{final-test,final-build,verify}.log。原有make verify全绿，核心网络门禁扫描200项通过；与独立更新目标分别验证，不能把Rust扫描称为此联网程序零网络证明。

构建过程中修复过FoundationXML在Apple SDK导入错误；最终构建零诊断。测试只覆盖新模块及精确镜像，未重建上游旧Sparkle控制器完整依赖图。正式feed/公钥未知，没有线上检查、下载包签名、更新安装、网络抓包、升级/回退或App Store通过结论。独立产物仅本地构建、未签名安装，不进入正式发行包。

## 后续最小步骤

先审阅两个PR，不自动合并；配置正式HTTPS appcast和Ed25519密钥后，增加系统/架构/频道筛选、下载签名验证，再衔接受保护IME退出/替换/恢复和GUI入口。后台检查如需用户偏好必须走ime-config，不能启用现有Sparkle控制器的UserDefaults代替。保持现有手工升级作为稳定路径。

输入体验修复#63与原生验收记录#62仍独立在审，不被此更新工作替代；双高亮修复未装入当前594c8c6开发包。用户手工TextEdit窗口1902保持原状。
