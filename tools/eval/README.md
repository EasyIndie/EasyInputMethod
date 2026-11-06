# 候选排序评测（B 批基线）

> 目的：把"打单字不跟手"这类主观描述变成**可复跑的数字**，让 ADR-304（简码入表 + 位次上移）
> 的收益和副作用都能对账。基线必须在改排序**之前**采集——`baselines/1.0.2-build37.json` 就是那条线。

## 1. 一键跑

```sh
make eval-candidates                       # 结果打到终端，并写 tools/eval/last-run.json
make eval-candidates EVAL_JSON=/tmp/x.json # 指定输出
```

默认样本 `tools/eval/samples.tsv`、码表 `data/generated/wubi86-core.tsv`。
纯本地、不联网、不读用户配置、不写 `~/Library`。

## 1.1 二级简码「选谁」的来源对照

```sh
python3 tools/eval/compare-level2-sources.py     # 全码权重 vs 通用字频，各生成一版临时表对比
```

结论与决策见 `docs/reviews/237-level2-shortcode-source-decision.md`：两种来源在 624 个码位里只差 5 个生僻字，
因此采用现有全码权重（少一个依赖、与码表同源、可复现）。

## 2. 样本集

`tools/eval/gen-samples.py` 生成，**勿手改** `samples.tsv`（要改进就改生成器，样本集一改等于换考卷）。

| 类别 | 条数 | 键盘输入 | 意图来源 |
|---|---|---|---|
| `jianma1` | 25 | 1 字母（五笔86 一级简码） | 公开标准键位表 |
| `jianma2` | 40 | 2 字母（**官方二级简码表** D17-bis 等距取样） | 官方简码表 |
| `prefix2` | 30 | 2 字母（该字全码前两位） | 高频单字（原 jianma2 考卷，报告238 改名） |
| `single` | 50 | 4 字母全码 | `pinyin-chars.tsv` 单字词频（jieba，D10） |
| `word2` | 25 | 4 字母词码 | `input-quality.tsv` **holdout**（ADR-227） |
| `word2v` | 30 | 同上 | 同上 **validation**（数量补足，单独统计） |
| `word34` | 23 | 4 字母词码 | 同上，holdout → validation → train 取够 |
| `sentence` | 17 | 分段 `usrh\|ceid\|irlg` | 同上，按码表贪心切词 |

**关键设计：意图来源与排序权重不同源。** 单字用 jieba 词频（D10），码表排序用 WindInput 权重（D3）；
若两者同源，"首选率 100%"就只是自证。

## 3. 指标口径

| 指标 | 定义 |
|---|---|
| `hit%` | 整条样本被完整命中的比例（分段样本要求每段都命中） |
| `first%` | 命中的样本里全部段落都是首选的比例 |
| `avgPos` | 命中候选的平均位次（0 = 首选）；未命中不计入 |
| `keys/sample` | 按键数 = 本段字母数 + 确认键（四码唯一自动上屏豁免）+ 非首选时 1 个序号键 |
| `pages` | 累计翻页数 = 位次 / 每页候选数（9） |

## 4. 对比流程

```sh
make eval-candidates EVAL_JSON=/tmp/after.json
python3 - <<'PY'
import json
a = json.load(open('tools/eval/baselines/1.0.2-build37.json'))['metrics']
b = json.load(open('/tmp/after.json'))
for cat in sorted(set(a['categories']) | set(b['categories'])):
    x = a['categories'].get(cat); y = b['categories'].get(cat)
    if not (x and y): print(f"{cat}: 仅一侧存在"); continue
    print(f"{cat:<10} first {x['firstChoice']:>3}→{y['firstChoice']:<3} "
          f"pos {x['meanPosition']:.2f}→{y['meanPosition']:.2f} "
          f"keys {x['meanKeystrokes']:.2f}→{y['meanKeystrokes']:.2f}")
PY
```

判定口径（`docs/MVP后执行计划.md` §4）：`hit%` / `first%` / `keys` 不得劣化，`jianma1` 的 `first%`
与 `keys` 必须明显改善；否则不发布。

## 5. 基线（1.0.2 / build 37；240 条新样本的基线见 `baselines/1.1.0-build38.json`）

```
category     samples   hit%  first%    avgPos keys/sample
jianma1           25   56.0    32.0      1.14       2.24
jianma2           30  100.0    93.3      0.07       3.07
single            50  100.0   100.0      0.00       4.46
word2             25  100.0   100.0      0.00       4.16
word2v            30  100.0    93.3      0.07       4.40
word34            23  100.0    87.0      0.17       4.35
sentence          17   70.6    70.6      0.00      11.00
ALL              200   92.0    85.5      0.11       4.47
```

读法：单字/词组在同码内排序已经不错（`first%` 87–100%），**真正的缺口是一级简码**
（只有 32% 首选、44% 连命都命不中）——这正是 ADR-304 要补的那一段，也和报告 224 的诊断一致。
`sentence` 的 `hit%` 70.6% 多半来自码表没收录的切词段，属于数据覆盖问题，不是排序问题；
1.1.0 判定时按"不得劣化"处理，不作为改善目标。
