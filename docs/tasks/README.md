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

### 当前迭代（T-ITER-01进行中；其余待认领）

统一排序与其余待拆任务见 [迭代计划](../迭代计划.md)。

| 卡片 | 主题 | 前置 |
|---|---|---|
| [T-ITER-01](T-ITER-01.md) | 多应用验收资源所有权 | 无 |
| [T-ITER-02](T-ITER-02.md) | 面板验收文件与词库隔离 | 无 |
| [T-ITER-04](T-ITER-04.md) | 快捷键统一解析与校验 | 无 |
| [T-ITER-05](T-ITER-05.md) | 全半角配置与覆盖一致 | 无 |
| [T-ITER-06](T-ITER-06.md) | 组合中配置重算 | 无 |
| [T-ITER-07](T-ITER-07.md) | 保存失败反馈 | IT-04 |

[T-ITER-03](T-ITER-03.md)结果分类与覆盖门禁、[T-ITER-12](T-ITER-12.md)宿主性能基线、[T-ITER-13](T-ITER-13.md)发布附件与构建元信息、[T-ITER-20](T-ITER-20.md)五笔键位提示均已拆卡并进行中；其余卡按统一队列到点细化。以下原里程碑卡片用于追溯，状态以各卡为准。


### P1-M1（自建码表 + 词频）—— 历史任务；主体已交付

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
| [T-M1-10](T-M1-10.md) | `convert` 去全表线性扫描（二分 + 前缀区间） | **pro** | ADR-060 |

### 原P2已提前交付项（现属MVP功能集；见各卡完成记录）

| ID | 标题 | 模型 | 依赖 |
|---|---|---|---|
| [T-P2-01](T-P2-01.md) | 简繁转换（含 `Ctrl+Shift+F` 默认键） | **pro** | ADR-014/016/068 |
| [T-P2-02](T-P2-02.md) | 偏好设置面板（Schema 驱动非模态） | **pro** | ADR-070 |
| [T-P2-03](T-P2-03.md) | 用户反馈入口（本地诊断 + 用户主动打开） | **pro** | ADR-071 |
| [T-P2-04](T-P2-04-memory.md) | 引擎常驻内存优化（**MEM-1**，macOS 27/arm64 ≤30MB） | **pro** | ADR-060、MVP-05 §2.4 |

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

- [T-ITER-23：单人五工作日手动试用](T-ITER-23.md)：用户计划2026-10-13开始，最终RC及实际结果待验。

## 核心完整性评估待办

- [IT-29](T-ITER-29.md)：混输自动提交跨引擎歧义。
- [IT-26](T-ITER-26.md)：拼音兜底首屏可达。
- [IT-27](T-ITER-27.md)：隔音符与常用读音质量。
- [IT-28](T-ITER-28.md)：编辑键/安全输入边界取证，非已确认漏洞。

IT-29与IT-26工程完成，IT-27隔音符工程完成、读音质量待推进；全部最终包原生门禁待验。见[报告012](../reviews/012-core-refinement.md)。

[IT-27读音工程结果](../reviews/014-pinyin-reading-quality.md)，最终包原生待验。

[IT-28工程结果及原生矩阵](../reviews/015-editing-boundary-audit.md)；编辑键工程完成，安全字段/布局等原生待验。

2026-10-14用户批准ADR-165：基础UI纳入MVP，候选→设置/菜单→既有工具/反馈→外观/AX→重新锁最终包；功能基线66ab513保留，完整教学后移。实施见docs/design/mvp-ui.md及T-MVP-UI；历史“全UI延期”段落被本决策覆盖，新UI尚未原生验收。

## 当前教学数据专项

[T-MVP-LEARNING-COVERAGE](T-MVP-LEARNING-COVERAGE.md)：覆盖审计已完成，按高频100→500→1000/3500分批核验教学；与UI工程完成分开验收。

- [`T-ITER-22.md`](T-ITER-22.md)：最终候选产品走查（IT-22 执行清单，含取证命令与判定口径）。
