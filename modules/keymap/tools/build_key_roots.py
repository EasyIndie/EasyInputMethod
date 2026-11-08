#!/usr/bin/env python3
"""从 B0 运行时资源派生"键 → 字根"分布表。

输入：data/generated/B0-runtime.tsv（第 4 列 `形:键`，可能含 `？:键` 占位）
输出：modules/keymap/data/key-roots-wubi86.tsv

只做统计，不引入新数据源：字根与键位的对应关系来自已经登记的教学运行时资源。
"""
from __future__ import annotations

import argparse
import pathlib
import sys

SCHEME = "wubi86"

# 五笔 86 传统助记口诀（每个键位一句，教学常识，随方案内置；不在口诀里做版权主张）。
MNEMONIC = {
    "G": "王旁青头戋（兼）五一",
    "F": "土士二干十寸雨",
    "D": "大犬三羊古石厂",
    "S": "木丁西",
    "A": "工戈草头右框七",
    "H": "目具上止卜虎皮",
    "J": "日早两竖与虫依",
    "K": "口与川，字根稀",
    "L": "田甲方框四车力",
    "M": "山由贝，下框几",
    "T": "禾竹一撇双人立，反文条头共三一",
    "R": "白手看头三二斤",
    "E": "月彡（衫）乃用家衣底",
    "W": "人和八，三四里",
    "Q": "金勺缺点无尾鱼，犬旁留叉儿一点夕，氏无七（妻）",
    "Y": "言文方广在四一，高头一捺谁人去",
    "U": "立辛两点六门疒",
    "I": "水旁兴头小倒立",
    "O": "火业头，四点米",
    "P": "之宝盖，摘礻（示）衤（衣）",
    "N": "已半巳满不出己，左框折尸心和羽",
    "B": "子耳了也框向上",
    "V": "女刀九臼山朝西",
    "C": "又巴马，丢矢矣",
    "X": "慈母无心弓和匕，幼无力",
    "Z": "",
}
# 区位号（11–55）：口诀与字根都按这个顺序排，和主流教程一致。
POSITION = {
    "G": 11, "F": 12, "D": 13, "S": 14, "A": 15,
    "H": 21, "J": 22, "K": 23, "L": 24, "M": 25,
    "T": 31, "R": 32, "E": 33, "W": 34, "Q": 35,
    "Y": 41, "U": 42, "I": 43, "O": 44, "P": 45,
    "N": 51, "B": 52, "V": 53, "C": 54, "X": 55,
    "Z": 0,
}
ZONE_NAME = {1: "横", 2: "竖", 3: "撇", 4: "捺", 5: "折", 0: "万能"}

# 五笔 86 标准字根表（以正式字根表为准，顺序即口诀顺序）。
# 生成时以本表为**唯一真源**：语料只用于交叉校验（见 key-roots-wubi86-audit.md），
# 不再把语料里出现过的部件直接当成字根，避免"多出不属本键的字根"。
CANONICAL = {
    "G": ["王", "一", "五", "戋"],
    "F": ["土", "士", "二", "干", "十", "寸", "雨"],
    "D": ["大", "犬", "三", "羊", "古", "石", "厂", "丆"],
    "S": ["木", "丁", "西", "覀"],
    "A": ["工", "戈", "弋", "艹", "卄", "廾", "匚", "七"],
    "H": ["目", "具", "上", "止", "卜", "虎", "皮", "⺊"],
    "J": ["日", "曰", "早", "虫", "刂"],
    "K": ["口", "川"],
    "L": ["田", "甲", "囗", "四", "罒", "车", "力", "皿"],
    "M": ["山", "由", "贝", "冂", "几"],
    "T": ["禾", "竹", "⺮", "丿", "彳", "攵", "夂"],
    "R": ["白", "手", "扌", "斤"],
    "E": ["月", "彡", "乃", "用", "豕", "衣"],
    "W": ["人", "亻", "八", "癶"],
    "Q": ["金", "钅", "勹", "儿", "夕", "犭", "乂"],
    "Y": ["言", "讠", "文", "方", "广", "丶", "亠", "高", "乀"],
    "U": ["立", "辛", "丬", "六", "门", "疒", "丷"],
    "I": ["水", "氵", "小", "⺌"],
    "O": ["火", "灬", "米", "业"],
    "P": ["之", "辶", "廴", "宀", "冖", "礻", "衤"],
    "N": ["已", "己", "巳", "尸", "心", "忄", "羽", "乙", "乚"],
    "B": ["子", "孑", "耳", "阝", "也", "了", "凵", "卩"],
    "V": ["女", "刀", "九", "臼", "彐", "巛"],
    "C": ["又", "巴", "马", "厶"],
    "X": ["纟", "幺", "弓", "匕", "ヒ", "母"],
    "Z": ["万能"],
}

# 只收录能被系统字体渲染成汉字的字根：康熙部首（⺈ ⺝）、注音符号（ㄅ ㄠ）、
# 日文片假名部件（リ）等码位没有字形，画出来是 `?`，故从展示数据中剔除。
RENDERABLE_RANGES = ((0x4E00, 0x9FFF), (0x3400, 0x4DBF), (0xF900, 0xFAFF))


