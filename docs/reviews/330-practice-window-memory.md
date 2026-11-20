# 报告 330：练习窗口的内存账（P1-M2）与 1.3.4 候选验收

- 日期：2026-11-20
- 结论：**P1-M2 已修**（关窗即拆 + 键位图延迟构造），**旧验收口径（关窗后 footprint 回落）不成立**，
  改成状态判据（ADR-387）。1.3.4 候选 `1.3.4 / 47` 真机验收 **PASS**。
- 关联：报告 326（footprint 采样协议）、报告 328（题库延迟构造）、报告 329（1.3.3 验收）、ADR-385/386/387。

## 1. 候选身份

| 项 | 值 |
|---|---|
| 版本 / 构建 | **1.3.4 / 47** |
| 提交 | `70854861d2521bc0c09feb38ec754afe44433b94`（main，PR #350 合并后） |
| Acceptance run | `44730915189` success |
| ZIP（universal） | `3acfcc4363dce20413a56902078cb57a9c95de6de4a66d340123d0b8485807e4`（= `.sha256`） |
| 包内宿主执行 SHA-256 | `70ab3d673c1beda1983d5138823ce10f12efdd7fa2e33b8ebe6f062f505519da` |
| 签名 / 公证 | `spctl` → `Notarized Developer ID`，`Developer ID Application: Zhizhou Wang (2N62934Y28)` |
| 装机 | 2026-11-20 20:2x，`make macos-fast-reinstall … --stop-host --keep-data`；装后回读 `ps -o etime` = 11 s（新宿主）、config `52af2b90…`、`practice.tsv` 保留 |

## 2. 问题归因（1.3.3 真机：38.8 → 55.7 → **55.8**）

两层原因，缺一层都修不掉：

1. **窗口只藏不拆**：`PracticeWindow.shared` 建一次窗口后一直持有，`isReleasedWhenClosed = false`，
   关窗 = `orderOut`。控件树、图层、窗口后备存储全留在输入法进程里。
2. **默认隐藏的键位图面板被预支**：`KeymapPanelView`（25 键 + 字根 + 口诀）在 `init` 阶段就构造并排过版，
   而它默认是隐藏的。

## 3. 实测（1.3.4，air / arm64，重启宿主后 11 s 起测；`footprint -p` 三连一致）

| 状态 | footprint | 相对冷启动 |
|---|---|---|
| 冷启动（未开过练习） | **35.4 MiB** | — |
| 打开练习（**不点键位图**） | **51.1** | **+15.7** |
| 再点「键位图」 | **70.2** | +34.8（面板 **+19.1**） |
| 键位图关掉（面板仍活着但隐藏） | 62 | 面板隐藏回收 ~6–8 |
| 关窗 | **58.1** | +22.7（关窗回收 ~8，窗口那 ~16 是 AppKit 缓存） |
| 反复开/关 ×3 | 开 61 / 关 59，**三轮一致** | 无增长 |

`vmmap -summary` 归因（dirty）：键位图那 19.1 里，`IOSurface` **+5.0**（整块面板的图层后备存储）、
`IOAccelerator (graphics)` **+2.3**、其余在 malloc/字体与文本布局缓存；关窗后 `IOSurface` 归零，
`IOAccelerator` 留在原处（GPU 侧缓存不归进程管）。

对照 1.3.3（报告 329）：冷 38.8 → 开练习 55.7 → 关窗 55.8。**1.3.4 的收益是「不点键位图就不付那 19 MiB」
和「关窗真的把窗口/面板放掉」**，而不是让 footprint 回到冷启动。

## 4. 为什么「关窗后 footprint 回落」做不到

`phys_footprint` 数的是**脏页**。关窗把对象交还分配器后：

- malloc 只是 `madvise(MADV_FREE)` 标记「可复用」，页仍然算在 footprint 里（要等系统压力或复用才消失）；
- AppKit 的 CJK 字形缓存、文本布局缓存、AttributeGraph 是**进程级常驻**，从不逐窗回收。

离线harness（-O，进程内 `ri_phys_footprint`）里这一条看得最清楚：开窗 +17.0、关窗只回落 0.3–0.8。
所以 ADR-387 把验收改成三条**状态**判据（ADR-385 的教训：门禁必须是状态，不是噪声）：

1. 开窗默认**不**构造键位图面板；
2. 关窗后窗口与面板**必须**被释放（`windowForTesting == nil`、`keymapPanelBuilt == false`）；
3. 反复开/关**不增长**（实测 +0.3～0.4 MiB/轮，四轮累计 < 1 MiB）。

