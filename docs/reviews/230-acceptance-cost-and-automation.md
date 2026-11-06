# 230 — 验收成本梳理：自动化、合并、精简、并行

- 日期：2026-11-06　｜　触发：用户「验收耗时太长，全面梳理」　｜　基线包：1.1.0 / build 38（`d3c5a2ef…`）
- 关联：报告 229（延迟门禁）、`docs/tasks/T-ITER-22.md`、`docs/tasks/T-ITER-22-coverage.md`

## 0. 结果速览

| 项 | 之前 | 之后 | 手段 |
|---|---|---|---|
| 离线回归（55–56 文件） | **127–164s** 串行 | **33.6s**（6 并发） | `run-offline-tests.py` 并行化，`JOBS=N` 可调 |
| `make macos-local-acceptance` | 49s，**且已腐烂到必失败** | 删除（并入离线回归） | 同名目标改为别名，指向唯一 runner |
| 一键探针 `acceptance-auto` | ~9 分钟 | **4.7 分钟**（`FAST=1`），发布仍用默认档 | `ROUNDS`/`SETTLE`/`KEY_SETTLE` 可配 + FAST 档 |
| IT-22 人工走查 | 65 项 | **17 项人工 + 1 项日常**（每次换包 12 项 ≈12 分钟） | 覆盖映射 + 精简清单（`T-ITER-22-coverage.md`） |
| `make verify` | 13.6s | 13.6s（无改动空间） | — |

## 1. 盘点：钱花在哪

| 环节 | 之前的实测 | 说明 |
|---|---|---|
| `make verify` | 13.6s | fmt/clippy/test/deny/零网络符号，已很便宜 |
| `make macos-offline-tests` | 127s（56 文件/303 例） | 单进程串行；最贵的是 6 个编译 Swift 的用例（8–12s each） |
| `make macos-local-acceptance` | 49s 且 **exit 3** | 第二套 runner，契约（`observations.json` + 固定 case 名）早已和重写后的测试对不上 |
| `make macos-auto-acceptance` | ~9 分钟 | 热键 10 次 type-session（每次 settle 8s）+ 性能 10 轮 + 5 客户端 |
| IT-22 人工 | 65 项、两小时级 | 其中 47 项与脚本/单测重复 |

## 2. 自动化（能跑就别让人跑）

1. **离线回归并行**：`run-offline-tests.py` 支持 `JOBS`（默认 `min(6, CPU)`），每个文件独立日志不变；
   摘要新增 `jobs` / `seconds` / `serial_seconds`。串行 163.7s → 并行 **33.6s**。
   `JOBS=1` 保留给归因排查。
2. **一键探针 FAST 档**：`FAST=1 make macos-auto-acceptance` → `ROUNDS=4`、性能静置 8s、热键 settle 6s，
   实测 281s（默认档 ~9 分钟）。发布门禁仍跑默认档；开发迭代用 FAST。
   教训：热键 settle 压到 4s 会让 ⌥M / ⌥T 读到空文本（实测一次 FAIL），所以 FAST 档只压轮数与性能静置。
3. **IT-22 覆盖映射**：`docs/tasks/T-ITER-22-coverage.md` 把 47 项映射到具体命令/测试文件，
   人工清单压到 12 项（A 档，每次换包）+ 5 项（B 档，每版一次，需换包授权）+ 1 项并入日常。

## 3. 合并与精简

1. **两套 runner 合成一套**：删掉 `platforms/macos/tests/run-local-acceptance.py` 与其自测
   `test-local-acceptance.py`。它本质上把同一批 `test-*.py` 再跑一遍，还要求早已废弃的
   `observations.json`/固定 case 名契约 —— 结果是**必失败**的假门禁（本轮 `make macos-local-acceptance` exit 3）。
   `make macos-local-acceptance` 保留为别名（打印废弃提示后转 `macos-offline-tests`），文档同步。
2. **同一场景不再写三遍**：`quality-samples.sh`（16 项）与 `acceptance-auto.sh`（8 项）有重叠、
   IT-22 手工表又重叠一次。现在以脚本为准，手工表只留脚本判不了的部分。
3. **安装类降级**：IT-22 §8 五项从"每次走查"降为"每版一次"，因为它们只在换包时有意义。

## 4. 顺手修掉的两处腐烂/假 FAIL

| 问题 | 现象 | 修法 |
|---|---|---|
| `test-preview-menu.py` 在有宿主运行时必失败 | 宿主学习落盘会**整文件重写**词库，测试的"只追加"豁免判不出，于是把宿主行为记成"真实数据被改" | 有宿主在跑时该断言记 SKIP（并给出原因）；无宿主（CI）仍严格断言 |
| IT-22 的 `menu-view` 覆盖映射过期 | runner 期望 `menu-view.*` 的 `observations.json`，测试早已改成聚合断言 | 测试把探针的 case 名透传到日志；runner 整体删除（见 §3.1） |

## 5. 防腐烂

新增 `platforms/macos/tests/test-acceptance-map.py`（进离线回归，毫秒级）：
校验覆盖映射引用的 Make 目标/脚本/测试文件全部存在、人工清单条目不重复。
以后再出现"文档说自动覆盖、实际没这个命令"会直接在离线回归里挂掉。

## 6. 一条命令的推荐姿势

```sh
# 开发迭代（约 1 分钟 + 4.7 分钟）
make verify && make macos-offline-tests && FAST=1 make macos-auto-acceptance

# 发布候选（约 1 分钟 + 9 分钟 + 12 分钟人工）
make verify && make macos-offline-tests && make macos-acceptance-full
# 再按 T-ITER-22-coverage.md §2 的 A 档走 12 项人工；B 档只在发版时做
```

## 7. 没做 / 边界

- 没有降低发布门禁本身：默认档轮数、阈值、人工 A 档判定口径全部不变，只是把重复劳动删掉。
- `quality-samples.sh`（16 项）与 `acceptance-auto.sh` 的热键项仍有内容重叠（约 5 项语义相同）。
  合并它们需要重排证据文件命名与历史报告引用，本轮不动，留作下一步。
- 客户端矩阵在 air 上仍会随环境漂移（本机验证时 4/4 与 2/4 都出现过），已按 BLOCKED 记账，不当 PASS。
