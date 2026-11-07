# 253 — B3：学习区（⌥L）改两行式，候选窗零改动

- 日期：2026-11-06　｜　批次：B3　｜　设计：`docs/design/l3-hint.md`
- 结论：学习区按评审稿落地；候选窗**一个像素都没改**；词组按输入码对应到字。

## 1. 改了什么

| 位置 | 之前 | 之后 |
|---|---|---|
| 学习区第一行 | `完整码 TKG   识别码G：横、左右`（码与说明挤一行） | `完整码 TKG` + 右侧 `简码 T`（或 `拆解待核验`） |
| 学习区第二行 | 字根格子（**识别码也混在格子里**） | 字根格子 + 右侧识别码两行：`识别码：横·左右结构` / `G` |
| 词组 | 需展开「逐字拆分」才看逐字 | 直接按输入码对应到字：`KWWL → 中K 华W 人W 国L`，其余进「逐字 ▸」 |
| 候选窗 | — | **零改动**（高度/配色/圆角/行为都不动） |
| 数据源 | D14（`ime_wubi_learning`） | 优先 `B0-runtime.tsv`（结构化，含简码/识别码/占位），缺失退回 D14 |

代码：`platforms/macos/Sources/CandidateWindow.swift`（`arrange` 重写）、新增
`platforms/macos/Sources/LearningHints.swift`；`build.sh` / `dev-preview.sh` 把
`data/generated/B0-runtime.tsv` 复制进 `Contents/Resources`。

## 2. 词组的"按码对应到字"

| 字数 | 取码规则 | 例（中华人民共和国 · KWWL） |
|---|---|---|
| 2 字 | 各取 2 码 | — |
| 3 字 | 前两字各 1 码 + 末字 2 码 | — |
| ≥4 字 | 前三字各 1 码 + **末字 1 码** | 中 K / 华 W / 人 W / **国 L** |

中间的字（民、共、和）不显示——它们不参与这个码，显示出来反而看不出拆字逻辑。

## 3. 实拍（离屏渲染，亮/暗各一遍）

`docs/design/learning-real-single.png`（你，含 `简码 WQ` + `识别码：捺·左右结构 / Y`）、
`learning-real-partial.png`（我，`？(N)` + 橙色「拆解待核验」）、
`learning-real-word.png`（中华人民共和国）、`learning-real-dark.png`。

- 单字与词组高度都是 **76 pt**（同构两行）；
- 展开「逐字 ▸」后仍受原有 428 pt 上限约束；
- 亮/暗对比度检查沿用既有断言（`minimumContrastForTesting`）。

## 4. 验证

- `platforms/macos/tests/test-wubi-learning.py`：测试夹具现在把 `B0-runtime.tsv` 放进
  `Resources/`，因此**同时覆盖 B0 路径**；资源缺失时退回 D14 的路径另有断言（学习区仍显示完整码）。
- `make verify` PASS；离线回归 **62 文件 / 327 例 PASS**；`dev-preview --smoke-test` PASS。

## 5. 还没做

- **装机包**上的性能与内存实测（`perf-session` 三段 + `soak`）——要等 1.2.0 候选包，属 B5 收口。
- 学习区在**词组展开**时的逐字项仍未用 B0 的结构化字根（沿用 D14 的 `roots`）；若 B0 覆盖更好，
  下一步把展开项也接到 `LearningHints`。

## 6. 关联

ADR-311、`docs/design/l3-hint.md`、`docs/迭代计划-1.2.0.md`、报告 252。
