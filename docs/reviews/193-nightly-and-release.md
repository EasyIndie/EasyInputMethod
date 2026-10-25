# 193 夜间回归接入与 0.1.13 发布材料

## 1. 夜间工作流（ADR-290）

`.github/workflows/macos-nightly.yml`：每日 18:00 UTC + 手动触发，`macos-latest`，90 分钟上限。

| 步骤 | 作用 |
|---|---|
| `make verify` | 仓库门禁（fmt/lint/test/deny/产物级网络断言） |
| `make macos-offline-tests` | 50 项离线回归（含本轮新增的卸载脚本 6 项） |
| `make macos-updater-tests` | 更新程序/安装器 XCTest |
| `make macos-probe-build` + 全部 `*.sh` 的 `bash -n` | 验收工具链自身不腐化 |
| 真实键入验收 | 先跑 `acceptance-preflight.sh`：退出码 **78 → SKIP**（runner 没装输入法/无图形会话），0 → 跑 `acceptance-auto`（`ROUNDS=10 SOAK_MINUTES=3`）并上传证据；其他码 → 判红 |

`acceptance-preflight.sh` 逐项检查：已装 `Lampyris.app`、宿主在跑、输入源 `Lampyris.default` 已启用、图形会话可取前台应用、探针已构建、测试 `.app` 已生成；输出 JSON（含执行 SHA），本地与 CI 共用。

## 2. 0.1.13 发布材料

`docs/releases/0.1.13.md`：

- 身份表：0.1.13 / build 21，main `2d9c509`，ZIP `f86959d6…`、源码 `c743feb4…`、执行 `a3faf05c…`。
- 相对 0.1.12 的用户可见改动（更新可靠性、目标目录语义、包体清理）。
- 已验证 / 未验证两栏，避免把报告186-192 的结论越界。
- 升级与回滚：配置/词库/输入源注册均保留；回滚重装 0.1.12。
- 8 步 checklist，其中两条最容易出错：**站点链接必须与发布同批**（提前改 404）、**tag 必须签名**（未签名会被 release 工作流拒绝）。

## 3. 首次运行就抓到两个真实问题

| 运行 | 结论 | 原因 |
|---|---|---|
| `40163323913` | FAIL | `test-ci-sign.py` 首个断言隐式依赖本机 `platforms/macos/build/Lampyris.app`，干净 runner 上先报「待签名 app 不存在」 |
| `40164071693` | FAIL | 同一文件里「成功」用例仍走默认 app 路径，补了 fixture 也不够 |
| `40164726091` | **PASS（4 分钟）** | 两处都改成显式 `--app <fixture>`，用例不再依赖构建产物 |

- 这正是夜间回归的价值：这两个用例在本机一直"绿"，因为它们撞上了本地已有的构建产物。

## 4. 夜间运行结果（main `9296fb5`）

| 步骤 | 结果 |
|---|---|
| Repository gates（`make verify`） | success |
| 离线/打包回归（50 项） | success |
| 更新程序与安装器 XCTest | success |
| 探针构建 + 全部 shell 语法 | success |
| 真实键入验收 | **跳过**：`{"ready":false,"checks":{"installed":"未安装输入法","host":"宿主未运行","input_source":"输入源未启用","gui_session":"ok",...}}` → `::notice` 说明原因，不上传证据，灯号仍为绿 |
| Summary | 写入 run summary（提交、验收状态、artifact 名） |

## 5. 状态

- `schedule`（每日 18:00 UTC）已随 main 生效；也可 `workflow_dispatch` 手动触发。
- 具备「已装输入法 + 输入源启用」的机器上，同一工作流会自动从跳过转为实跑并上传证据。
- 0.1.13 仍是候选：发布是独立授权动作（打 tag/发 Release/改站点），本报告不代替发布。
