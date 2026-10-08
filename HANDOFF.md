# HANDOFF — 会话交接文档

> **本文件记录"当前状态"，供任意 AI 工具在任意新会话中快速接手，防止背景信息丢失。**
> **每次会话结束时必须更新本文件**（规则见 `AGENTS.md` §6.1；操作见 Skill `update-handoff`）。
>
> 稳定背景（设计、决策、数据合规）在 `docs/`；**本文件只回答三件事：此刻在哪 / 下一步做什么 / 有什么坑。**

---

## 0. 元信息

| 项 | 值 |
|---|---|
| 最后更新 | 2026-10-08 |
| 更新者 | pi |
| 当前阶段 | **P1-M1 进行中（T-M1-01/02/04 完成；下一步 T-M1-03）** |
| 当前分支 | `main`（T-M1-04 改动待提交） |
| 活跃 PR | 无 |
| 最近一次 `make verify` | ✅ 全绿（fmt+clippy+24 测试+deny+隐私断言） |

## 1. 三十秒摘要

- **萤火虫**：跨平台、开源可审计、默认离线、只做核心输入的中文输入法（五笔优先，**默认混输**）。
- **技术**：Rust 引擎 + 窄 C ABI + 平台薄宿主；**GPL-3.0-or-later**。
- **现在**：**P1-M1 进行中**（`wubi-encoder` 字根骨架 + 键名字/成字字根；拆字数据已登记并完成交叉校验；24 测试、`make verify` 全绿）。
- **下一步**：`ROADMAP.md` 的 **P1-M1**（自建码表流水线 + 词频权重）。
- ⛔ 继续遵循铁律：核心不联网、`forbid(unsafe_code)`、数据登记许可。

## 2. 已完成

- 竞品调研、架构选型；**码表自建可行性已验证**（词组码 99.90% 可由单字码推导）。
- 权威方案 `docs/技术方案.md` + 配套文档；交叉审核（`docs/reviews/001.md`）已确认并落地行动项。
- **P1-M0**：Rust workspace、`ime-core`（Engine/InputMode/会话状态机）、`ime-table`（码表引擎）、`ime-cli`（REPL）。
- **P1-M1 / T-M1-01**：新建 `crates/wubi-encoder`（零外部依赖、`forbid(unsafe_code)`）：`RadicalTable::from_tsv` + `radical_to_key`，`Stroke`/`Structure`/`EncodeError`；6 个单测。
- **P1-M1 / T-M1-02**：`RadicalTable::key_name_char`/`is_radical_char` + `encode_key_name`/`stroke_to_key`/`encode_chengzi`（键名字、成字字根）；新增 `TooFewStrokes` 错误；7 个单测。
- **P1-M1 / T-M1-04**：`data/sources.toml` + `data/sources/fetch-wubi-chaizi.sh`（D2 `aardio/wubi-lex`、D3 `huanfeng/WindInput`，均 MIT，SHA-256 固定）；`wubi-encoder/examples/crosscheck.rs` 产出 `data/generated/chaizi-diff.txt`。
- 实现阶段发现 `yada` 不支持预测搜索 → 改定 `cedarwood`（ADR-015）。

## 3. 进行中

**P1-M1**（自建码表流水线）：T-M1-01/02/04 已交付；**T-M1-03 待认领**（合体字 + 末笔字型识别码，尚无编码逻辑）。

## 4. 下一步（优先级排序）

1. **P1-M1**：按 `docs/tasks/` 取卡执行。T-M1-01 ✅、T-M1-02 ✅、T-M1-04 ✅；下一步 **T-M1-03**（合体字 + 末笔字型识别码，pro，依赖 T-M1-02），随后 T-M1-05（码表生成 + 对照回归，pro，依赖 T-M1-03/04）。
2. 定 `TBD-4`：英文/包名（`yinghuo` vs `lampyris`）。
3. 之后 **P1-M2**：`ime-config` + 拼音兜底 + 混输合并。

## 5. 待决 / 阻塞

| 编号 | 问题 | 是否阻塞 |
|---|---|---|
| REV-1…4 | 交叉审核已**完成**（`docs/reviews/001.md`），结论有条件通过 | 否 |
| TBD-1 | 词频数据源（ADR-013 已定为 P1-M1 必交付；具体数据源仍待选） | 阻塞 P1-M1 |
| TBD-2 | 五笔98 / 新世纪 / 郑码数据源 | 否 |
| TBD-3 | 用户词库存储格式 | 阻塞 P1-M4 |
| TBD-4 | 英文/包名 | 否 |

