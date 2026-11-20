# 329 — 1.3.3 / build 46 候选真机验收（air，2026-11-20）

> 候选来自 main `ee2f589`（PR #347）的 `macOS Acceptance Package` run `44697158179`。
> 本版四件改动：候选窗残留修复（报告 327）、练习题库延迟构造（ADR-386）、footprint 采样协议（ADR-385）、学习表补 `坶`。

## 1. 候选身份

| 项 | 值 |
|---|---|
| 提交 | `ee2f589d11fb93ef971d161a06759b288a53a036` |
| 版本 / 构建 | 1.3.3 / 46 |
| ZIP（universal） | `c01a323118df2886a2927a95e15c05bec9e5150ebc6febe4d6cdfdc1a76f2cae` |
| 包内宿主执行 SHA-256 | `56c46afec889bc75df63cae1bf52125712b0e428ffd0c5709ab7db4a1ed1b193` |
| 签名 | Developer ID（Zhizhou Wang / 2N62934Y28），公证通过 |

## 2. 装机

`make macos-fast-reinstall … --stop-host --keep-data`：装后执行 SHA = 包内，`config.toml` `52af2b90…` 未变。

> ⚠️ 装机时发现：`--stop-host` 那次没杀掉 16:10 起的老宿主（`pgrep -x Lampyris` 返回 2 小时前的 pid，
> 跑的还是旧镜像）。**装机后必须回读 `ps -o etime`**：宿主 uptime 远大于装机时间就说明在跑旧进程，要 `kill` 后由
> IMK 重新拉起（本轮后续所有测量都在 `kill` + 重新拉起之后）。

## 3. 面板残留复现路径（1.3.3 判决性验证）

| 步骤 | `cgwins 萤火虫` |
|---|---|
| 组合态 `khk` | `layer 101`（面板出现是正常的） |
| **切到 ABC 后 0.6 s** | **`{"windows":[]}`** |
| 切走后 3 s | `{"windows":[]}` |

结论：与报告 327 §8 一致，**修复在 1.3.3 仍然成立**。

## 4. 练习题库：进程内证据 + 真机观察

**进程内（`platforms/macos/tests/wubi-learning.swift` 的 `lazy-bank` 断言）**：七个题型全建完的常驻增量
**5.86 → 1.95 MiB**，建库期间**零解析**（只解析被访问的那一条）。

**真机（本机，`⌥K` 开练习窗口）**：

| 时刻 | host footprint |
|---|---|
| 冷启动（未开练习） | 36.8 MiB |
| 打开练习窗口 | **53.5 MiB（+16.7）** |
| 关闭练习窗口 | 53.8 MiB（**不回落**） |
| 重新打开 | 54.0 MiB |

结论与处置：

- 题库那份重复数据确实收回了（1.3.2 若开练习预计 ≈57.5 MiB，本版 53.5，差 ≈4 MiB 与 5.86−1.95 吻合）；
- 但**练习窗口本身还有约 15 MiB 的常驻开销**（vmmap 区域表显示 `mapped file` +5.5、CoreAnimation +1.3、CG Image +0.7 等，
  余下不在 `-summary` 明细里），与题库无关，**列为 P1-M2 跟进**（不在 1.3.3 范围）；
- 这解释了 ADR-385 为什么把绝对值限定在冷启动窗口：用户开过练习之后，footprint 会长期高于 44 MiB 粗粒度顶。

## 5. 整套验收（`make macos-acceptance-full`，干净宿主）

| 项 | 结果 |
|---|---|
| 预检 | 9/9 ok，`exec_sha = 56c46afe…` |
| auto-acceptance | **PASS**：p95 **6.49 ms**（限 16）、360 键、`max_connections 0`、冷首键 p95 24 ms（单独披露、不进门禁） |
| footprint（ADR-385 协议） | **40.4 / 40.4 / 40.4 MiB**，离散 0.0，`uptime 8 s`（冷窗口内）≤ 44 |
| 质量样本 | **PASS**（31 行全 PASS、0 FAIL） |
| memory-gate | **PASS**：`heap live` **21.7** / 24 |
| 总结果 | **PASS** |

对照：同一台机器、开过练习窗口的宿主上跑同一脚本，footprint 读到 56.3（`uptime 189 s`）→ FAIL。**这不是回归**，
是 §4 的窗口开销 + 「关闭不回落」，已按 ADR-385 的口径记在案。

## 6. 状态

- 候选通过；1.3.3 可以发布（tag / Release / 站点）。
- 遗留：P1-M2「练习窗口的 ~15 MiB 常驻」——需要单独归因（窗口/图层/字体/数据），并给出「关闭后回落」的方案。
