# 用量实验（Experiments）

> 目的：用**真实数据**回答"一个主会话 vs 一堆子代理/无头 worker，哪个更省"，而不是凭感觉。

## 一、度量什么

每次 headless pi 调用（`pi --mode json`）都会记录：

| 字段 | 含义 |
|---|---|
| `input` | 全价输入 token（缓存未命中部分） |
| `cacheRead` | 命中缓存的输入 token（便宜，约 1/10 价） |
| `cacheWrite` | 写缓存的 token（有溢价，一次） |
| `output` | 输出 token |
| `totalTokens` / `cost` | 合计 |

**关键指标 `cacheHitRate = cacheRead / (cacheRead + input)`**：越高越省。
**持久会话（reuse）应显著高于每次新 worker（fresh）。**

## 二、工具

```bash
# 1) 平时派发任务卡时自动记录（零额外成本）
./scripts/dispatch-task.sh docs/tasks/T-M1-01.md --model <flash> --reuse batch-a

# 2) 汇总（纯本地，不花 token）
./scripts/usage-report.sh            # 全部
./scripts/usage-report.sh bench-     # 只看 A/B 实验

# 3) 受控 A/B / 微基准（会真的跑 pi，花 token）
./scripts/bench-session-vs-workers.sh --micro
./scripts/bench-session-vs-workers.sh --tasks "docs/tasks/T-M1-01.md docs/tasks/T-M1-04.md"
```

- `--micro`：用同一句极短 prompt 跑"新会话"与"复用会话"，**直接量出冷启动过路费**。
- `--tasks`：在两个 `git worktree` 里分别跑"每次新 worker"和"一个持久会话"，主仓库不受影响。
- 数据落 `docs/experiments/runs/usage.jsonl`（提交）；原始事件流落 `runs/raw/`（gitignore）。
- 不花 token 地验证管道：`PI_CMD=echo ./scripts/bench-session-vs-workers.sh --micro`

## 三、判定规则（据实测数据选用）

记 `O` = 单次冷启动过路费（微基准测得的 fresh 平均 `input+cacheWrite` 成本），
`T` = 某任务本身的净成本。

- **一类小任务**（`T ≲ O`）→ 留在主会话 / 持久 worker 里做。
- **一批小任务** → **一个持久 worker 串行跑**（缓存热，过路费只付一次）。
- **孤立的大任务** → 开新 worker 值得（过路费摊薄，且隔离更专注）。
- **并行**：只在墙钟时间重要、且任务彼此独立时用（每个 worker 各付一次过路费）。

> 注意：A/B 里两臂在各自 worktree 跑，仓库状态演化相近但非完全相同；本实验测的是
> **会话复用带来的缓存/固定开销差异**，不是代码质量差异。

## 四、结论

见 [session-vs-workers.md](session-vs-workers.md)（随数据积累持续更新）。
