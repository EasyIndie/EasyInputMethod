# 标准（Standards）

> 本目录放**项目自己定义、可被第三方引用**的规范。规范是"契约"：数据、校验与测试必须与之一致，
> 不一致就是缺陷（`platforms/macos/tests/test-*-standard.py` 会拦）。

| 标准 | 状态 | 内容 |
|---|---|---|
| [wubi-decomposition.md](wubi-decomposition.md) | 采纳（ADR-358） | 五笔拆字标准 v1：`full` 的判定规则（组件=标准字根、键位一致、识别码一致） |
| **[wubi86/spec-1.0.md](wubi86/spec-1.0.md)** | **1.0 正式（ADR-381/388，随 1.4.0 发布）** | **LWS-86（萤火虫五笔86 拆字标准）**：数据模型、规则 R1–R10、识别码网格、一致性等级 L1–L4 |
| [wubi86/conformance-1.0.md](wubi86/conformance-1.0.md) | 同上 | 一致性判定项（T1–T9）、退出码、数据完整性 |
| [wubi86/CHANGELOG.md](wubi86/CHANGELOG.md) | 同上 | 版本与变更记录、勘误、独立实现验证结果 |

## 怎么用（第三方）

```sh
# 1) 生成标准数据包（仓库内已登记数据，不联网；可复现）
python3 tools/wubi86-std-bundle.py --out build/wubi86-std-1.0
# 2) 拿你自己的实现数据自测（同格式，字段见 spec §4）
python3 tools/wubi86-std-check.py --bundle build/wubi86-std-1.0 --impl <你的数据目录> --level L2
# 3) 看我们自己的独立实现怎么只按规则算出码（S-3）
python3 tools/lws86-reference-impl.py --bundle build/wubi86-std-1.0 --out build/lws86-impl
python3 tools/wubi86-std-check.py --bundle build/wubi86-std-1.0 --impl build/lws86-impl --level L4
```

数据包字段：`roots.tsv`（字形/键位/类别）、`chars.tsv`（字/全码/质量/根序/键位/识别码/简码槽位/范围内/类别）、
`shortcodes.tsv`（字/等级/简码）、`meta.json`、`SHA256SUMS`。

## 命名与免责

标准中文名「**萤火虫五笔86 拆字标准**」，英文 **LWS-86**。由 EasyInputMethod **独立制定**，不是王码（Wangma）
或中央研究院的官方标准，不暗示任何机构背书。差异清单按 ADR-382 **不做**（86 专利已届满、规则属公有领域，
且王码无免费数据许可）；规范只声明独立性，逐条可核对的是"规则与数据自洽"。

**发布方式**：数据包随每个 Release 发布（`LWS-86-1.0.zip` + `.sha256`，与 tag 绑定、可复现），
站点入口 `https://input.jokerhub.cn/standards.html`。
