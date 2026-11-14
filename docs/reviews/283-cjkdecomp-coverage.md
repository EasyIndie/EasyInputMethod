# 283 — cjk-decomp（Apache-2.0）覆盖扩量

> 2026-11-14。**引入开源免费、非付费的完整拆字源；仅构建期读取，不随包分发。**

## 1. 来源与许可

| 项 | 值 |
|---|---|
| 来源 | `amake/cjk-decomp` 的 `cjk-decomp.txt`（约 75,000 字的图形分解树） |
| 固定提交 | `c29b391fd6267e7a3541387e03a3dd60b1cd34d1` |
| SHA-256 | `5accf5661dd509d4bc5966afaeb7f763231a39f23b00acda89d6c040740b8ab6` |
| 许可 | README 提供 Apache-2.0 / LGPL-3.0 / CC BY-SA 3.0 / MIT / ODC-By / EPL 六选一；**LICENSE 文件为 Apache-2.0**（GPL-3 兼容） |
| 登记 | `data/sources.toml` D24，`ship=false`；`fetch-cjk-decomp.sh` 下载并校验 |

**不是付费数据**；源文件不提交、不随包分发。

## 2. 方法

`tools/coverage_decomp.py`：

1. 解析 cjk-decomp 的树（组件/5 位中间 ID 递归展开）；
2. 在树上切出恰好 **n 或 n-1 个叶子**（n = 全码长度）；
3. 枚举叶子顺序（最多 4 个），只保留**每个叶子的五笔键位都与码位一致**的候选；
4. n-1 个叶子时，末位识别码结构必须与 D19 IDS 结构一致；
5. 多个候选视为歧义，跳过；CJK 笔画字形归一化为 `一丨丿丶乙`；
6. 只对 B0 当前非 `full` 的字生成。

产物 `data/learning/wubi86-cjkdecomp-coverage.tsv`（83 条，项目自编编排 CC-BY-SA-4.0）；B0 用 `componentsSource=D24`。

## 3. 结果

| 指标 | 前（报告 282） | 后 |
|---|---:|---:|
| B0 1,000 字 `full` | 955 | **965** |
| B0 1,000 字 `partial` | 37 | **31** |
| B0 1,000 字 `unknown` | 8 | **4** |
| B0 3,000 字 `full` | 2,676 | **2,759** |
| B0 3,000 字 `partial` | 104 | **87** |
| B0 3,000 字 `unknown` | 220 | **154** |
| 运行时 `full` | 2,519 | **2,602** |
| 运行时 `partial` | 261 | **244** |

覆盖率：B0 **92.0%**、运行时 **86.7%**；仍未达 98% 门槛。

## 4. 典型样例

- `紝` → 糹 丿 士（X T F + 识别 G）
- `簡` → 竹 門 日（T U J + 识别 F）
- `鏈` → 金 車 辶（Q L P + 识别 Y）
- `駐` → 马 丶 王（C Y G + 识别 G）
- `武` → 一 弋 止（G A H + 识别 D）
- `冷` → 冫 人 丶 厶（U W Y C）

这些在 D2 里只有 1 个根或缺失，cjk-decomp 树切分 + 键位/结构校验后补全。

## 5. 仍未完成

- 154 个 `unknown`：cjk-decomp 的树切分无法给出 n/n-1 个键位全匹配的叶子（或结构不匹配）；
  多数是极生僻繁体/异体字。
- 88 个 `partial`：主要是 13 个语境歧义 PUA、D2 缺根/位次问题。
- 未用 D3 作来源；未引入付费数据。
- 下一步若要继续，可评估 Academia Sinica 部件库（需离线核对许可）或接受当前覆盖率。

## 6. 验证

- `coverage_decomp.py` 生成报告：targets 324 / accepted 83 / ambiguous 5 / no_cut 187 / key_mismatch 60 / recognition_mismatch 8；
- `validate_b0.py`、`test-cjkdecomp-coverage.py`、`make macos-offline-tests`、`make verify`。

## 7. 关联

ADR-357、报告 282、`data/sources.toml` D24、`fetch-cjk-decomp.sh`、`coverage_decomp.py`。
