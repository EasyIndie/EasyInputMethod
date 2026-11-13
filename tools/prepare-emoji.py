#!/usr/bin/env python3
"""生成可选 emoji 数据（U3-5 / ADR-349）。

输入（fetch-emoji-data.sh 下载，不入库）：
  data/sources/emoji-test-16.0.txt       Unicode 16.0 emoji-test（Unicode License V3）
  data/sources/cldr-annotations-zh.xml   CLDR release-47 中文标注（Unicode License V3）
  data/sources/cldr-annotations-en.xml   CLDR release-47 英文标注
  data/sources/cldr-main-zh.xml          CLDR release-47 中文地区名（旗帜 emoji）

输出：
  data/generated/emoji.tsv
    emoji\tgroup_id\tgroup_zh\torder\tname_zh\tname_en\tkeywords_zh\tkeywords_en
  data/generated/emoji-report.json
"""
from pathlib import Path
import hashlib
import json
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "data/sources"
GENERATED = ROOT / "data/generated"
EMOJI_TEST = SOURCES / "emoji-test-16.0.txt"
CLDR_ZH = SOURCES / "cldr-annotations-zh.xml"
CLDR_EN = SOURCES / "cldr-annotations-en.xml"
CLDR_MAIN_ZH = SOURCES / "cldr-main-zh.xml"
OUT = GENERATED / "emoji.tsv"
REPORT = GENERATED / "emoji-report.json"

GROUP_ZH = {
    "Smileys & Emotion": "表情",
    "People & Body": "人物",
    "Animals & Nature": "动物与自然",
    "Food & Drink": "食物与饮料",
    "Travel & Places": "旅行与地点",
    "Activities": "活动",
    "Objects": "物品",
    "Symbols": "符号",
    "Flags": "旗帜",
}
LINE = re.compile(r"^([0-9A-F ]+)\s*;\s*fully-qualified\s*#\s*(\S+)\s+E[0-9.]+\s+(.+)$")


def load_annotations(path):
    root = ET.parse(path).getroot()
    out = {}
    for element in root.iter("annotation"):
        cp = element.get("cp")
        if not cp:
            continue
        kind = element.get("type")
        text = (element.text or "").strip()
        if not text:
            continue
        entry = out.setdefault(cp, {"tts": "", "keywords": ""})
        if kind == "tts":
            entry["tts"] = text
        else:
            entry["keywords"] = " ".join(part.strip() for part in text.split("|") if part.strip())
    return out


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def strip_vs(text):
    return text.replace("️", "")


def tone_name(char):
    return {
        "\U0001F3FB": "浅肤色",
        "\U0001F3FC": "中浅肤色",
        "\U0001F3FD": "中等肤色",
        "\U0001F3FE": "中深肤色",
        "\U0001F3FF": "深肤色",
    }.get(char, "")


def base_and_tone(emoji):
    """去掉所有肤色修饰符；返回 (base, 肤色描述)。"""
    tones = [c for c in emoji if tone_name(c)]
    base = "".join(c for c in emoji if not tone_name(c))
    if not tones:
        return base, ""
    return base, tone_name(tones[-1])


def tone_labels(emoji):
    labels = []
    for char in emoji:
        label = tone_name(char)
        if label and label not in labels:
            labels.append(label)
    return labels


PHRASE_ZH = [
    ("women holding hands", "两个女人牵手"),
    ("men holding hands", "两个男人牵手"),
    ("woman and man holding hands", "男女牵手"),
    ("kiss: woman, man", "男女亲吻"),
    ("kiss: man, man", "两个男人亲吻"),
    ("kiss: woman, woman", "两个女人亲吻"),
    ("kiss: person, person", "两人亲吻"),
    ("couple with heart: woman, man", "男女情侣"),
    ("couple with heart: man, man", "两个男人情侣"),
    ("couple with heart: woman, woman", "两个女人情侣"),
    ("couple with heart: person, person", "情侣"),
]


