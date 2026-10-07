# 结论：一个主会话 vs 一堆无头 worker

> 数据：`docs/experiments/runs/usage.jsonl`（`scripts/usage-report.sh` / `usage-compare.sh`）。
> 复现：`scripts/bench-session-vs-workers.sh`。**本文件是"活"的**，随数据更新。

## 环境

- 模型：`deepseek-v4-flash`（provider `cc-switch-deep-seek`，1M 上下文）
- ⚠️ provider **未配置计价** ⇒ `cost`=0。用 token 口径：`input`=全价，`cacheRead`=命中缓存（DeepSeek 量级 ≈0.1×）。

---

## 结果一：固定开销（微基准）

| 指标 | micro-fresh | micro-reuse |
|---|---|---|
| input（全价） | 3,816 | 232 |
| cacheRead | 512 | 4,096 |
| cacheHitRate | 11.8% | 94.5% |

**每次调用固定开销 ≈ 4.3k tokens**；前缀缓存**跨会话共享** → 同模型 + 同前缀 + 在 TTL 内，**开新会话 ≠ 冷启动**。

## 结果二：真实任务卡 A/B（T-M1-01 → T-M1-02，n=1）

两臂都成功、产出等价。

| | 总 tokens |
|---|---|
| A 每卡新 worker | **521,379** |
| B 持久会话 | **918,377**（+76%） |

原因：持久会话把任务一整段历史带进任务二（任务二 `cacheRead` 3.4×）。
**关键**：这两个任务卡的依赖是**"落在磁盘上"的**（后卡可直接读前卡建的 crate）→ 属"弱依赖/可重派生"。

## 结果三：独立任务工作负载（N=5，取中位数）

`--workload independent`（3 条互不相关、读不同文档的 prompt）

| | 每轮 tokens（5 次，已排序） | 中位数 |
|---|---|---|
| fresh | 32,705 / 37,474 / **37,908** / 38,307 / 38,630 | **37,908** |
| reuse | 31,223 / 42,127 / **43,618** / 43,768 / 50,935 | **43,618**（+15.1%） |

**分布重叠** → 结论是"**fresh 略优或持平，reuse 无收益**"，而非"fresh 必胜"。

## 结果四：强依赖序列工作负载（N=5，取中位数）

`--workload dependent`（后一条 prompt 必须用到前一条的产出）

| | 每轮 tokens（5 次，已排序） | 中位数 |
|---|---|---|
| fresh | 120,260 / 165,135 / **230,933** / 300,154 / 506,395 | **230,933** |
| reuse | 39,367 / 45,356 / **51,913** / 58,233 / 61,560 | **51,913**（**−77.5%**） |

**分布不重叠**（fresh 最小 120k > reuse 最大 61.5k）→ **reuse 稳定快 4.4×**，且方差远小。
原因：强依赖下，fresh 每个 worker 都要**重新读大文档、重新推导**上游结论；reuse 只付一次。

---

## 综合结论

**决定因素不是"批量大小/缓存冷热"，而是"任务间依赖是强还是弱"。**

| 依赖类型 | 特征 | 推荐 | 依据 |
|---|---|---|---|
| **弱依赖 / 独立** | 后一任务能从**磁盘产物**重新派生（读文件即可） | **每卡新 worker** | 结果三、二 |
| **强依赖** | 后一任务需要**上一任务的在上下文中的推理状态**（无法从磁盘完整恢复） | **同一会话 reuse** | 结果四（快 4.4×） |

### 怎么判断强/弱依赖（可操作）

对下一张任务卡问一句：**"不给我上一任务的对话，只给我仓库里的文件，我能完整做到吗？"**

- **能** → 弱依赖 → **新 worker**（我们的任务卡按设计都写了"涉及文件/验收"，故**默认即此类**）。
- **不能** → 强依赖 → **复用同一会话**。典型场景：
  - 迭代打磨同一个东西（"再改改你刚写的"）
  - 多步调试（"根据刚才的报错继续修"）
  - 会话里做过、未落盘的决策

### 对萤火虫开发流程的落地约定

1. **默认：一张任务卡 = 一个新 worker**（上下文有界、结果稳定）。
2. **拆分任务卡时，尽量让每张卡自包含**（写清涉及文件 + 验收）→ 保持弱依赖 → 可并行、可重派。
3. **只有"必须接着上一卡上下文"的序列**才用 `--reuse <同名>`（一轮迭代一个会话）。
4. **worker 只回短摘要**（已有约定），避免把它的上下文带回主会话。
5. 别用 `cacheHitRate` 当 KPI；看**每轮总 tokens**，且**看中位数**不看单次。

---

## 注意事项

- `cache×0.1` 为**假设**，非官方报价；`cost` 字段不可用。
- 结果三（独立）两臂**分布重叠**，只能说"fresh 不差、reuse 无益"；结果四（强依赖）**分布不重叠**，结论强。
- 工作负载是"读文档+分析"型；代码型任务的绝对量级更大，但**机制一致**。

## 复现

```bash
PI_CMD=echo ./scripts/bench-session-vs-workers.sh --micro                       # 管道自检
./scripts/bench-session-vs-workers.sh --micro --model deepseek-v4-flash
./scripts/bench-session-vs-workers.sh --workload docs/experiments/workloads/independent.txt --repeat 5 --name independent
./scripts/bench-session-vs-workers.sh --workload docs/experiments/workloads/dependent.txt   --repeat 5 --name dependent
./scripts/usage-compare.sh independent
./scripts/usage-compare.sh dependent
```
