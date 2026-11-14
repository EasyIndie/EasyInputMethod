# 285 — D2 字形别名归一化（ADR-359）

> 2026-11-15。**只归一化同形替代，不放松标准；零降级。**

## 1. 问题

标准 v1 下 B0 1,000 字有 73 条 `positionMismatch`。逐条复查后发现三类成因：

| 成因 | 例子 | 处理 |
|---|---|---|
| D2 用假名/注音符号代汉字部件 | `リ`→`刂`、`ㄗ`→`卩`、`ク`→`夕` | **同形归一化**（本次） |
| D2 是视觉拆法，不是 86 根序 | `交` 记作 `亠八乂`，86 取 `六乂` | 保持 `partial`，不猜 |
| 占位 PUA 未识别 | `被` 的第 2 位 | 保持 `partial`，等许可数据 |

## 2. 做法

`modules/hanzi-structure/corpus/d2-glyph-aliases.tsv`（项目自编 CC-BY-SA-4.0）：

```text
alias  canonical  evidence
リ      刂        师 归 帅 狮 筛 蛳 岿（7 例）
ㄗ      卩        节 爷 卫 疖 栉（5 例）
ク      夕        久 玖 柩 灸 疚（5 例）
```

`build_b0.py --glyph-aliases` 在 `decode()` 的非 PUA 分支归一化；归一化后仍走标准 v1
的字根清单与码位校验，**别名本身不能把条目送进 `full`**。

同时：

- `彑` → X 加入标准字根清单（`彖 xeu`、`椽 sxey`、`喙 kxey`、`篆 txeu` 等 7 例）；
- `ノ` 作为撇笔画加入 `STROKES`，让「末位识别码槽是可读笔画」的判定覆盖 D2 的假名写法。

## 3. 结果

| 指标 | 前（报告 284） | 后 |
|---|---:|---:|
| B0 1,000 `full` | 916 | **928** |
| B0 1,000 `partial` | 80 | **68** |
| B0 1,000 `standardMismatchEntries` | 73 | **61** |
| B0 3,000 `full` | 2,578 | **2,614** |
| B0 3,000 `partial` | 268 | **232** |
| 运行时 `full` | 2,578 | **2,614** |
| 运行时体积 | 120,460 B | 120,785 B |

**零降级**：3,000 字运行时逐条比对，36 条全部 `partial → full`，没有 `full → partial`。

## 4. 逐条核验

| 字 | 全码 | 组件 | 依据 |
|---|---|---|---|
| 师 | jgmh | 刂 一 冂 丨 | 刂=j、一=g、冂=m、丨=h，四根无识别码 |
| 归 | jvg | 刂 彐 | 刂=j、彐=v + 识别 g（横+左右） |
| 节 | abj | 艹 卩 | 艹=a、卩=b + 识别 j（竖+上下） |
| 爷 | wqbj | 八 乂 卩 | 八=w、乂=q、卩=b + 识别 j（竖+上下） |
| 久 | qyi | 夕 乀 | 夕=q、乀=y + 识别 i（捺+杂合） |
| 仍 | wen | 亻 乃 | 亻=w、乃=e + 识别 n（折+左右） |
| 动 | fcln | 二 厶 力 | 二=f、厶=c、力=l + 识别 n（力末笔取折） |
| 功 | aln | 工 力 | 工=a、力=l + 识别 n |
| 劝 | cln | 又 力 | 又=c、力=l + 识别 n |
| 劲 | caln | ス 工 力 | ス=c、工=a、力=l + 识别 n |
| 伤 | wtln | 亻 𠂉 力 | 亻=w、𠂉=t、力=l + 识别 n |
| 绣 | xten | 纟 禾 乃 | 纟=x、禾=t、乃=e + 识别 n |

`力/刀/乃` 末笔按五笔 86 惯例取「折」；`ス` 是 86 标准变体（C 键），已在字根清单中。

## 5. 边界

- 归一化只接受**同形替代**；形近而非同一部件的 D2 字形不塞进清单。
- 剩余 232 条 partial 主要是 D2 视觉拆法、占位 PUA、以及 154 条 `unknown`（繁体/生僻，无许可拆字源）。
- 标准 v1 不承诺 100% 覆盖；本轮不引入任何新外部数据源。

## 6. 验证

- `validate_b0.py` PASS（1,000 条，full 无 `positionMismatch`）
- `test-hanzi-structure-b0.py` 新增 `test_d2_glyph_aliases_are_normalized`
- `make macos-offline-tests`、`make verify`

## 7. 关联

ADR-359、报告 284、`docs/standards/wubi-decomposition.md`、`d2-glyph-aliases.tsv`、
`data/learning/wubi86-root-inventory.tsv`、`data/sources.toml`。
