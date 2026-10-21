# 隔离输入法公证对照（设备绑定）

在 main 手动运行 Isolated IMK Notarization，填写两项：

| 输入 | 含义 |
|---|---|
| `target_root` | 接收设备上**已存在**的独有私有临时根绝对路径（`lampyris-imk-<UUID>`，0700 + `owner` 文件） |
| `arch` | 载荷架构：`arm64`（默认）、`x86_64` 或 `universal`；在 arm64 runner 上交叉构建 |

目标根必须是接收设备**系统临时目录**里的路径：`/private/var/folders/<A>/<B>/T/…` 或
`/private/tmp`、`/tmp`、`/private/var/tmp`、`/var/tmp` 的直接子目录。不得填真实 Lampyris 数据目录、
用户文档或其它非临时路径；相对路径、`..` 穿越、非 UUID 后缀、非规范化路径同样拒绝。

仅 main 触发、复用现有 Apple 凭据、所有 Actions 固定 commit；非 main 不会使用凭据。
附件保留 7 天，无 Release、无安装操作。

## 构建与签名约束

- 载荷按 `arch` 构建：`arm64`/`x86_64` 为单架构切片，`universal` 用 `lipo` 合并两片；
  Rust 侧用 `--target` 交叉编译 staticlib，Swift 侧显式 `-target <arch>-apple-macosx13.0`。
- runner 先在自己的同 UUID 临时根构建并跑 `--isolation-probe normal`；
  **签名前**再把 `IMKTestRoot` 重绑到 `target_root`，此后**不在 runner 上执行**该包。
- 架构、绑定与 commit 由 `TARGET-ARCH.txt` / `TARGET-ROOT.txt` / `SOURCE-COMMIT.txt` 记录，
  流水线在签名前用 `lipo -archs` 与 PlistBuddy 复核。

## 下载后核对

核对 ZIP 摘要、`SOURCE-COMMIT.txt`、`TARGET-ARCH.txt`、`TARGET-ROOT.txt`，确认本机根位于本机系统临时目录、
UUID/所有权/0700 权限及 `owner` 文件正确，再用 `ditto` 解压，核对签名、staple 和 Gatekeeper。
外层包名称 `Lampyris.app` 仅用于复用 CI 签名脚本，内部仍为独有测试身份；放入根内时重命名为
`LampyrisIMKTest.app`。**不修改** `IMKTestRoot` 或其他签名资源。注册/启动/选择须另按安全协议验收，
不能以公证成功代替。

设备绑定导致该包只允许在声明根所在的设备上运行；换设备或换根必须重新出包。

## 固定开发身份（ADR-230）

工作流development默认false，既有临时根候选不变。仅显式true允许 `/Users/<user>/Library/Application Support/LampyrisIMKDev/lampyris-imk-<UUID>`，同一设备重复构建复用同根；签名前写入开发标记和源码提交，标签为“萤火虫开发 <UUID前8位>”。宿主验证当前用户专用父目录的所有权/权限，拒绝生产根及重定向。使用[报告106](../../docs/reviews/106-stable-imk-development.md)的初始化与安装入口；该可变身份不用于正式RC。
