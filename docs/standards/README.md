# 标准（Standards）

> 本目录放**项目自己定义、可被第三方引用**的规范。规范是"契约"：数据、校验与测试必须与之一致，
> 不一致就是缺陷（`platforms/macos/tests/test-*-standard.py` 会拦）。

| 标准 | 状态 | 内容 |
|---|---|---|
| [wubi-decomposition.md](wubi-decomposition.md) | 采纳（ADR-358） | 五笔拆字标准 v1：`full` 的判定规则（组件=标准字根、键位一致、识别码一致） |
| **[wubi86/spec-1.0.md](wubi86/spec-1.0.md)** | **1.0 草案（ADR-381）** | **LWS-86（萤火虫五笔86 拆字标准）**：数据模型、规则 R1–R10、识别码网格、一致性等级 L1–L4 |
| [wubi86/conformance-1.0.md](wubi86/conformance-1.0.md) | 同上 | 一致性判定项（T1–T9）、退出码、数据完整性 |
| [wubi86/CHANGELOG.md](wubi86/CHANGELOG.md) | 同上 | 版本与变更记录、勘误、与王码官方口径的差异入口 |

## 怎么用（第三方）

```sh
# 1) 生成标准数据包（仓库内已登记数据，不联网）
python3 tools/wubi86-std-bundle.py --out build/wubi86-std-1.0
# 2) 拿你自己的实现数据自测（同格式，字段见 spec §4）
python3 tools/wubi86-std-check.py --bundle build/wubi86-std-1.0 --impl <你的数据目录> --level L2
```

数据包字段：`roots.tsv`（字形/键位/类别）、`chars.tsv`（字/全码/质量/根序/键位/识别码/简码槽位/范围内/类别）、
`shortcodes.tsv`（字/等级/简码）、`meta.json`、`SHA256SUMS`。

## 命名与免责

标准中文名「**萤火虫五笔86 拆字标准**」，英文 **LWS-86**。由 EasyInputMethod **独立制定**，不是王码（Wangma）
或中央研究院的官方标准，不暗示任何机构背书；与王码官方口径的差异见 `wubi86/wangma-diff.md`（待建）。