## 6. 必须知道的坑与硬约束（详见 `AGENTS.md` 铁律）

- 核心 crate **不联网**、`#![forbid(unsafe_code)]`；`unsafe` 只在 `ime-ffi`。
- 配置只能走 `ime-config`；**禁止**写 `UserDefaults` / 注册表 / 第二个配置文件。
- 任何数据必须**登记许可**（`docs/数据来源与许可.md` + `data/sources.toml`）。
- ⚠️ `rime-wubi86-jidian` 的**码表 provenance 存疑**（源自闭源"极点五笔"），**只可作过渡/测试**，不得作为正式发布的不可替代来源。
- **不复用 weasel / squirrel 代码**（GPL，只读不抄）。
- 提交前必须 `make verify` 全绿。

## 7. 环境快照

| 项 | 值 |
|---|---|
| 平台 | macOS |
| Rust | 1.98.1（由 `rust-toolchain.toml` 固定） |
| 构建 | `make` 可用；`just` 不可用（故用 Makefile） |
| 依赖工具 | `cargo-deny`、`cargo-fuzz` 已安装 |
| 硬件 | **2 物理核 / 4 逻辑核，16 GB 内存，14 GiB 可用磁盘** |
| 编译成本 | 全量冷编译 ≈ 4 秒，`target/` ≈ 22 MB（当前零依赖；加依赖后会涨） |
| 代码 | ✅ Rust workspace 就绪（`ime-core`/`ime-table`/`ime-cli`/`wubi-encoder`），24 个测试通过 |

## 8. 接手清单（新会话开始时）

- [ ] 读 `AGENTS.md`（铁律 / 工作流 / 约定）
- [ ] 读本文件
- [ ] 看 `ROADMAP.md` 当前进度
- [ ] 读与本次任务相关的 `docs/` 文档
- [ ] 若要写代码：先跑 `make verify` 确认基线
- [ ] 有歧义 → **先问，不要猜**

## 9. 会话日志（倒序，保留最近 10 条；更早见 git 历史）

### 2026-10-08 · pi（T-M1-04 拆字数据交叉校验）
- 新增 `data/sources/fetch-wubi-chaizi.sh`（下载 D2 aardio/wubi-lex 86.txt、D3 WindInput wubi86_chaizi.txt；SHA-256 固定并校验；源文件不入库）+ `data/sources.toml`（D2/D3 登记）；`docs/数据来源与许可.md` §1.1 补 SHA-256 与脚本路径。
- 新增 `crates/wubi-encoder/examples/crosscheck.rs`：产出 `data/generated/chaizi-diff.txt`（交集 6862、仅 D3 独有 20961、分歧 6861；D2 可见字根 vs D3 PUA，差异大属预期）。
- 验证：`make verify` 全绿（24 测试）；未裁定分歧（留 T-M1-05，pro）。

### 2026-10-08 · pi（T-M1-02 键名字+成字字根）
- `crates/wubi-encoder`：新增 `key_name_char`（25 键名固定映射）、`is_radical_char`、`encode_key_name`（键连打四次）、`stroke_to_key`（横G竖H撇T捺Y折N）、`encode_chengzi`（键+首次末笔）；新增 `TooFewStrokes` 错误（笔画<2 报错）。
- 未改动其它 crate；未实现合体字/识别码（留 T-M1-03）。
- 验证：`cargo test -p wubi-encoder` 13 通过；`make verify` 全绿（24 测试）。

### 2026-10-08 · pi（派发防护 + T-M1-01 质检）
- T-M1-01 已由 flash worker 完成并**人工复核**：质量优秀，`make verify` 全绿（17 测试）。已提交。
- 派发工具加防护：`--jobs N`（`CARGO_BUILD_JOBS`）+ 磁盘预检（默认 ≥3 GiB，`--min-free-gb N`）。
- 硬件实测：可用磁盘 14 GiB（每 worktree ≈22 MB，宽裕）；但仅 **2 物理核** → **并行上限建议 2，当前默认顺序派发**。