def fallback_zh(name_en, tones):
    """为 CLDR 未收录的肤色/发型组合给一个可搜索的中文配名。"""
    text = name_en
    for phrase, zh in PHRASE_ZH:
        if text.startswith(phrase):
            suffix = "（" + "、".join(tones) + "）" if tones else ""
            return zh + suffix
    facing = [
        ("person walking", "向右走的人"), ("woman walking", "向右走的女人"), ("man walking", "向右走的男人"),
        ("person kneeling", "向右跪着的人"), ("woman kneeling", "向右跪着的女人"), ("man kneeling", "向右跪着的男人"),
        ("person with white cane", "向右拿白手杖的人"), ("woman with white cane", "向右拿白手杖的女人"),
        ("man with white cane", "向右拿白手杖的男人"),
        ("person in motorized wheelchair", "向右坐电动轮椅的人"),
        ("woman in motorized wheelchair", "向右坐电动轮椅的女人"),
        ("man in motorized wheelchair", "向右坐电动轮椅的男人"),
        ("person in manual wheelchair", "向右坐手动轮椅的人"),
        ("woman in manual wheelchair", "向右坐手动轮椅的女人"),
        ("man in manual wheelchair", "向右坐手动轮椅的男人"),
        ("person running", "向右跑步的人"), ("woman running", "向右跑步的女人"), ("man running", "向右跑步的男人"),
    ]
    if "facing right" in text:
        for phrase, zh in facing:
            if text.startswith(phrase + " facing right"):
                suffix = "（" + "、".join(tones) + "）" if tones else ""
                return zh + suffix
    if text.startswith("family: "):
        roles = {"man": "爸爸", "woman": "妈妈", "boy": "儿子", "girl": "女儿"}
        members = [roles.get(part.strip(), part.strip()) for part in text.split(":", 1)[1].split(",")]
        return "家庭（" + "、".join(members) + "）"
    hair = [("red hair", "红发"), ("curly hair", "卷发"), ("white hair", "白发"),
            ("blond hair", "金发"), ("bald", "秃头"), ("beard", "胡须"), ("mustache", "八字胡")]
    for phrase, zh in hair:
        if phrase in text:
            person = "男人" if text.startswith("man:") else "女人" if text.startswith("woman:") else "人"
            suffix = "（" + "、".join(tones) + "）" if tones else ""
            return zh + person + suffix
    return ""


def flag_region(emoji):
    """两个区域指示符 → 两位地区码；否则返回空串。"""
    points = [ord(c) for c in emoji]
    if len(points) != 2 or not all(0x1F1E6 <= p <= 0x1F1FF for p in points):
        return ""
    return "".join(chr(p - 0x1F1E6 + ord("A")) for p in points)


def load_territories(path):
    root = ET.parse(path).getroot()
    out = {}
    for element in root.iter("territory"):
        kind = element.get("type", "")
        if len(kind) == 2 and not element.get("alt") and element.text:
            out.setdefault(kind, element.text.strip())
    return out


