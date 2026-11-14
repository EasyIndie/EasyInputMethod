# 279 — 字根字形来源调研（P1-2 / N1 / U3-4）

> 2026-11-14。**只调研：未下载数据、未改 B0/D2、未引入任何字体。**

## 结论

- **没有许可干净、直接以五笔私有区码位提供的字根字形库**。WindInput/qingg/`wmwb06.ttf` 等
  均为「未声明/非商业」，不能进 GPL-3 分发；D3 字体同样不可用（ADR-310）。
- **N1 主候选**：中央研究院「漢字構形資料庫」——1,324 字根、4,766 部件、约 165,653 字形；
  库 GPL-3.0，字体 GFDL 1.2 或 CC BY-SA 2.5 TW，附署名/非背书条款。官方站点当前证书过期，
  需离线/镜像核对文件与许可。
- **交叉校验**：cjk-decomp（75,000 字部件序列，MIT/Apache-2.0 等任选）与 cjkvi-ids/CHISE（GPL-2+）；
  Unicode Unihan 提供 kIDS/kRSUnicode，不含字形图形。
- **兜底**：若 PUA→部件对齐仍不可靠，自绘约 251 个字根 SVG/PNG（参考 OFL 字体），
  以 CC-BY-SA-4.0 发布；工作量约 2–3 周，许可最干净。

## 建议路线

1. N1-a：核对 Academia Sinica 2.7 文件/许可与覆盖，登记来源；
2. N1-b：用 cjk-decomp/IDS 与 D2 序列对齐，产出 PUA→部件候选与置信度；
3. N1-c：人工抽检/裁定，不确定的进入自绘清单；
4. N1-d：自绘剩余字根 + 数据包/许可登记。

**U3-4 仍保持受阻**，直到 N1 完成；不猜测填数。

## 关联

- 全文：`docs/research/root-glyph-sources.md`
- ADR-309/310、报告 268 §2、`docs/结构库第二阶段需求.md`
- 来源：Academia Sinica CDP、cjk-decomp、cjkvi-ids、Unihan、HNG、WindInput 论坛
