# 发布工程

macOS 首个候选：`macos/prepare.sh` 本地准备，`macos/sign.sh` 显式签名/公证，应用安装卸载脚本位于 platforms/macos。正式分发须 Developer ID + hardened runtime + 公证（ADR-032），默认开发使用独立窗口。

```sh
make verify                            # 完整审计通过后保存提交
./packaging/macos/prepare.sh             # clean git 源码、本地 ad-hoc 审核包
./packaging/macos/sign.sh --sign 'Developer ID Application: …'
./packaging/macos/sign.sh --submit '<钥匙串凭据名>' # 明确上传 Apple
./packaging/macos/prepare.sh --signed    # 不重建已公证应用，检查同一源码提交
```

候选生成在 packaging/out/ 唯一目录，保留旧包。附件：完整 SOURCE（含 vendor）、GPL LICENSE、依赖许可、数据许可/出处、CycloneDX SBOM、cargo tree、主机与工具链信息、文件及 ZIP 的 SHA-256。包须 ≤15MB；不携带用户配置词库，不自动安装、不上传凭据。

验收门槛见 docs/技术方案.md §12，未满足前只称候选包。第三方复现说明及终端安装/卸载命令随包 README 提供。Windows/Linux/移动端打包尚未开始。