44 MiB footprint 硬顶与 `heap live ≤ 24 MiB` 一个都没调（ADR-338/379），44 MiB 仍只适用冷启动窗口。

## 5. 改动

`platforms/macos/Sources/PracticeWindow.swift`

- `windowWillClose` → `dismantle()`：置空 `onKey`/`delegate`/`toolbar`，`scrollView.documentView = nil`，
  `contentView = nil`，拆掉内容视图树与键位图面板，`window = nil`；保留进度、题库、题型位置与显示偏好。
- `KeymapPanelView` 改为**懒构造**（`keymapPanelStorage` + `keymapPanelBuilt`）：第一次点工具栏「键位图」才建，
  关窗一并释放；「是否显示」与口诀开关跨窗口保留，重开时按原样重建。
- 打字闪烁、换题高亮全部走 `if keymapPanelBuilt` 守卫，**不会为了闪烁把 19 MiB 建出来**。
- 三个测试钩子：`prepareForTesting` / `windowForTesting` / `closeForTesting` / `keymapPanelBuiltForTesting`。

`platforms/macos/tests/{practice-window-memory.swift,test-practice-window-memory.py}`（新增离线契约）

- 冷态 → 开（断言面板未建）→ 点开键位图（断言已建）→ 关（断言窗口与面板均释放）；
- 重建后 `layoutProblemsForTesting` 无越界/重叠（重建路径没坏）；
- 四轮开关净增 < 2 MiB；打印 MiB 供报告引用，**不做跨机器 MiB 门禁**。

## 6. 真机验收（候选 `70ab3d67…`）

功能（练习窗口，真宿主）：

| 项 | 结果 |
|---|---|
| ⌥K 开窗 | PASS（`windows` 见「萤火虫 · 练习」，AX 有题型段、作答框、`下一题 →`、`键位图`） |
| 点「键位图」 | PASS（AX 出现「五笔 86 · 25 键字根分布」「五笔 86 字根键位图」；面板按需构造） |
| 关窗 | PASS（`cgwins 萤火虫` → `{"windows":[]}`） |
| 重开 ×3 | PASS（每次都正常出内容，版式无异常；footprint 平台期） |
| 数据 | PASS（`--keep-data`：`practice.tsv` 197 B 保留、config `52af2b90…` 未变） |

整套 `make macos-acceptance-full`（`OUT=/tmp/acc-1.3.4`，宿主 uptime 169 s，冷窗口内）：

| 项 | 结果 |
|---|---|
| preflight | `ready:true`，`exec_sha` = `70ab3d67…`（= 装机包内执行） |
| auto-acceptance | **PASS**（Shift 中/英、⌥P 标点、⌥F 全角、⌥T 繁简、⌥M 模式 8 项） |
| 键入延迟 | 30 轮 p95 中位 **7.52 ms**（单轮最高 23.45 ms 出现在标点轮的首键冷态；单列披露 冷首键 p95 24.4 ms） |
| footprint | **42.2 / 42.2 / 42.2 MiB**（离散 0.0，`footprint_cold_baseline: true`，uptime 169 s） |
| heap live | **21.6 / 21.7 / 24 MiB** PASS |
| 网络 | 499 采样、**0 连接** |
| 质量样本 | **31/31 PASS**、0 FAIL |
| memory-gate | PASS（`private_committed` 39.2–39.3） |
| 总结果 | **PASS** |

## 7. 遗留与教训

- **遗留**：练习窗口的 ~16 MiB 是 AppKit 字形/布局/AttributeGraph 的进程级常驻，**没有**在不砍功能的前提下收回的办法。
  它只在用户真的开过练习后存在，且 44 MiB 门禁只看冷启动窗口（ADR-385），因此不再当一个"待办"挂着。
- **教训 1（探针）**：第一版 harness 没跑 run loop、没加 `autoreleasepool`，量出「每轮 +2.8 MiB」的假泄漏。
  加 `autoreleasepool` + 转 0.35 s run loop 后立刻变成平台期——**量 AppKit 内存必须让它把延迟释放跑完**。
- **教训 2（对照）**：离线 harness 里键位图只值 7.0 MiB，真机上值 **19.1**（2× Retina 图层 + IOSurface）。
  离线的绝对值不能当真机预算，只能当趋势与契约。