### 2026-10-08 · pi（T-M1-01 字根表骨架）
- 新建 `crates/wubi-encoder`（零外部依赖、`forbid(unsafe_code)`）：`RadicalTable::from_tsv`/`radical_to_key` + `Stroke`/`Structure`/`EncodeError`。
- 仅字根→键查询，**不含编码逻辑**（留给 T-M1-02/03）；未改动 `ime-core`/`ime-table`/`ime-cli`。
- 验证：`cargo test -p wubi-encoder` 6 通过；`make verify` 全绿（17 测试、clippy、deny、隐私断言）。
- 卡外无改动；`ime-cli` 冒烟行为不变。

### 2026-10-08 · pi（重复实验定论）
- 新增可重复 A/B：`bench-session-vs-workers.sh --workload --repeat`、`usage-compare.sh`（中位数）、`docs/experiments/workloads/`。
- **N=5 中位数结论**：独立负载 fresh 37.9k vs reuse 43.6k（+15%，分布重叠）；
  强依赖负载 fresh 230.9k vs reuse 51.9k（**reuse 快 4.4×**，分布不重叠）。
- **开发约定**：默认每卡新 worker（任务卡保持自包含）；仅“必须接着上卡上下文”的序列用 `--reuse`。
- 详见 `docs/experiments/session-vs-workers.md`。

### 2026-10-08 · pi（会话 vs worker 实测）
- 跑通完整 A/B（模型 `deepseek-v4-flash`，负载 = T-M1-01 + T-M1-02），两臂均成功且产出等价。
- **结论（反直觉）**：对独立任务，**每卡新 worker 更省**（A 521k vs B 918k tokens，+76%）；
  B 的 cacheHitRate 更高（96.8%）但上下文滚雪球（任务二 cacheRead 3.4×）。
- 微基准：固定开销 ≈ 4.3k tokens/次；前缀缓存跨会话共享 → 开新会话 ≠ 冷启动。
- 默认派发改定：**一张卡 = 一个新 worker**；`--reuse` 仅用于强依赖序列。详见 `docs/experiments/session-vs-workers.md`。
- 注意：provider 未配计价，`cost`=0；用 token 口径。n=1，方差大。

### 2026-10-08 · pi（用量量测脚手架）
- 新增用量量测：`scripts/lib/pi-usage.sh`、`dispatch-task.sh`（支持 `--model/--reuse/--label`）、`usage-report.sh`、`bench-session-vs-workers.sh`（`--micro`/`--tasks`）。
- 新增 `docs/experiments/`（方法学 + 判定规则 + 结论待实测）。`make usage-report` 可本地汇总（不花 token）。
- 用途：用真实 token/成本数据判定“持久会话 vs 每次新 worker”。已用 `PI_CMD=echo` 验证管道与合成数据校验汇总数值。
- 遗留：待用真实模型跑 `bench-session-vs-workers.sh --micro` 采集数据。

### 2026-10-08 · pi（上下文压缩前交接）
- 关键上下文已固化到本文件与 docs/；代码无未提交变更（已推 origin/main）。
- 恢复要点：读本文件 §0–§8 → 按 §4 下一步执行 → 派发任务卡用 `scripts/dispatch-task.sh`。
- 决策记录在 `docs/决策记录.md`（ADR-001…015）；审核报告 `docs/reviews/001.md`。

### 2026-10-08 · pi（首次提交 + 任务拆分）
- 首次提交并推送到 origin/main（commit a699ac1 之前）。
- 拆分 P1-M1 为 9 张任务卡（docs/tasks/），按 flash/pro 标注；新增 dispatch-task.sh（headless 派发）。
- 结论：pi 无原生子代理，用 virtual models 或 headless CLI 实现 flash 派发。
- 遗留：P1-M1 待认领；TBD-4 包名待定。

### 2026-10-08 · pi（P1-M0 实现）
- 完成 P1-M0：Rust workspace + `ime-core`（Engine trait/InputMode/会话状态机）+ `ime-table`（排序数组码表）+ `ime-cli`（REPL）。
- 验证：11 测试通过、clippy -D warnings 干净、`cargo deny` 通过、隐私断言过（22 产物无网络符号）。
- 实现期发现：`yada` 无预测搜索 → 弃用，改 `cedarwood`（ADR-015）；Makefile 反引号命令替换 bug 已修。
- 遗留：P1-M1 开始；TBD-4 包名待定。

