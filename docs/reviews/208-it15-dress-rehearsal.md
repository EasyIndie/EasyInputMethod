# 208 IT-15 预演：0.1.14/build 23 源码包离线重建与核验

> **性质**：这是**预演**，不是 IT-15 的正式结果。按 `docs/MVP单人验收清单.md` §独立核验 与 ADR-125，
> 独立核验必须由用户本人执行、代理在本机跑的重建**不能算作独立结果**（`docs/reviews/038` 同款约束）。
> 本报告只记录「这条流程在本机能不能走通、会卡在哪、需要什么环境」，供正式执行时照抄。

## 1. 结论摘要

| 步骤 | 结果 |
|---|---|
| 身份链（摘要/版本/提交对应） | ✅ 全部对齐 |
| 独立目录离线重建（源码包 → 宿主） | ✅ 成功（两次：本机架构 + universal） |
| 预期载荷比对（未签名可执行文件） | ❌ **本机不可字节一致**：CI 用 macOS 26.6.2 / SDK 26.5 / Swift 6.3.3，本机 macOS 13.7.8 / SDK 13.3 / Swift 5.8.1 |
| 默认数据比对 | ✅ 4/4 逐字节一致 |
| 静态零网络断言（重建产物） | ✅ PASS |
| 运行时零外联（已装包） | ✅ 空闲 30s 与键入期各 0 条 TCP/UDP |

**一句话**：IT-15 的流程在本机跑得通，但**「逐字节一致」这一步必须在与发布构建同 SDK 的机器上做**；
否则能给出的结论只有「身份+数据+静态+运行时」四项一致，加上「可执行文件因工具链不同而不同」的明确说明。

## 2. 身份链（本机可完整核验）

| 项 | 值 |
|---|---|
| 候选 ZIP | `Lampyris-0.1.14-universal.zip`，SHA-256 `7741cdde…e02d`（= 资产 `.sha256`） |
| 源码包 | `Lampyris-0.1.14-source.tar.gz`，SHA-256 `964f32f1…cb3c8`（= 资产 `.sha256`） |
| `SOURCE-COMMIT` | `0b2aa244f536fe9db9f4c76221a4d294fbe0e627`（= 候选构建的 main 提交） |
| 版本 / 构建号 | `Cargo.toml` 0.1.14、`packaging/build-number` 23（与 `BUILD-INFO.txt` 一致） |
| 锁定 | `Cargo.lock` + `vendor/`（10 个 crate，`.cargo/config.toml` 用 `replace-with = "vendored-sources"`）、`rust-toolchain.toml` 固定 1.98.1 |
| 候选执行 SHA | `a165f05c…e4dc`（装机版同值） |

## 3. 离线重建（在仓库之外的新目录）

源码包解压到 `/tmp/it15-rebuild/Lampyris-0.1.14-source`（47MB），全程 `CARGO_NET_OFFLINE=true`：

| 步骤 | 命令 | 结果 |
|---|---|---|
| Rust 库 | `cargo build --locked --offline --release -p ime-ffi` | rc=0，29.6s，日志中 `downloading/updating crates.io/fetch` **0 行** |
| 宿主（本机架构） | `./platforms/macos/build.sh --strict` | rc=0，产物 `0.1.14/build 23`，`lipo -archs = x86_64` |
| 宿主（通用） | `./platforms/macos/build.sh --strict --universal` | rc=0，`lipo -archs = x86_64 arm64`，逐架构网络导入检查通过 |
| 项目自带复现脚本 | `./platforms/macos/tests/run-repro.sh <候选 ZIP>` | 校验和/软链检查通过，重建成功，**`cmp` 在可执行文件上失败**（见 §4） |

## 4. 载荷比对：为什么会不一致（这是本报告最重要的发现）

`run-repro.sh` 在去签名后的可执行文件上 `cmp` 失败（`differ: char 23`）。逐架构切片比对：

| 切片 | 重建大小 | 候选大小 | 结果 |
|---|---|---|---|
| x86_64 | 2,716,048 | 2,722,064 | DIFF |
| arm64 | 2,663,888 | 2,720,064 | DIFF |
| 数据 `wubi86-core.tsv` / `pinyin-chars.tsv` / `pinyin-core.tsv` / `variant-s2t.tsv` | — | — | **4/4 SAME** |

`otool -l` 对比（x86_64 切片）：

| 项 | 本机重建 | CI 候选 |
|---|---|---|
| `sdk`（`LC_BUILD_VERSION`） | **13.3** | **26.5** |
| 链接器 | ld64-857.1 | ld 1267.0 |
| AppKit | 228.0.0 | 2685.60.104 |
| `LC_UUID` | 不同（每次构建都不同） | 不同 |

`BUILD-INFO.txt` 里候选的构建环境是 `macOS 26.6.2 / SDK 26.5 / Swift 6.3.3`；本机是
`macOS 13.7.8 / SDK 13.3 / Swift 5.8.1`。ADR-033 早已把复现边界写成「**同工具链/SDK/架构**下比较未签名载荷」，
签名/公证/ZIP 元数据不承诺一致——本预演正是这条边界的实证：**工具链不同，字节必然不同**，与源码是否对应无关。

## 5. 静态与运行时零外联

| 项 | 命令/场景 | 结果 |
|---|---|---|
| 静态断言（重建产物） | `./scripts/verify-no-network.sh`（源码树内） | ✅ 12 个产物，网络符号/导入检查通过 |
| 运行时（已装 build 23） | 空闲 30 秒，抽样 30 次 `lsof -nP` | `max_connections = 0` |
| 运行时（已装 build 23） | 测试窗口键入 `wq ` + `nihao `，抽样 12 次 | `max_connections = 0` |

## 6. 正式执行 IT-15 时的建议流程（照抄即可）

1. **换一台与发布构建同 SDK 的机器**（当前候选是 macOS 26 + Xcode 26），或由发布者提供一份由该环境重建的对照产物；否则只能给出 §4 那种「工具链不同」的说明，无法给出「逐字节一致」。
2. 全新目录解压源码包（不要在仓库工作树里构建），先核对 §2 的身份链，再 `CARGO_NET_OFFLINE=true` 构建。
3. 用 `./platforms/macos/tests/run-repro.sh <候选 ZIP>` 一次跑完校验和 → 重建 → 去签名 `cmp` → 数据 `cmp`。
4. 记录 `10-env.txt` 那类环境信息（macOS/SDK/Swift/ld/rustc），这是判定「能不能逐字节比」的前提。
5. 运行时零外联用**已装的产品包**做（重建包是 ad-hoc 签名，不建议装进输入法槽位），记录宿主 PID、场景与采样次数。
6. 结果填 schema 2 报告，并让发布说明/安装说明绑定同一最终包。

## 7. 证据文件（本机 `/tmp/it15-rebuild/`）

`01-rust.log`、`02-swift.log`、`04-run-repro.log`、`05-universal.log`、`06-payload.txt`、
`07-no-network.log`、`08-runtime-idle.txt`、`09-runtime-typing.txt`、`10-env.txt`、`cmp/`（切片与去签名副本）。
