# 结论：一个主会话 vs 一堆无头 worker

> 数据来源：`docs/experiments/runs/usage.jsonl`（由 `scripts/usage-report.sh` 汇总）。
> **本文件是"活"的**：每次跑完 `bench-session-vs-workers.sh` 后更新。

## 环境

- 模型：`deepseek-v4-flash`（provider `cc-switch-deep-seek`，1M 上下文）
- ⚠️ 该 provider 未配置计价 ⇒ `cost` 恒为 0。**用 token 作对比口径**（`input` = 全价，`cacheRead` = 命中缓存）。

## 结果一：微基准（冷启动固定开销）

命令：`./scripts/bench-session-vs-workers.sh --micro --model deepseek-v4-flash`
（prompt 仅"只回复两个字：收到"，故测到的几乎全是**每次调用的固定开销**）

| 指标 | micro-fresh | micro-reuse-1 | micro-reuse-2 |
|---|---|---|---|
| totalTokens | 4330 | 4330 | 4341 |
| **input（全价）** | **3816** | **232** | **243** |
| cacheRead | 512 | 4096 | 4096 |
| output | 2 | 2 | 2 |
| cacheHitRate | 11.8% | 94.6% | 94.4% |
| cost | 0（未配计价） | 0 | 0 |

### 观察

1. **每次调用的固定开销 ≈ 4.3k tokens**（系统提示 + 工具定义 + AGENTS.md 上下文）。
2. **首次（冷）≈ 3.8k 全价**；**之后（热）≈ 0.24k 全价 + 4.1k 缓存**，缓存命中率 ≈ 94%。
3. **前缀缓存跨会话共享**：`micro-reuse-1` 是新会话却已 94% 命中 —— 只要
   **同模型 + 同系统提示/工具 + 在供应商缓存 TTL 内**，**开新会话 ≠ 冷启动**。
4. 因此"开一堆 worker"的主要代价**不是**缓存，而是每个 worker 都要**重新装载任务上下文 + 重新探索代码**
   （这部分微基准测不到）→ 需完整 `--tasks` A/B 才能定论。

## 结果二：完整 A/B（含真实任务工作）

⏳ **未采集**。命令（花 token）：

```bash
./scripts/bench-session-vs-workers.sh --tasks "docs/tasks/T-M1-01.md docs/tasks/T-M1-04.md" --model deepseek-v4-flash
./scripts/usage-report.sh bench-
```

待填：

| 臂 | 任务数 | 总 tokens | 全价 input | cacheRead | cacheHitRate | 单任务均 tokens |
|---|---|---|---|---|---|---|
| A 每次新 worker (fresh) | | | | | | |
| B 持久会话 (reuse) | | | | | | |

## 结论（据微基准，暂定）

1. **固定开销 O ≈ 4.3k tokens/次**；热态下其中仅 ~0.24k 是全价 → **冷启动惩罚很小**，
   前提是**同模型、同前缀、快节奏连续跑**（缓存不失效）。
2. 缓存失效的场景（换模型 / 隔太久超 TTL / 改系统提示或工具）才会让每次新 worker 变贵 →
   **换模型 = 缓存全灭**，这是最贵的操作。
3. **决策规则**（待完整 A/B 校准）：
   - 任务净成本 `T >> O` → 开 worker 值得（且可并行，各自只多付 ~4.3k）。
   - `T ≲ O` → 留在主会话 / 一个持久 worker 里做。
   - 一批**互相独立**的小卡 → **一个持久 worker 串行**仍更稳（避免每卡重载任务上下文）。
   - 一批**互不相关且大**的卡 → 可并行开 worker（前缀缓存共享，过路费低）。

> ⚠️ 完整 A/B 才会揭示"reuse 会话把上一任务的历史带进下一任务"的**上下文膨胀成本**；
> 微基准只证明固定开销不大，不证明 reuse 总是更省。

## 复现方法

1. `PI_CMD=echo ./scripts/bench-session-vs-workers.sh --micro`（验证管道，不花 token）
2. `./scripts/bench-session-vs-workers.sh --micro --model deepseek-v4-flash`（本页数据）
3. `./scripts/usage-report.sh micro-` 取数。
4. 提交 `docs/experiments/runs/usage.jsonl` 与本文件。
