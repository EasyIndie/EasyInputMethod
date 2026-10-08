# 任务卡（Task Cards）

> 把 ROADMAP 的阶段拆成**独立可交付、可被低成本模型（deepseek-v4-flash）执行**的最小任务卡。
> **规则见根目录 `AGENTS.md`**（铁律/工作流/验证）；本目录只负责"更细的粒度"。

## 一、任务卡格式（每张卡固定结构）

```markdown
# T-XXX-xx：标题
- 状态：待认领 / 进行中 / 完成
- 模型建议：flash / pro（及理由）
- 前置：依赖的任务卡 ID（无则写"无"）
- 目标：一句话
- 步骤：明确的、可照做的步骤（flash 需要非常具体，不含设计决策）
- 验收：可执行的命令/断言
- 铁律提醒：本任务相关的 AGENTS.md 铁律
- 禁止：明确不要做的事
- 参考：docs/ 相关章节
```

## 二、flash vs pro 分工原则

| 模型 | 适合 | 不适合 |
|---|---|---|
| **flash** | 步骤明确、无歧义的机械工作：骨架/脚手架、数据登记、规则简单的生成器、对照脚本、单测 | 领域知识判断（五笔取码/识别码）、设计决策、微妙 bug、跨模块集成 |
| **pro** | 五笔编码规则、重码排序调优、集成联调、审核、架构决策 | — |

**铁律：flash 卡里不得出现"酌情/合理/优化"等需要判断的词，必须给出可照抄的规格。** 若做不到，就标 pro。

## 三、派发方式（headless flash 当子代理用）

```bash
# 默认：一张卡 = 一个新 worker
./scripts/dispatch-task.sh docs/tasks/T-M1-01.md --model deepseek-v4-flash

# 仅当后一卡必须接着前一卡的上下文时，才复用同一会话
./scripts/dispatch-task.sh docs/tasks/T-M1-02.md --model <flash> --reuse seq-a
```

脚本会：读任务卡 → 用指定模型 headless 执行 → 要求跑 `make verify` + 更新 HANDOFF/ROADMAP → 只回简短摘要；**并把本次 token/成本记入 `docs/experiments/runs/usage.jsonl`**。

- 汇总用量：`./scripts/usage-report.sh`
- 受控对比（花 token）：`./scripts/bench-session-vs-workers.sh --micro`
- 结论与判定规则：`docs/experiments/`
- **磁盘预检**：默认要求 ≥ 3 GiB 余量，不足即拒绝（`--min-free-gb N` 可调）。
- **编译并行度**：`--jobs N` 设 `CARGO_BUILD_JOBS`，防多 worker 抢核。
  ⚠️ 本机仅 **2 物理核**：磁盘够但 CPU 是瓶颈 → **默认顺序派发**，不要盲目并行。

> 模型名以 `/model` 或 `pi --model` 实际可用为准；`deepseek-v4-flash` 是占位示例。
>
> ⚠️ **实测结论**（`docs/experiments/session-vs-workers.md`，N=5 中位数）：
> **弱依赖/独立任务 → 每卡新 worker**（reuse 无益或更贵，实测 +15%）；
> **强依赖序列 → 同一会话 `--reuse`**（实测快 **4.4×**）。
> 判断法：问“不给上卡对话、只给仓库文件，我能做到吗？”——能→新 worker；不能→reuse。

## 四、卡片清单

### P1-M1（自建码表 + 词频）—— 下一阶段，已拆细

| ID | 标题 | 模型 | 依赖 |
|---|---|---|---|
| [T-M1-01](T-M1-01.md) | 字根表建模与编码器 crate 骨架 | flash | 无 |
| [T-M1-02](T-M1-02.md) | 键名字 + 成字字根编码规则 | flash | T-M1-01 |
| [T-M1-03](T-M1-03.md) | 合体字取码 + 末笔字型识别码 | **pro** | T-M1-02 |
| [T-M1-04](T-M1-04.md) | 拆字数据加载与交叉校验 | flash | 无 |
| [T-M1-04b](T-M1-04b.md) | 接入第二个 oracle 码表（rime-wubi） | flash | T-M1-04 |
| [T-M1-05a](T-M1-05a.md) | 引入独立的结构/末笔数据源 | **pro** | T-M1-03, T-M1-04 |
| [T-M1-05b](T-M1-05b.md) | 自建独立结构/末笔数据集（IDS+部件表） | **pro** | T-M1-05a |
| [T-M1-05](T-M1-05.md) | 单字码表生成 + 多 oracle 回归 | **pro** | T-M1-03, T-M1-04, T-M1-04b |
| [T-M1-06](T-M1-06.md) | 词组码自动生成 | flash | T-M1-05 |
| [T-M1-06b](T-M1-06b.md) | 词表与词频升级（jieba，含 T-M1-07） | flash | T-M1-05, T-M1-06 |
| [T-M1-07](T-M1-07.md) | 词频权重接入（已并入 06b） | flash | — |
| [T-M1-08](T-M1-08.md) | 数据来源与许可登记 | flash | T-M1-04/06b |
| [T-M1-09](T-M1-09.md) | 正式码表接入 ime-table / ime-cli | **pro** | T-M1-05, T-M1-06b |

### 后续（粗粒度，到点时再拆）

见 [backlog.md](backlog.md)。

### P1-M2（配置 + 拼音 + 混输）

| ID | 标题 | 模型 | 依赖 |
|---|---|---|---|
| [T-M2-01](T-M2-01.md) | `ime-config` 配置子系统 | **pro** | 无 |
| [T-M2-02](T-M2-02.md) | 内置轻量拼音引擎 `ime-pinyin` | **pro** | T-M2-01 |
| [T-M2-03](T-M2-03.md) | 拼音反查 + `ime-config` 接入 CLI | **pro** | T-M2-01, T-M2-02 |
| [T-M2-04](T-M2-04.md) | `inputx-pinyin` spike | flash | — |

### P1-M3（macOS 宿主）

| ID | 标题 | 模型 | 依赖 |
|---|---|---|---|
| [T-M3-01](T-M3-01.md) | `ime-ffi` C ABI（会话 + 配置） | **pro** | P1-M1/M2 |
| [T-M3-02](T-M3-02.md) | Swift + InputMethodKit 宿主（需人工验证） | **pro** | T-M3-01 |
| [T-M3-03](T-M3-03.md) | 安装/卸载脚本 + Gatekeeper 说明 | flash | T-M3-02 |
| [T-M3-04](T-M3-04.md) | CI 加 macOS runner（覆盖 Swift 前端） | flash | T-M3-02 |
