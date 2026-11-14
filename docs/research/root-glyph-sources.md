# 字根字形/部件来源调研（P1-2 / N1 / U3-4）

> 2026-11-14。**只调研，不下载数据、不改仓库数据。**
> 目标：为 U3-4 的 738 条 D2 补充区私有码位（`U+F00xx` 类）找许可干净的字根字形身份来源。

## 0. 缺口

B0 当前 1,000 字：`full` 735 / `partial` 257 / `unknown` 8；3,000 字里约 876 条 partial，
其中 738 条缺的是 **D2 的私有区字根字形身份**（不是笔画、不是结构）。没有字形身份，
就不能把「？」换成可读字根；强行按码位猜会把错误字根教给用户（报告 268 §2）。

## 1. 候选来源

| 候选 | 提供 | 许可 | 覆盖/规模 | 结论 |
|---|---|---|---|---|
| **中央研究院「漢字構形資料庫」** | 部件/字根/构字符号与字形 | **GPL-3.0**（库/程序）；字体 **GFDL 1.2 或 CC BY-SA 2.5 TW**（二选一），附署名/非背书条款 | 2.7 版约 165,653 字形；4,766 部件、**1,324 字根**（常用 657） | **N1 主候选**；官方站点当前证书过期，需离线/镜像核对许可与文件 |
| **cjk-decomp**（amake，已停维护） | 75,000 字的图形分解（部件序列） | **MIT / Apache-2.0 / LGPL-3 / CC BY-SA 3.0 / ODC-By / EPL** 任选 | 20,924 基本区 + 6,582 扩展 A + 42,711 扩展 B 等 | 部件序列/交叉校验主选；推荐维护版 `cjkvi-ids` |
| **cjkvi-ids / CHISE IDS** | IDS 分解（`⿰⿱…`） | CHISE 为 **GPL-2+**；`ids-ext-cde.txt` 不受 GPL 限制 | 近乎全 CJK | 可作 IDS 交叉校验；GPL 数据与项目 GPL-3 代码可共存，但需单独登记 |
| **Unicode Unihan** | `kIDS` / `kRSUnicode` / `kTotalStrokes` | **Unicode License V3** | 全 CJK | 结构/部首交叉校验；**不含字形图形** |
| **HNG（汉字字体规范史）** | 历史字形图片 + 元数据 | **CC BY-SA 4.0 / GPL-2+** | 历史字形 | 可作字形参考，不直接给字根身份 |
| **WindInput / qingg 等五笔字根字体** | 五笔字根字体 | **未声明/非商业**（论坛字体、`wmwb06.ttf` 明确教育用途） | 86/98/新世纪 | **不采用**（许可不明/不可商用） |
| **Noto Sans CJK / Source Han** | 标准 CJK 字形 | **SIL OFL 1.1** | 全 CJK | 只能渲染 Unicode 部件，不能渲染私有区；可用于**自绘字根 SVG**的参考 |
| **Make Me a Hanzi / hanzi-writer-data / KanjiVG** | 笔顺/字形 | Arphic / CC BY-SA 3.0 | 常用字 | **不采用**（Arphic 非 GPL 兼容；KanjiVG 简体覆盖差） |

## 2. 关键结论

1. **没有任何许可干净、直接以五笔私有区码位提供的字根字形库**。现有五笔字根字体都属于「未声明/非商业」，
   与 GPL-3 分发不兼容；D3 的 `HeiTiZiGen.ttf` 也属于这一类（ADR-310）。
2. 可以做的是 **「部件身份库」而不是「五笔字体」**：
   - Academia Sinica 的 1,324 字根 + cjk-decomp/IDS 的部件序列，可以给出**标准 Unicode 部件身份**；
   - 再把 D2 的 251 个私有区字形与这些部件对齐（序列对齐 + 人工抽检），而不是依赖五笔字体。
3. 若对齐仍不可靠，最后兜底是**项目自绘约 251 个字根 SVG/PNG**：
   - 依据公开五笔86 字根表与 OFL 字体（Noto/Source Han）作形状参考，重新绘制；
   - 以 CC-BY-SA-4.0 发布，作为 N1 数据包；
   - 工作量约 2–3 周（251 个字形 + 核验），但许可最干净、可长期维护。

## 3. 推荐路线（批准后）

| 里程碑 | 内容 | 预计 |
|---|---|---|
| N1-a | 核对 Academia Sinica 2.7 文件/许可与字体覆盖；登记 D26 | 1–2 天 |
| N1-b | 用 cjk-decomp/IDS 与 D2 序列对齐，产出 PUA→部件候选与置信度 | 3–5 天 |
| N1-c | 人工抽检/裁定；仍不确定的进入自绘清单 | 3–5 天 |
| N1-d | 自绘剩余字根 SVG（如需要）+ 数据包/许可登记 | 1–2 周 |

**验收**：3,000 字 `partial` 中由「缺字根身份」导致的条目降到接近 0；每个字根身份有来源/许可/SHA；
用户可见拆解不含猜测字形。

## 4. 本次不做什么

- 不下载 Academia Sinica / cjk-decomp 数据；
- 不修改 B0/D2；
- 不把任何五笔字根字体放进仓库或安装包。

## 5. 来源

- [中央研究院漢字構形資料庫](https://cdp.sinica.edu.tw/cdphanzi/)（官方站点当前证书过期，需镜像/离线核对）
- [Academia Sinica 字体许可声明（上游镜像）](https://raw.githubusercontent.com/leonsilicon/fontpkg-eudc/f53f955f92c9345e3e1b66c044170f1fac3058d0/UPSTREAM-LICENSE.md)
- [cjk-decomp](https://github.com/amake/cjk-decomp)
- [cjkvi-ids](https://github.com/cjkvi/cjkvi-ids)
- [CHISE IDS](https://www.chise.org/)
- [Unicode Unihan](https://www.unicode.org/charts/unihan.html)
- [HNG basic data](https://gitlab.nijl.ac.jp/HNG/hng-basic-data)
- [WindInput 字根字体讨论（无明确许可）](https://forum.windinput.com/topic/401/)
