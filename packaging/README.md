# 发布工程

macOS 首个候选：`macos/prepare.sh` 本地准备，`macos/sign.sh` 显式签名/公证，应用安装卸载脚本位于 platforms/macos。正式分发须 Developer ID + hardened runtime + 公证（ADR-032），默认开发使用独立窗口。

```sh
make verify                            # 完整审计通过后保存提交
./packaging/macos/prepare.sh             # clean git 源码、本地 ad-hoc 审核包
./packaging/macos/sign.sh --sign 'Developer ID Application: …'
./packaging/macos/sign.sh --submit '<钥匙串凭据名>' # 明确上传 Apple
./packaging/macos/prepare.sh --signed    # 不重建已公证应用，检查同一源码提交
```

候选生成在 packaging/out/ 唯一目录，保留旧包，**产出两份产物**：

- `Lampyris-0.1.0-<arch>.zip`（二进制安装包，**不含源码**）+ `.sha256`；内含 `LICENSE`、`SOURCE.txt`（指向下方源码包）、依赖许可、数据许可/出处、CycloneDX SBOM、`cargo-tree.txt`、`BUILD-INFO.txt`、`SHA256SUMS`。
- `Lampyris-0.1.0-source.tar.gz`（**对应源码**：`git archive` 全源码 + `cargo vendor` 锁定依赖）+ `.sha256`；与二进制**同处发布**（GPL-3.0 §6(d)，ADR-064）。

包须 ≤15MB；不携带用户配置词库，不自动安装、不上传凭据。发布时须把两份产物放在**同一位置**，源码方可公开获取（仓库可保持 private）。

验收门槛见 docs/技术方案.md §12，未满足前只称候选包。第三方复现说明及终端安装/卸载命令随包 README 提供。Windows/Linux/移动端打包尚未开始。

同环境离线载荷复现：`./platforms/macos/tests/run-repro.sh <候选ZIP>`，在临时目录核验二进制包 SHA/软链及**同目录源码包**的 SHA 后，从源码包 vendor 离线构建；去签名可执行文件及默认词表须逐字节一致，不安装应用。正式构建通过 ADR-033 归一化编译路径和目标版本；需要相同架构、Rust、Swift/SDK 与编译选项。

自动验收出包采用 GitHub Actions + App Store Connect 团队 API 密钥，凭据一次配置后由 CI 签名/公证/上传附件，见 [CI-ACCEPTANCE.md](macos/CI-ACCEPTANCE.md)。普通 PR 自动提供无凭据审核包。
