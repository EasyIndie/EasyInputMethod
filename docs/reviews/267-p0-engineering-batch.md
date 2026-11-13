# 267 — P0 工程项收口（安装器测试、离线提速、私有数据根、高亮取字、CI 运行机）

2026-11-13，air（arm64 / macOS 27.2）。承接 1.3.0 发布前的工程项（P0-2、P0-3）与 ADR-339/340。
本轮**没有换包**；所有真机行为留待下一次候选装机复验。

## 1. 本轮完成

| 项 | 改动 | 证据 |
|---|---|---|
| P0-2 安装器新分支回归 | `test-install.py` 新增 `InstallerBranches` 4 例：同版本跳过 / 强制覆盖、宿主运行中拒绝覆盖、旧宿主重启只在显式请求时发生、输入源未被接受时只在显式请求时打开设置页 | 临时 HOME + `codesign/xcrun/spctl/pgrep/open` 桩；15 例 PASS（13.1s），不碰真实目录/进程/系统设置 |
| P0-3 离线回归提速 | 所有测试共用 `platforms/macos/build/swift-module-cache`（`clang` 缓存自带锁），并发 4→6；探针编译超时 180s→90s | 冷缓存跑 62 文件 / 332 例 **35.1s**（串行 176.0s），最慢单文件 20.7s |
| 延迟脚本失焦崩溃 | `perf-session.sh` 对非 JSON 的轮次（`type-session` 输出 `BLOCKED …`）不再 `json.load` 抛异常；记入 `unreadable_rounds` 跳过，仍有有效样本时照常判定 | 用伪造的「1 条有效 + 1 条失焦 + 1 条未接 IME」轮次复跑汇总，输出判定而非崩溃 |
| 真机样本私有数据根 | `quality-samples.sh` 默认 `ISOLATE=1`：`$OUT/support` 为私有根，`launchctl setenv LAMPYRIS_SUPPORT_DIR`、重启宿主、`ps eww` 回读；`config.toml`/`weak-chars.tsv` 跟随私有根；trap 还原环境变量并重启（ADR-340） | `sh -n` 通过；**未在真机执行**（需重启宿主，待授权） |
| CI 运行机可选 | `macos-acceptance.yml`、`release.yml` 的 `workflow_dispatch` 新增 `runner` 输入，默认 `macos-latest`；push/tag 触发不变 | 避免发版当天分不到 macOS 运行机再次排队被取消 |
| 以词定字跟随高亮 | `Session` 增加高亮下标；`[` / `]` 从高亮候选取首/末字，越界退回首选，单字候选退回标点；新增 FFI `ime_session_set_highlight`，宿主每次喂键前传入候选窗高亮（ADR-339） | `ime-core` 单测覆盖 1/2/99 下标与单字候选；`cargo test -p ime-core -p ime-ffi` 通过 |

## 2. 验证

| 命令 | 结果 |
|---|---|
| `cargo test -p ime-core -p ime-ffi` | PASS |
| `make verify` | PASS（373 个产物零网络符号） |
| `./platforms/macos/build.sh --strict` | PASS（arm64 宿主 + 输入源 helper） |
| `python3 -I platforms/macos/tests/test-install.py` | 15 例 PASS |
| `python3 -I platforms/macos/tests/run-offline-tests.py` | 62 文件 / 332 例 PASS，6 并发 35.1s |

## 3. 未完成 / 待真机复验

- **私有数据根**：脚本已接线，但没有在真机上跑过；下一次换包后先看 `ps eww` 是否带 `LAMPYRIS_SUPPORT_DIR`，
  再核对真实 `config.toml` / `user-dictionary.tsv` SHA 不变。
- **以词定字跟随高亮**：只有单测与编译证据；换包后需实键：`nihao` → 方向键移到第二候选 → `[` / `]`。
- 设置页新开关的版式与键盘可达性、练习错题加权外观、安装完成页、DMG 完成页仍未目视。
- Safari / Chrome 自动回读（本轮 8 项里的「尝试项」）未做，仍靠人工补。

## 4. 结论

P0 的两项工程欠账（安装器分支测试、离线回归提速）已关闭；真机样本不再写用户数据、以词定字按高亮取字、
CI 运行机可切换三项已实现并通过本地检查，**真机行为待下一候选统一复验**。
