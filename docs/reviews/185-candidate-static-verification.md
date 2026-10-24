# 185 新候选包静态核验（main `167a644`）

## 1. 候选身份

| 项 | 值 |
|---|---|
| 来源提交 | main `167a64476d0d67210238438a3c722d738ac30a0c`（PR #154 合并，含 ADR-289 与 drill 修复） |
| 构建运行 | `macOS Acceptance Package` run `40141807115`（success） |
| 归档 ZIP SHA-256 | `430da00b5b65313d21f4b3b89721ab7718d2314401bb0764a909421b18c74f3d` |
| 源码 tar SHA-256 | `a76039623d79e773ec4168c6eb055e9585220eb4c02743100e54dfc8042ab5c4` |
| 执行文件 SHA-256 | `9c4d40f94567bdce9b29f5600c22a8d9275d3fcac920950437a4e6ce0ff75924` |
| 版本 / 构建号 | 0.1.12 / 20（与已装生产包同版本号，但执行 SHA 不同） |
| 已装生产包执行 SHA | `c09c2d11749dea9a4347930972817e5262e682c971653f0618c420e7ad9e77a3` |

- 两份 SHA 由 GitHub 产物自带 `.sha256` 校验通过（`shasum -a 256 -c`）。
- CI 侧 `run-repro.sh` 已用源码 tar 重建并与 ZIP 比对通过（同源可复现）。

## 2. 静态核验（本机执行）

| 检查 | 结果 |
|---|---|
| `codesign --verify --strict --deep` | 通过 |
| `stapler validate` | `The validate action worked!` |
| 架构 | `x86_64 arm64` |
| 逐架构 `nm -u` 网络导入（`_socket`/`_connect`/`_getaddrinfo`/`NSURLSession`） | 两片均 **0** |
| IMK 控制器类字符串 `LampyrisInputController` | 存在（4 处） |
| 隔离键（`LampyrisTestOnly`/隔离根/UUID 身份） | 无 |
| `scripts/verify-no-network.sh` | PASS（338 个产物；仅静态断言） |
| 归档内容 | `Lampyris.app` + `SBOM.cdx.json` + `DATA-SOURCES.md` + `data-sources.toml` + `SOURCE.txt` + 源码 tar |
| SOURCE.txt | GPL-3.0-or-later 第 6(d) 条声明，指向同位置源码 tar 与仓库 |

结论：该候选与 main `167a644` 绑定，静态门禁（签名、公证、可复现、零网络符号、身份非隔离）全部通过。

## 3. 与"已装生产包"的差异

- 版本号未变（0.1.12 / build 20），仅内部实现变化：更新下载临时目录所有权清理、首次安装回滚与 staging 预检、`-dead_strip` 与逐架构导入门禁、ADR-289 目标目录前置检查。
- 因此**不能**靠版本号区分两者，任何后续验收与回滚都必须以执行 SHA 为准。

## 4. 启动/idle 运行时观察（非完整动态验收）

- 从解压目录直接运行候选执行文件（未注册为输入法），持续 30 秒、6 次抽样 `lsof -nP -i`：**0 条 TCP/UDP**，进程存活。
- 期间真实配置 SHA `3bc1117c…` 与词库 SHA 前后一致，输入源条目数 10→10，未新增注册。
- 日志：`_IMKServerLegacy _createConnection` 无法注册 `cn.jokerhub.inputmethod.Lampyris_Connection` —— 属预期（生产宿主已占用该名称，本进程未作为已注册输入法启动）。
- 结论边界：这只覆盖「进程启动 + 空闲」路径，**不等于**真实输入时的动态零外联；键入路径仍须安装后验证。

## 5. 尚未做（需用户授权）

- 安装该候选并做动态验收（真实三模式、目标客户端、辅助功能/多屏/睡眠、宿主长期零外联、p95 与内存）。
- 安装会替换 `~/Library/Input Methods/Lampyris.app`（配置与词库不动）；回滚路径为重新安装 GitHub Releases 的 v0.1.12 DMG。
- 版本号/构建号是否在正式发布前递增，属发布决策，尚未动。