def renderable(glyph: str) -> bool:
    return all(any(low <= ord(ch) <= high for low, high in RENDERABLE_RANGES) for ch in glyph)
KEYNAME = {
    "G": ("王", 1), "F": ("土", 1), "D": ("大", 1), "S": ("木", 1), "A": ("工", 1),
    "H": ("目", 2), "J": ("日", 2), "K": ("口", 2), "L": ("田", 2), "M": ("山", 2),
    "T": ("禾", 3), "R": ("白", 3), "E": ("月", 3), "W": ("人", 3), "Q": ("金", 3),
    "Y": ("言", 4), "U": ("立", 4), "I": ("水", 4), "O": ("火", 4), "P": ("之", 4),
    "N": ("已", 5), "B": ("子", 5), "V": ("女", 5), "C": ("又", 5), "X": ("纟", 5),
    "Z": ("万能", 0),
}


def build(runtime_path: pathlib.Path) -> str:
    counts: dict[str, dict[str, int]] = {letter: {} for letter in KEYNAME}
    for line in runtime_path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) < 4:
            continue
        for item in fields[3].split():
            if ":" not in item:
                continue
            glyph, key = item.rsplit(":", 1)
            key = key.upper()
            if glyph == "？" or key not in counts:
                continue
            counts[key][glyph] = counts[key].get(glyph, 0) + 1
    lines = ["# scheme\tletter\tzone\tposition(区位)\tkeyname\troots(按口诀顺序，空格分隔)\tmnemonic(口诀)",
             "# 由 modules/keymap/tools/build_key_roots.py 生成，勿手改。",
             "# 只收录可渲染为汉字的字根；康熙部首/注音符号等无字形码位见文末注释。"]
    for letter in "QWERTYUIOPASDFGHJKLZXCVBNM":
        name, zone = KEYNAME[letter]
        canonical = [glyph for glyph in CANONICAL[letter] if glyph != name]
        kept = [glyph for glyph in canonical if renderable(glyph)]
        # 展示顺序跟随口诀：口诀里先出现的排前面；口诀没提到的按标准表顺序收尾。
        text = MNEMONIC.get(letter, "")

        def order(item: tuple[int, str]) -> tuple[int, int]:
            index, glyph = item
            position = text.find(glyph)
            return (position if position >= 0 else len(text) + index, index)

        kept = [glyph for _, glyph in sorted(enumerate(kept), key=order)]
        lines.append("\t".join([SCHEME, letter, str(zone), str(POSITION[letter]), name,
                                 " ".join(kept), MNEMONIC.get(letter, "")]))
    return "\n".join(lines) + "\n"


def audit(runtime_path: pathlib.Path) -> str:
    """逐键校验：语料里出现但不在标准字根表里的部件，以及标准表里语料从未用到的字根。"""
    counts: dict[str, dict[str, int]] = {letter: {} for letter in KEYNAME}
    for line in runtime_path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) < 4:
            continue
        for item in fields[3].split():
            if ":" not in item:
                continue
            glyph, key = item.rsplit(":", 1)
            key = key.upper()
            if glyph == "？" or key not in counts:
                continue
            counts[key][glyph] = counts[key].get(glyph, 0) + 1
    lines = ["# 键位字根审计（逐键）",
             "",
             "标准表 = `tools/build_key_roots.py` 的 `CANONICAL`；语料 = `data/generated/B0-runtime.tsv`。",
             "",
             "| 键 | 区位 | 语料有、标准表无（疑似误挂） | 标准表有、语料未用 |",
             "|---|---|---|---|"]
    for letter in "QWERTYUIOPASDFGHJKLZXCVBNM":
        canonical = set(CANONICAL[letter])
        used = counts[letter]
        extra = sorted(((glyph, n) for glyph, n in used.items() if glyph not in canonical),
                       key=lambda kv: (-kv[1], kv[0]))
        missing = [glyph for glyph in CANONICAL[letter] if glyph not in used]
        extra_text = "、".join(f"{glyph}×{n}" for glyph, n in extra) or "—"
        lines.append(f"| {letter} | {POSITION[letter]} | {extra_text} | "
                     f"{'、'.join(missing) or '—'} |")
    lines.append("")
    lines.append("说明：语料里的拆分是「实际拆字结果」，包含复合部件与变形写法，不都是字根；"
                 "本表以标准字根表为展示真源，语料差异仅作回归线索，不改展示内容。")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime", default="data/generated/B0-runtime.tsv")
    parser.add_argument("--out", default="modules/keymap/data/key-roots-wubi86.tsv")
    parser.add_argument("--audit-out", default="modules/keymap/data/key-roots-wubi86-audit.md")
    args = parser.parse_args()
    runtime = pathlib.Path(args.runtime)
    if not runtime.is_file():
        print(f"缺少运行时资源：{runtime}", file=sys.stderr)
        return 1
    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(build(runtime), encoding="utf-8")
    print(f"写出 {out}（{out.stat().st_size} B）")
    audit_out = pathlib.Path(args.audit_out)
    audit_out.write_text(audit(runtime), encoding="utf-8")
    print(f"写出 {audit_out}（{audit_out.stat().st_size} B）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
