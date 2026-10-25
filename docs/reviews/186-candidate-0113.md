# 186 正式候选 0.1.13 / build 21

## 1. 身份递增

| 项 | 旧 | 新 |
|---|---|---|
| `Cargo.toml` workspace version | 0.1.12 | **0.1.13** |
| `packaging/build-number` | 20 | **21** |

- 只改这两个受控输入（`tools/release_version.py` 读取），`Cargo.lock` 由 `cargo metadata` 刷新。
- 文档：`docs/更新发布流程.md` 新增「2.5 版本号与构建号递增」（含站点链接延后到正式发布、同号包以执行 SHA 区分、构建号不复用）。
- PR #155（head `72e5447`）四 CI PASS → main `2d9c509`。

## 2. 候选产物（`macOS Acceptance Package` run `40145382687`，success）

| 项 | 值 |
|---|---|
| 来源提交 | main `2d9c50983436e75a7f2b545ff242df8a86e40a47` |
| 版本 / 构建号 | **0.1.13 / 21** |
| ZIP SHA-256 | `f86959d6e670bed8f59edf3f999c1086c09737536fac92872e633bd61a5523d2` |
| 源码 tar SHA-256 | `c743feb4fba91446a10d9c93802235347c480e585095f3d7fe394463bd4f9a28` |
| 执行文件 SHA-256 | `a3faf05c66299992df642d1a47af31402fac9e2249c2317d9a9f04e191a441c4` |
| 标识 / 团队 | `cn.jokerhub.inputmethod.Lampyris` / `2N62934Y28` |

- 自带 `.sha256` 校验通过；CI `run-repro.sh` 用源码 tar 重建比对通过。

## 3. 静态核验

| 检查 | 结果 |
|---|---|
| `codesign --verify --strict --deep` | 通过 |
| `stapler validate` | `The validate action worked!` |
| 架构 | `x86_64 arm64` |
| 逐架构 `nm -u` 网络导入（`_socket`/`_connect`/`_getaddrinfo`） | 两片均 **0** |
| `LampyrisInputController` | 两片均存在（2 处） |
| 隔离键（`LampyrisTestOnly`/隔离身份） | 无 |
| `scripts/verify-no-network.sh` | PASS（422 个产物，静态断言） |

## 4. 启动/idle 运行时抽样（非完整动态验收）

- 从解压目录直接运行候选执行文件（未注册），30 秒内 6 次 `lsof -nP -i` 抽样：**0 条 TCP/UDP**，进程存活。
- 真实 `config.toml` SHA 前后一致、输入源条目 10→10 未变。
- 边界：只覆盖「启动 + 空闲」，键入路径与外联需装机后验证。

## 5. 与已发布版的关系

- 已发布 v0.1.12 / build 20（执行 `c09c2d11…`）仍是生产安装；本候选尚未安装。
- 站点 `site/index.html` 仍指向 `Lampyris-0.1.12-universal.dmg`；按流程在**正式发布 0.1.13 时**才更新链接与文案（ROADMAP 已记）。
- 未创建 tag/Release，未改 appcast。

## 6. 下一步（需用户授权）

安装本候选替换 `~/Library/Input Methods/Lampyris.app`（配置/词库不动，回滚为重装 v0.1.12 DMG），然后执行最终 RC 动态矩阵：三模式与实际客户端、辅助功能/多屏/睡眠、键入期零外联、p95<16ms、稳态 ≤30MiB、升级与卸载。
