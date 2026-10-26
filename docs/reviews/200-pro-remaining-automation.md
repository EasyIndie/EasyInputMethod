# 200 pro 侧其余自动化项（离线回归 / 本地验收 / 对比度 / 长时久用）

## 1. 范围

报告198/199 覆盖了键入路径、内存门禁与久用；本报告把 pro 上**其余可自动化**的门禁跑完，并修掉挡路的测试基础设施问题。人工项（VoiceOver、多屏/缩放/Spaces/全屏、睡眠唤醒、真实卸载→重装）按用户要求留到后面。

环境：pro（Intel x86_64 / macOS 13.7.8 / 用户 `bot`），0.1.13 build 21，执行 SHA `c3b533e4…`，`config.toml` `2bd3fde6…`。

## 2. 离线回归：从「3 项失败」到 50/50 PASS

`make macos-offline-tests` 在 pro 上原本直接失败，逐个查清后是两个问题：

### 2.1 系统自带的 `python3` 是 3.9，而套件要 ≥3.11

`packaging/macos/validate-release.py` 与 `tools/release_version.py` 用 `tomllib`（3.11+），macOS 13 的 `/usr/bin/python3` 是 3.9.6，于是 `test-validate-release.py` 直接 `ModuleNotFoundError`。

- `run-offline-tests.py`：版本不足时给出明确提示（不再是 traceback）。
- `Makefile`：新增 `PYTHON`，按 `python3.13 → 3.12 → 3.11 → python3` 挑第一个可用的，`macos-offline-tests`/`macos-local-acceptance` 用它（其余目标不动）。

### 2.2 沙盒回归把「结果文件位置」写死成较新系统的行为

`test-sandbox-config.py` 只读 `~/Library/Containers/<id>/Data/tmp/sandbox-probe.json`。实测 macOS 13 上**沙盒应用的 `temporaryDirectory` 是** `/var/folders/…/T/<bundle-id>/`，较新系统才映射到容器 `Data/tmp`。探针本身的行为是对的（容器内 `Data/Library/Application Support/Lampyris/config.toml` 已由 `ime-config` 写出，`init/set` 返回 0、回读 `7`），缺的只是测试的查找路径。

修法：两个候选路径都查（容器 `Data/tmp` 与 `/var/folders/…/T/<id>`），断言的硬规则仍是「配置只落容器」。

### 2.3 本地验收的 `candidate` 套件在所有机器上都 BLOCKED

`run-local-acceptance.py` 的必测清单比探针落后三个场景：`candidate.keyboard-confirm-target`（`b0088a1` 方向键浏览）、`candidate.batched-status`（`3eb87c2`）、`candidate.content-phases`（`e3f4b0e`）。探针一直记录这三项，但清单没加，于是 `set(ids) != set(required)` → 每次都被判 `BLOCKED`，且报错信息只打印「缺失」集合（为空），把真正原因（多出未登记场景）藏住了。

修法：把三项补进必测清单（`test-local-acceptance.py` 的合成用例总数随之 67 → 70）。

**结果**：`make macos-offline-tests` → **50/50 PASS**；`make macos-local-acceptance` → **6 个套件全 PASS、70 个本地用例**（`MVP remains BLOCKED` 是设计如此，本地离屏证据不等于正式场景证据）。

## 3. UI 快照对比度：28/28 PASS

`make macos-ui-contrast`（离屏渲染，不操作桌面）：28 张快照的最低对比度 10.00:1（阈值 4.5:1），失败 0 张。air（macOS 27）是 26 张全过；pro 这里多了 2 张，说明 Intel/macOS 13 的渲染同样达标。

## 4. 长时久用（带 footprint 采样）：PASS，长会话悬案有进展

给 `soak-session.sh` 加了每 10 秒一次的 `vmmap` physical footprint 采样（RSS 跨版本不可比，见报告198）。

`MINUTES=10`（约 2.3k 键，235 轮）：

| 项 | 值 |
|---|---|
| footprint | 23.4 → **24.6 MiB**（峰值 24.6），后半段增量 **+0.1 MiB** |
| RSS | 37.8 → 稳态 39.3 MiB（增长 0.1 MiB） |
| 网络 | 全程 **0 条** TCP/UDP |
| 词库 | 486 → 486 → 重启后仍 486 |
| 结果 | PASS |

**结论（对报告199 §2 的补充）**：连续键入 10 分钟只会带来 ~1 MiB footprint 增量；报告198 里 43M 的读数来自**数小时混合会话**（多应用窗口/候选窗反复创建 + 用户真实输入），不是「打字越多越涨」。要判定数小时尺度是否收敛，需要更长的观测窗口，暂列后续，不影响当前候选。

## 5. 其它自动化状态（只读核对）

| 项 | 状态 |
|---|---|
| `macOS Nightly` | 最近一次 `40229361253` **success**（更早一次失败是 `test-ci-sign.py` 依赖本地产物，已由 #163/#164 修） |
| `CI` / `macOS Acceptance Package`（main） | success |
| 开放 PR | 0 |

## 6. 仍未做的自动化（需你点头，属于「换包」操作）

- **真实卸载 → 重装（保留数据）**：脚本层面已有 6 项离线回归（`test-uninstall-script.py`），但要在 pro 上真跑一次「用 DMG 里的卸载器卸载（保留数据）→ 重新安装 → 校验执行 SHA/config/词库/输入源」。这会替换已装应用，按铁律 §5 需要单独授权。
- 人工项：VoiceOver、多屏/缩放/Spaces/全屏、睡眠唤醒。

## 7. 本轮改动

| 文件 | 改动 |
|---|---|
| `Makefile` | 新增 `PYTHON`（优先 ≥3.11），仅用于 `macos-offline-tests`/`macos-local-acceptance` |
| `platforms/macos/tests/run-offline-tests.py` | Python <3.11 时给出明确提示 |
| `packaging/macos/tests/test-sandbox-config.py` | 结果文件位置兼容 macOS 13（容器 `Data/tmp` 或 `/var/folders/…/T/<id>`） |
| `platforms/macos/tests/run-local-acceptance.py` + `test-local-acceptance.py` | `candidate` 必测清单补 3 项（67 → 70） |
| `tools/macos-probe/soak-session.sh` | 增加 physical footprint 采样与统计字段 |

产品代码（Rust/Swift 宿主）未改动；0.1.13 执行 SHA 全程未变；`config.toml` 未变、词库随学习增长（482 → 486，用户设置，不还原）。
