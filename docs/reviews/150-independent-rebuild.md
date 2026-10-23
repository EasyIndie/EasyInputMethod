# 150 独立源码重建（v0.1.0）

## 方法

- 干净临时目录克隆 tag `v0.1.0`（提交 `26e3c07`），**不使用**现有工作树或构建缓存产物；
- 执行 `./platforms/macos/build.sh --strict --universal`（Rust 1.98.1、Xcode 27.0/27A266a、macOS 27.0.1）；
- 与 GitHub Release 的 `Lampyris-0.1.0-universal.zip` 对比数据文件、元数据、架构，并启动重建包。

## 结果

| 项 | 重建 | Release |
|---|---|---|
| 构建 | 成功（strict + universal） | — |
| 架构 | `x86_64 arm64` | `x86_64 arm64` |
| 版本/构建号 | 0.1.0 / 6 | 0.1.0 / 6 |
| 数据表 SHA | 4/4 与 Release 完全一致 | 同 |
| 可执行 SHA | `e59c05be…` | `5709716c…` |
| 启动 | 成功（PID 95727，随后精确停止） | 已公证安装 |

## 结论

- **第三方可从 tag 源码重建出可运行、数据一致的通用包**：数据文件逐字节相同、版本/构建号一致、架构一致。
- **未达到二进制逐字节可复现**：重建包是 ad-hoc 签名，Release 是 Developer ID + hardened runtime + 时间戳，
  Mach-O 内嵌签名块不同；CI 与本地 Xcode/SDK 版本也可能不同。因此不宣称 bit-reproducible。
- 若要追求逐字节复现，需要：固定同一 Xcode/SDK、比较**未签名**产物、以及确定性的签名/时间戳策略；这属于后续独立议题。

## 证据

`docs/reviews/150-rebuild-evidence/00-rebuild.txt`（工具链、SHA、数据对比、启动结果）。
