# 328 — 练习题库延迟构造：把 footprint 的 +11 MiB 收回去（ADR-386）

> 触发：报告 326 发现宿主**冷启动 35.9 MiB → 用 1.5 h 47.0 MiB**（+11.1），顶到 ADR-379 的 44 MiB 粗粒度顶；
> P1-M1 的触发条件（footprint 再涨 >2 MiB）因此命中。本报告记录归因、改法与实测。

## 1. 归因：同一份数据存了两遍

`Practice.bank(kind:)` 给每个字建一条 `PracticeQuestion`，而这条记录把学习区资源里解析出来的东西**又存了一份**：

```swift
struct PracticeQuestion {   // 改前
    let kind, char, code: String
    let roots: [(glyph: String, key: String)]                       // 3–4 个元组
    let recognition: (letter: String, stroke: String, structure: String)?
    let short1, short2, short3: String?
}
```

七个题型各建一份题库，合计 12,000+ 条；词组题库更贵——把 5.2 万行码表一次性 `split` 成数组再排序。

分题型的常驻增量（`wubi-learning.swift` 里逐题型采样，改前）：

| 题型 | 条数 | 累计 footprint 增量 |
|---|---|---|
| 字根 | 147 | 0.14 MiB |
| 一级 / 二级 / 三级简码 | 25 / 598 / 3,362 | 0.17 / 0.23 / 0.48 |
| 完整码 | 5,021 | 0.64 |
| **词组** | 800 | **5.80** |
| 识别码 | 2,738 | 5.80 |

也就是说：**5.2 MiB 在词组解析，剩下的在"每题存一份完整解析"**。

## 2. 改法（ADR-386）

1. `PracticeQuestion` 只存「题型 + 字」；`code` / `roots` / `recognition` / `short1..3` 变成计算属性，
   经 `LearningHints.hint(for:)` 取（那条路径本来就有 64 条缓存、按需解析）。字根题与词组题的答案不在学习表里，仍固定存放。
2. 出题筛选不解析整行：新增 `LearningHints.slots(for:)`，**按字节**判断该字的字根/识别码/一·二·三级简码列是否非空。
3. 词组题库改成**逐行扫描 + 有界小顶堆**（只保留权重最高的 800 行），不再 `split` 整张表、也不留 5.2 万个 `Substring`。

## 3. 实测（同一台 air，同一份运行时资源）

| 指标 | 改前 | 改后 |
|---|---|---|
| 全部题库建完的常驻增量 | **5.86 MiB** | **1.95 MiB** |
| 词组题库增量 | 5.80 | 1.30（主要是读 714 KB 码表时的短暂页） |
| 建库时解析的学习区条目 | 5,021 条（全部） | **0**（只在显示某题时解析那一条） |
| 题库条数 | 5,021 / 3,362 / 598 / 25 / 2,739 / 147 / 800 | 完全一致 |

断言已进离线回归（`platforms/macos/tests/wubi-learning.swift`）：

- 建 `完整码`/`三级简码` 题库时 `materializedCount` 不变（零解析）；
- 访问第一题只让 `materializedCount` +1；
- 七个题型全建完的 footprint 增量 **< 3 MiB**；
- 题库总数 > 10,000，条数与改前一致。

## 4. 作用与边界

- **作用**：把长时使用后 footprint 的 +11.1 MiB 里的 **约 4 MiB**（改前 5.86 → 改后 1.95）直接收回去；
  配合 ADR-385 的采样协议，长时占用应回到 44 MiB 粗粒度顶以下有余量的位置。
- **不改**：出题权重、判分、进度文件格式、题型解锁阶梯；`Practice.bank` 的返回类型与条数不变。
- **不做**：不把整张学习表缓存起来（缓存上限仍是 64 条）——那等于把这次省下的内存又花回去。

## 5. 复核

```sh
python3 platforms/macos/tests/test-wubi-learning.py   # 含 lazy-bank 断言
make macos-offline-tests                              # 72 文件 / 360 例
make verify                                           # 810 产物零网络符号
```
