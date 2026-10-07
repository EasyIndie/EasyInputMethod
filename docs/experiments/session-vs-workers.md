# 结论：一个主会话 vs 一堆无头 worker

> 数据来源：`docs/experiments/runs/usage.jsonl`（由 `scripts/usage-report.sh` 汇总）。
> **本文件是"活"的**：每次跑完 `bench-session-vs-workers.sh` 后更新。

## 状态

⏳ **尚未采集实测数据**（等待首次运行）。

```bash
# 采集（会花 token）：
./scripts/bench-session-vs-workers.sh --micro
./scripts/bench-session-vs-workers.sh --tasks "docs/tasks/T-M1-01.md docs/tasks/T-M1-04.md"
# 汇总：
./scripts/usage-report.sh bench-
```

## 结果表（待填）

### 微基准：冷启动过路费

| 指标 | micro-fresh | micro-reuse-1 | micro-reuse-2 |
|---|---|---|---|
| model | | | |
| totalTokens | | | |
| input | | | |
| cacheRead | | | |
| cacheWrite | | | |
| cacheHitRate | | | |
| cost | | | |

**过路费 O ≈**（fresh 的 input+cacheWrite）＝ 待填。

### 完整 A/B

| 臂 | 任务数 | 总 tokens | 总 cost | cacheHitRate | 单任务均 cost |
|---|---|---|---|---|---|
| A 每次新 worker (fresh) | | | | | |
| B 持久会话 (reuse) | | | | | |

**差异**：(B − A) / A ＝ 待填。

## 结论（待数据）

暂定（机制推导，待实测校准）：

1. **持久会话的 cacheHitRate 明显更高**，固定开销只付一次 → 一批任务更省。
2. **单个孤立大任务** 开新 worker 值得（过路费摊薄 + 隔离）。
3. **单张小卡** 的净成本很可能 **小于** 过路费 O → 不要为它单开 worker。
4. 并行只在墙钟时间重要时用；并行会 **乘以** 过路费。

> 待采集后，把上面的数字填进来，并据此**收敛/修正** P1-M1 的派发策略（写回
> `docs/tasks/README.md` 与 `HANDOFF.md`）。

## 复现方法

1. `PI_CMD=echo ./scripts/bench-session-vs-workers.sh --micro`（验证管道，不花 token）
2. 用真实模型跑 `--micro` 与 `--tasks`。
3. `./scripts/usage-report.sh bench-` 取数，填入上表。
4. `git add docs/experiments/runs/usage.jsonl docs/experiments/session-vs-workers.md` 并提交。
