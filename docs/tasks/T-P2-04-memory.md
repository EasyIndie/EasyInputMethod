# T-P2-04：引擎常驻内存优化（macOS 27 / arm64 宿主 ≤ 30 MB）

- **状态**：✅ 完成（2026-10-11；ADR-082；宿主全新 43.8 → **23.3 M**，验收 ⑪ 达标）
- **模型建议**：**pro**（跨表数据结构选型 + 内存/时延权衡 + 必须先写 ADR；机械基准部分可 flash）
- **前置**：ADR-060（词典结构）、[`MVP-05.md`](MVP-05.md) §2.4（取证）、[`技术方案.md`](../技术方案.md) §12；**先写 ADR**（改数据结构属设计变更）
- **目标**：把宿主物理足迹降到 DoD「常驻内存 ≤ 30 MB（不含 mmap）」——macOS 27 / Apple Silicon 上当前为 **43.8 MB**；**或**经 ADR 论证后修订门槛。

## 背景（机器 B 实测，2026-10-11）

- 宿主 `vmmap` 物理足迹 **43.8 MB**；同机最小 Swift AppKit 基线仅 **7.7 MB**；`run-perf.sh` 引擎峰值 RSS **23.56 MiB**。
- 加载 4 个 TSV 共 **2.17 MB / 145,758 条**（五笔 37,828 · 拼音字 53,092 · 拼音词 12,405 · 简繁 42,433）→ malloc **319,890 节点 / 26.7 MB**（约 11× 膨胀）。
- 归因：`ime-table`（`Vec<(String, Vec<Entry>)>`）、`ime-pinyin`（多张 `HashMap<String,…>` + 反查表）、`ime-ffi` 简繁（`HashMap<String,String>`）均逐条 `String` 分配，无 interning / 紧凑编码。
- **非本版本回归**：简繁表在机器 A 那次 17.5 MB 的构建（`7ea5a53`）即已存在；差异主要来自 macOS 27 / arm64 的计量与架构。机器 A（macOS 13 / Intel）曾报 ~17.5 MB。

## 步骤（草案，实施前细化并**先写 ADR**）

1. **先写 ADR**（编号递增）：明确内存目标、数据结构选型与取舍。候选方向：
   - 字符串 interning / 共享 `Arc<str>`（去掉逐条重复的拼音、词文本）；
   - 紧凑排序数组（ADR-060 既定方向）替代 `HashMap`；
   - 简繁表**按需懒加载**（默认 `simplified` 时完全不加载，预计省 ~6–7 MB）；
   - 二进制 / mmap 仅在 ADR-060 的触发条件下评估（注意「不含 mmap」口径）。
2. **先立基线再改**：给 `run-perf.sh` 增加**常驻内存**指标（引擎 RSS + 宿主 `vmmap` footprint），固定机型与 commit，保证可复现对比。
3. **逐表量化后改**：分别测 4 张表各自增量，优先性价比最高者（预计「简繁懒加载 + interning」收益最大）。
4. **回归**：按键 p95 不退化（当前 0.555 ms，门槛 16 ms）、功能与候选排序不变；`make verify` + 预览冒烟全绿。
5. **两机复核**：macOS 27 / arm64 与 macOS 13 / Intel 都测，记录到 [`MVP-05.md`](MVP-05.md)。

## 验收

- macOS 27 / arm64 宿主物理足迹 **≤ 30 MB**（`vmmap -summary <pid> | grep 'Physical footprint'`）；**或** ADR 修订门槛并附两机证据；
- 按键 p95 < 16 ms 不退化、`make verify` 全绿、预览冒烟含内存断言；
- 若采用懒加载 / 二进制格式：首用延迟可接受，且有测试覆盖。

## 铁律提醒

- 核心 `#![forbid(unsafe_code)]`（仅 `ime-ffi` 例外）；
- 任何新数据 / 格式先登记 `数据来源与许可.md` + `data/sources.toml`；
- 配置只走 `ime-config`；核心不联网；
- **改数据结构 = 设计变更** → 先写 ADR，再动代码；文本 TSV 仍是唯一真值（ADR-060）。

## 禁止

- 不为省内存牺牲功能 / 候选质量；不引入未登记的预编译二进制数据；
- 不做与内存无关的重构（一次只做一件）。

## 结果（已实现）

- **简繁懒加载**（`ime-ffi`）：默认不加载 `variant-s2t.tsv`，首次切繁体才解析。
- **`ime-table::Table` 紧凑数组**：`code`/`text` 各一段连续字节缓冲 + 偏移，候选扁平存储；新建 `crates/ime-ffi/examples/mem_probe.rs` 作为稳态基线。
- **设置面板关闭即释放视图树**（降低驻留节点）。
- 实测（机器 B，macOS 27 / arm64）：引擎稳态 五笔 **2.19 MiB** / 三表 **6.73 MiB**（简繁懒）；宿主全新 **23.3 M**（旧 43.8 M）；`run-imk-acceptance.sh` **14/14**（⑪ 23.3M ≤ 30M）。
- 遗留：打开偏好设置面板会临时抬升 ~15M（macOS 27 AppKit/SwiftUI 内部，非我们的数据），已记入 `MVP-05.md` §2.4。

## 参考

- [`docs/tasks/MVP-05.md`](MVP-05.md) §2.4、[`docs/技术方案.md`](../技术方案.md) §12、ADR-060、[`docs/reviews/007-ux-and-tech-debt.md`](../reviews/007-ux-and-tech-debt.md)、`HANDOFF.md` §5 MEM-1。