def main():
    for path in (EMOJI_TEST, CLDR_ZH, CLDR_EN, CLDR_MAIN_ZH):
        if not path.is_file():
            raise SystemExit(f"缺少 {path}；先运行 data/sources/fetch-emoji-data.sh")
    zh = load_annotations(CLDR_ZH)
    en = load_annotations(CLDR_EN)
    zh_norm = {strip_vs(key): value for key, value in zh.items()}
    en_norm = {strip_vs(key): value for key, value in en.items()}
    territories = load_territories(CLDR_MAIN_ZH)
    rows = []
    group = ""
    subgroup = ""
    missing_zh = 0
    for raw in EMOJI_TEST.read_text(encoding="utf-8").splitlines():
        if raw.startswith("# group:"):
            group = raw.split(":", 1)[1].strip()
            subgroup = ""
            continue
        if raw.startswith("# subgroup:"):
            subgroup = raw.split(":", 1)[1].strip()
            continue
        match = LINE.match(raw)
        if not match:
            continue
        codes, emoji, name_en = match.groups()
        chars = "".join(chr(int(code, 16)) for code in codes.split())
        if chars != emoji:
            raise SystemExit(f"码点与 emoji 不一致：{raw}")
        key = strip_vs(emoji)
        zh_entry = zh.get(emoji) or zh_norm.get(key) or {"tts": "", "keywords": ""}
        en_entry = en.get(emoji) or en_norm.get(key) or {"tts": "", "keywords": ""}
        base, tone = base_and_tone(emoji)
        tones = tone_labels(emoji)
        base_key = strip_vs(base)
        base_zh = zh.get(base) or zh_norm.get(base_key) or {"tts": "", "keywords": ""}
        base_en = en.get(base) or en_norm.get(base_key) or {"tts": "", "keywords": ""}
        name_zh = zh_entry["tts"]
        keywords_zh = zh_entry["keywords"]
        if not name_zh and tones and base_zh["tts"]:
            # 肤色变体继承基础 emoji 的名称与搜索词，再补上肤色。
            suffix = "、".join(tones)
            name_zh = f"{base_zh['tts']}（{suffix}）"
            keywords_zh = f"{base_zh['keywords']} {suffix}".strip()
        region = flag_region(emoji)
        if not name_zh and region and region in territories:
            name_zh = f"{territories[region]}旗帜"
            keywords_zh = f"{territories[region]} 旗帜 {region} flag"
        if not name_zh and "handshake" in name_en and tone:
            name_zh = "握手（肤色组合）"
            keywords_zh = "握手 handshake 肤色"
        if not name_zh and name_en.startswith("keycap: "):
            keycap = name_en.split(":", 1)[1].strip()
            label = "数字键" if keycap.isdigit() else "符号键"
            name_zh = f"{label} {keycap}"
            keywords_zh = f"keycap {label} {keycap}"
        if not name_zh and name_en.startswith("flag: "):
            place = name_en.split(":", 1)[1].strip()
            place_zh = {"England": "英格兰", "Scotland": "苏格兰", "Wales": "威尔士",
                        "Sark": "萨克岛"}.get(place)
            if place_zh:
                name_zh = f"{place_zh}旗帜"
                keywords_zh = f"{place_zh} 旗帜 flag"
        if not name_zh:
            zh_fallback = fallback_zh(name_en, tones)
            if zh_fallback:
                name_zh = zh_fallback
                keywords_zh = f"{zh_fallback} {' '.join(tones)}".strip()
        if not name_zh:
            missing_zh += 1
        name_en = en_entry["tts"] or name_en or base_en["tts"]
        keywords_en = en_entry["keywords"] or base_en["keywords"]
        if not keywords_zh and base_zh["keywords"]:
            keywords_zh = base_zh["keywords"]
        if not group:
            raise SystemExit(f"emoji 缺少 group：{raw}")
        rows.append(
            (
                emoji,
                group,
                GROUP_ZH.get(group, group),
                len(rows),
                name_zh,
                name_en,
                keywords_zh,
                keywords_en,
            )
        )
    if not rows:
        raise SystemExit("没有解析到 fully-qualified emoji")
    seen = set()
    for row in rows:
        if row[0] in seen:
            raise SystemExit(f"emoji 重复：{row[0]}")
        seen.add(row[0])
        for field in row:
            if "\t" in str(field) or "\n" in str(field):
                raise SystemExit(f"字段含制表符/换行：{row!r}")
    lines = [
        "# 项目派生 emoji 数据；CC-BY-SA-4.0；D21/D22/ADR-349。",
        "# emoji\tgroup_id\tgroup_zh\torder\tname_zh\tname_en\tkeywords_zh\tkeywords_en",
    ]
    lines.extend("\t".join(map(str, row)) for row in rows)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    report = {
        "emoji_test_sha256": sha256(EMOJI_TEST),
        "cldr_zh_sha256": sha256(CLDR_ZH),
        "cldr_en_sha256": sha256(CLDR_EN),
        "cldr_main_zh_sha256": sha256(CLDR_MAIN_ZH),
        "output_sha256": sha256(OUT),
        "output_bytes": OUT.stat().st_size,
        "entries": len(rows),
        "missing_zh_short_name": missing_zh,
        "groups": sorted({row[1] for row in rows}),
        "license": "Unicode License V3（数据文件）/ CC-BY-SA-4.0（本编排）",
    }
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
