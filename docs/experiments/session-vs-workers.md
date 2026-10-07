# 结论：一个主会话 vs 一堆无头 worker

> 数据来源：`docs/experiments/runs/usage.jsonl`（由 `scripts/usage-report.sh` 汇总）。
> 复现：`scripts/bench-session-vs-workers.sh`。**本文件是"活"的**，随数据更新。

## 环境

- 模型：`deepseek-v4-flash`（provider `cc-switch-deep-seek`，1M 上下文）
- ⚠️ 该 provider **未配置计价** ⇒ `cost` 恒为 0。**用 token 作口径**：
  `input` = 全价输入，`cacheRead` = 命中缓存的输入（DeepSeek 通常 ≈ 0.1× 价）。

---

## 结果一：微基准（固定开销）

`./scripts/bench-session-vs-workers.sh --micro`（prompt 仅"只回复两个字：收到"）

| 指标 | micro-fresh | micro-reuse-1 | micro-reuse-2 |
|---|---|---|---|
| totalTokens | 4330 | 4330 | 4341 |
| **input（全价）** | **3816** | **232** | **243** |
| cacheRead | 512 | 4096 | 4096 |
| cacheHitRate | 11.8% | 94.6% | 94.4% |

**观察**：每次调用固定开销 ≈ 4.3k tokens；冷 ≈ 3.8k 全价，热 ≈ 0.24k 全价 + 4.1k 缓存。
**前缀缓存跨会话共享** → 只要同模型 + 同前缀 + 在 TTL 内，**开新会话 ≠ 冷启动**。

---

## 结果二：完整 A/B（真实任务，n=1）

工作负载：T-M1-01（建 `wubi-encoder` crate）+ T-M1-02（键名字/成字字根编码）。
A 臂＝每卡新 worker；B 臂＝一个持久会话跑两卡。**两臂都成功**（4/4 exit=0，均 `make verify` 全绿，产出等价）。

| | T-M1-01 input | cacheRead | output | total |
|---|---|---|---|---|
| A · fresh | 22,244 | 340,608 | 9,087 | 371,939 |
| A · fresh | 10,626 | 131,968 | 6,846 | 149,440 |
| **A 合计** | **32,870** | **472,576** | **15,933** | **521,379** |
| B · reuse | 22,425 | 416,640 | 13,945 | 453,010 |
| B · reuse | 5,972 | 449,408 | 9,987 | 465,367 |
| **B 合计** | **28,397** | **866,048** | **23,932** | **918,377** |

| 指标 | A 每卡新 worker | B 持久会话 | B/A |
|---|---|---|---|
| 总 tokens | 521,379 | 918,377 | **+76%** |
| cacheHitRate | 93.5% | **96.8%** | 更高 |
| 加权成本（cache×0.1）| ≈80.1k | ≈115.0k | **+43.5%** |
| 加权成本（cache×0.1, output×1）| ≈96.1k | ≈138.9k | **+44.6%** |

### 关键发现：**reuse 更贵，不是更省**

- B 的 **cacheHitRate 更高（96.8% vs 93.5%）**，但 **总 tokens 却多 76%**。
- 原因：**持久会话把任务一的整段历史带进任务二** ——
  任务二在 B 里 `cacheRead = 449,408`（vs A 的 131,968，**3.4×**）；
  即任务二一开始就背着 ~400k tokens 的上下文，且**每一轮都要重发**。
- 缓存命中率高 ≠ 便宜：**被命中的 token 也是 token**（≈0.1× 价），量大了照样贵。
- 固定开销（~4.3k）在真实任务（10⁵ tokens 级）面前**可忽略**。

---

## 结论与决策规则（已用真实数据校准）

1. **默认：一张卡 = 一个新 worker**（上下文有界），**不要**用一个长命 worker 串跑不相关任务。
2. **`--reuse` 只在任务间存在真实依赖/迭代**（后一卡必须接着前一卡的上下文）时才用；
   否则它只会让上下文滚雪球。
3. **别用 cacheHitRate 当 KPI**，要看**总 tokens**（或加权成本）。命中率高可能只是"上下文太大"。
4. **并行**：互不相关的大卡可并行开**新鲜** worker（前缀缓存共享，各自上下文有界）。
5. **worker 只回短摘要**（本仓库 dispatch 脚本已如此要求），避免摘要意外把上下文带回主会话。
6. **换模型 = 缓存全灭**，是最贵的操作，避免频繁切。

> 一句话：**"每卡新 worker + 短摘要"是本项目的默认派发形态；持久会话是例外，不是默认。**

---

## 注意事项（caveat）

- n=1/臂，**方差大**：B 的 T-M1-01 输出 13,945 vs A 的 9,087（模型非确定性），
  部分差异来自"做得更多"。但 **reuse 携带上下文**这一结构效应是确定的（3.4× cacheRead）。
- 加权成本中的 `cache×0.1` 是**假设**（DeepSeek 量级），非官方报价；`cost` 字段不可用。
- 结论对"**互相独立**的任务"成立；**强依赖**的任务序列结论可能相反 → 需要专项实验。
- 想提高置信度：重复跑 N 次取中位数，或用 `--tasks` 换更小/更大的卡观察趋势。

## 复现

```bash
PI_CMD=echo ./scripts/bench-session-vs-workers.sh --micro          # 验证管道（不花 token）
./scripts/bench-session-vs-workers.sh --micro --model deepseek-v4-flash
./scripts/bench-session-vs-workers.sh --tasks "docs/tasks/T-M1-01.md docs/tasks/T-M1-02.md" --model deepseek-v4-flash
./scripts/usage-report.sh bench-
```
