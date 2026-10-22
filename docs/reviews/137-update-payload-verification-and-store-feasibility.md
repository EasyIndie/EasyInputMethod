# 137 更新负载验签与 App Store 可行性口径

## 一、更新负载 Ed25519 验签（ADR-256）

原型此前明确「元数据不可信，公钥/签名长度检查不等于验签」。本轮补上可离线回归的一环：

- `platforms/macos/Updater/Sources/WebsiteUpdateCheck/PayloadVerification.swift`
  - `PayloadVerifier(publicKeyBase64:)`：严格接受 32 字节 Curve25519 原始公钥；
  - `verify(payload:signatureBase64:)`：签名必须是 64 字节 Base64，校验对象是负载**原始字节**；
  - `verify(fileAt:signatureBase64:)`：读文件失败按「无效」返回，不向外泄露路径细节。
- `WebsiteUpdateCheck --verify-payload <文件> <签名Base64>`：只在签名包已配置网站渠道公钥时可用，缺公钥按 2 退出；**不联网、不下载、不安装**。
- 用 CryptoKit 系统框架，无新增第三方依赖；模块仍默认关闭、不随输入法包分发、不链接 Rust 核心。

验证：7 项 XCTest（正确签名 / 篡改负载 / 篡改签名 / 他人私钥 / 非法公钥 / 非法签名编码与长度 / 文件缺失），
`swift test`（`-warnings-as-errors -strict-concurrency=complete`）与 `python3 platforms/macos/Updater/build.py` 严格 release 构建通过。

**仍未完成**（不得宣称升级闭环）：正式 feed 与公钥、下载器、目标系统/架构筛选、payload 与 feed 的绑定、停宿主/原子替换/回滚、GUI 与用户偏好（只能走 `ime-config`）。

## 二、App Store 可行性口径（ADR-257）

Apple 明确 App Store 提交必须启用 App Sandbox（[Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)）。
对 IMK 输入法还有额外现实约束（社区 2026 规范整理，供工程核对，不当作 Apple 官方承诺）：

- 沙盒下 `InputMethodConnectionName` 必须遵循 `$(PRODUCT_BUNDLE_IDENTIFIER)_Connection` 命名，否则切源时可能无法加载；
- 需要为自身 UserDefaults/NSConnection 声明临时例外权限；本项目不用 `UserDefaults`，但配置根在沙盒中会落到容器路径，
  必须由 `ime-config` 明确支持并回归，否则「配置唯一」在商店版会与网站版不同；
- App Store 版不能自更新：`LampyrisUpdateCheck` 必须不打包、不启动，更新完全交给 App Store；签名/描述文件与 Developer ID 不同，公证不适用；
- 输入法安装位置与首次启用体验需实包验证，不能沿用网站渠道的安装/换包结论。

结论：**两条渠道互斥、PASS 不互相继承**；先做一份不发布的沙盒化开发构建，在 B 机验证配置根/输入源/学习数据，再决定是否投入商店工程。
在沙盒验证通过前，网站渠道 + 公证 + 独立更新程序仍是唯一候选路径。

## 三、边界

- 无 tag、无正式 Release；未请求真实 feed、未下载、未安装更新；未改动已装 build5 输入法。
- Rust 核心零网络与「默认关闭」边界不变；独立更新程序的联网能力仍只用于显式 `--check`（未来）。

## 证据

- 代码与测试见 `platforms/macos/Updater/Sources/WebsiteUpdateCheck/PayloadVerification.swift`、
  `Tests/WebsiteUpdateCheckTests/PayloadVerificationTests.swift`。
- 本地结果：`PayloadVerificationTests` 7/7、`ReleaseConfigurationTests` 8/8、`FeedBoundsTests` 2/2、`UpdateCheckTests` 7/7；
  `build.py` 输出 `Build complete!`。
