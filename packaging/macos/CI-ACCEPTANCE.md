# macOS 自动验收出包

日常 PR 自动构建并上传 `Yinghuo-macos-review-<commit>` 审核包，不使用任何 Apple 凭据；该包未公证，只用于代码/源码复现审核，不安装系统输入法。

专用 `macOS Acceptance Package` 工作流在 main 推送或 Actions 手动运行时生成签名/公证验收包。它先执行完整验证、独立窗口冒烟和严格构建，再签名、API 公证、staple、Gatekeeper 校验、打包和离线重建。成功后在运行页面 Artifacts 下载 `Yinghuo-macos-acceptance-<commit>`，含 ZIP 与 SHA，保留30天。不会创建公开 GitHub Release，不会安装输入法。凭据步骤只允许 main，不对 PR/fork 运行。

## 一次配置

当前仓库保持 private，使用仓库 Settings → Secrets and variables → Actions 的 Repository secrets。GitHub Free 的私有仓库不能使用组织 Secrets；组织升级后可用同名组织凭据共享。配置如下：

| 名称 | 内容 |
|---|---|
| `APPLE_CERTIFICATE_P12_BASE64` | Developer ID Application 证书及对应私钥导出的 `.p12`，Base64 编码 |
| `APPLE_CERTIFICATE_P12_PASSWORD` | 导出 p12 时设置的密码 |
| `APPLE_ASC_API_KEY` | App Store Connect 团队 API 私钥 `.p8`，完整 PEM 文本或 Base64 编码均可 |
| `APPLE_ASC_API_KEY_ID` | API Key ID |
| `APPLE_ASC_ISSUER_ID` | 团队 Issuer ID |

同页 Variables 创建 `MACOS_SIGNING_IDENTITY`，填入实际证书完整名称，格式为 `Developer ID Application: <证书名称> (<Team ID>)`。

证书从本机“钥匙串访问 → 我的证书”导出：选择 Developer ID Application 及其私钥，导出为 p12 并设置密码。仅有 `.cer` 不足以签名；API 密钥也不能代替签名私钥。

团队 API 密钥从 App Store Connect → 用户与访问 → 集成 → App Store Connect API 创建，记录 Key ID/Issuer ID，下载 p8 并妥善保存。创建团队密钥需要相应管理权限。不要使用 App 专用密码。

在自己的终端对相应文件执行 `base64 -i /你的路径/文件.p12 | pbcopy` 或 `base64 -i /你的路径/文件.p8 | pbcopy`，将剪贴板内容直接粘贴到对应 Secret。不要提交文件/密码到仓库或聊天，也不要放进 GitHub Variables。

## 使用与限制

工作流合入 main 后，每次 main 更新会自动出包；也可在 Actions → macOS Acceptance Package → Run workflow 选择 main。无需维护本机 notarytool profile。runner 创建临时钥匙串并导入 p12，API 私钥仅存在 runner 临时目录，退出/失败 always 清理；仅上传候选 ZIP/SHA，不上传临时目录或整个工作空间。

Secrets 未配置时会明确报告缺失项；签名、公证或离线重建失败时不上传验收包。仓库凭据已完成实际签名、公证和离线复现验证；最近定稿候选为 main `6d7e8435`，运行 [37918189811](https://github.com/EasyIndie/EasyInputMethod/actions/runs/37918189811)。证书过期、API 密钥撤销、Apple 协议更新仍可能要求维护；正常迭代无需反复输入凭据。

此包提供真机验收材料，不代表正式 IMK 多应用、长时间稳定或动态零外联已通过。普通PR产物仍不可信安装。候选为 universal（arm64 + x86_64）；CI 先安装两个 rustup target 再以 `build.sh --universal` 构建。

参考：[Apple API 密钥](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api)、[Apple 公证认证](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool)、[GitHub runner 证书安装](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)。

下载并解压 Actions 附件后，进入包含候选 ZIP 的目录运行 `shasum -a 256 -c *.sha256`；校验文件采用相对文件名，不依赖 runner 路径。

签名前输出临时钥匙串的代码签名身份诊断，仅含公开证书名称/指纹和有效性错误，不导出私钥。若 p12 导入成功而身份找不到，先核对诊断中的有效期、信任链及签名策略结果。

CI 保留并临时扩展用户钥匙串搜索列表，按完整名称从有效身份中选取唯一证书指纹用于签名；退出时恢复原列表并删除临时钥匙串。
