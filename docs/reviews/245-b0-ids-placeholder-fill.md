# 245 — 用 IDS 填占位字根：能补 23 条，剩下的要靠字形库

- 日期：2026-11-06　｜　关联：报告 240/241/242/243/244、ADR-189/309
- 数据：**新增 D19 `yi-bai/ids`（MIT）**，`data/sources/fetch-ids.sh`（2 MB，下载不入库）
- 产物：`modules/hanzi-structure/`（schema **v5**）

## 1. 做了什么

v4 之后还有 **272 条** `partial`，病因只有一个：`components` 里有 `null` 占位（字根字形未识别）。
这轮把 IDS 接进来，在**严格条件下**用 IDS 叶子替换占位：

1. IDS 叶子数 == 组件数；
2. 已知位字形一致（或键位一致），否则整条不动；
3. 填入字形的键位（D14 有则查）必须等于码位，否则不填。

宁可不填，也不猜。

## 2. 结果

| 指标 | v4 | v5 |
|---|---|---|
| `full` | 714 | **737**（+23） |
| `partial` | 278 | **255** |
| 含占位组件 | 272 条 | **249 条** |
| 有 IDS 的条目 | — | **982 / 1000** |
| 识别码可解释 | 622 | 622 |

新增两个字段：

- `ids`：IDS 分解序列（如 `⿰禾口`），给"结构/分量"提供独立参考；
- `idsStructure`：**IDS 口径**的三分类结构。与识别码结构在 619 条可比条目上一致 **559 条（90.3%）**，
  不一致仍按 ADR-309 归档为口径差异（五笔为准），**不覆盖**识别码结论。

样例：

```
在 「dhfd」｜字根：𠂇(d) 丨(h) 土(f)｜3 个字根不足四码：末笔横 + 结构杂合 ⇒ 识别码 d
是 「jghu」｜IDS ⿱日𤴓（上下，参考）｜字根：日(j) 一(g) ？(h)｜参考识别码 u
```

## 3. 为什么只补了 23 条（诚实的天花板）

对 272 条占位条目逐条检验 IDS 能否给出对应分量：

| 情况 | 数量 | 说明 |
|---|---|---|
| IDS 无该字 | 3 | 全 CJK 覆盖 102,033 行仍有缺口 |
| IDS 叶子数与组件数**不同** | 220 | IDS 粒度粗（如 `是 = ⿱日𤴓`，我们按码位需要 3 个字根） |
| 叶数相同但已知位冲突 | 5 | 说明两家拆法不同，不能混用 |
| 叶数相同且已知位一致 | **44** | 上限 |
| 其中被"键位必须相符"再筛掉 | −21 | 填入字形在 D14 里的键与码位不符 → 说明该叶子不是这个字根 |

**结论**：IDS 是结构参考，不是字根字形库。要突破 220 条"粒度不同"，必须有一份
**能给出字根字形身份的来源**（字体 cmap 或字根字形库）——这属于 ADR-309 的 corpus 第二阶段，
不是靠现有数据能推出来的。

另外验证过一条错路：用 D2↔D3 的私有区对齐做"等价类传递"来推字形身份。
D3 对多个字根复用同一个占位码位，传递后会把上百个字根并成一类（实测标签冲突 5 类、单类含 100+ 字形），
**该方法不成立**，已记录在案，避免以后重复踩。

## 4. 边界

- IDS **不参与**识别码判定（五笔结构以识别码字母为准，ADR-309/报告 242）；
- IDS 不进输入热路径，只在 B0 讲解/查询路径使用；
- 产物仍**不含任何 PUA 字形**；`ids` 里允许出现扩展区汉字（如 𤴓），它们是正常 Unicode 字符。

## 5. 复现

```sh
./data/sources/fetch-ids.sh
cd modules/hanzi-structure
python3 tools/decode_pua.py --d2 ../../data/sources/wubi-lex-86.txt \
  --d3 ../../data/sources/windinput-wubi86-chaizi.txt --out corpus/pua-map.json
python3 tools/build_b0.py --codes ../../data/generated/wubi86-single.tsv \
  --radicals ../../data/sources/wubi-lex-86.txt \
  --d3 ../../data/sources/windinput-wubi86-chaizi.txt --pua-map corpus/pua-map.json \
  --readable-keys ../../data/learning/wubi86-readable-keys.tsv \
  --ids ../../data/sources/ids_lv1.txt \
  --short1 ../../data/sources/wubi86-level1-codes.tsv \
  --short2 ../../data/sources/wubi86-level2-codes.tsv \
  --pinyin ../../data/generated/pinyin-chars.tsv --limit 1000 --out-dir corpus
```
