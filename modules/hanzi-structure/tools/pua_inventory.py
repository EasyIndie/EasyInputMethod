#!/usr/bin/env python3
"""N1-d 自绘字根清单（ADR-353）：列出 3,000 字 partial 里用到的私有区字形。

只读 D2/D14/pua-map/码表；不猜字形、不改 B0。
输出：corpus/pua-inventory.tsv（pua, label, status, keys, occurrences, samples）
"""
from pathlib import Path
import collections
import json

ROOT = Path(__file__).resolve().parents[3]
D2 = ROOT / "data/sources/windinput-wubi86-chaizi.txt"
CODES = ROOT / "data/generated/wubi86-single.tsv"
RUNTIME = ROOT / "data/generated/B0-runtime.tsv"
PUA_MAP = ROOT / "modules/hanzi-structure/corpus/pua-map.json"
OUT = ROOT / "modules/hanzi-structure/corpus/pua-inventory.tsv"


def is_pua(char: str) -> bool:
    return 0xE000 <= ord(char) <= 0xF8FF or ord(char) >= 0xF0000


def main():
    d2 = {}
    for line in D2.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) >= 2:
            d2[fields[0]] = [c for c in fields[1] if not c.isspace()]
    codes = {}
    for line in CODES.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) >= 2:
            codes[fields[1]] = fields[0]
    known = {
        pua: info["readable"]
        for pua, info in json.loads(PUA_MAP.read_text(encoding="utf-8")).get("map", {}).items()
    }
    occurrences = collections.Counter()
    keys = collections.defaultdict(collections.Counter)
    samples = collections.defaultdict(list)
    for line in RUNTIME.read_text(encoding="utf-8").splitlines():
        fields = line.split("\t")
        if len(fields) < 3 or fields[2] == "full":
            continue
        char = fields[0]
        code = codes.get(char, "")
        glyphs = d2.get(char, [])
        if not code or len(glyphs) != len(code):
            continue
        for index, glyph in enumerate(glyphs[:-1]):
            if not is_pua(glyph):
                continue
            occurrences[glyph] += 1
            keys[glyph][code[index]] += 1
            if len(samples[glyph]) < 6:
                samples[glyph].append(char)
    lines = [
        "# N1-d 自绘清单（ADR-353）：3,000 字 partial 中用到的私有区字形。",
        "# pua\tlabel\tstatus\tkeys\toccurrences\tsamples",
    ]
    for pua, count in occurrences.most_common():
        label = known.get(pua, "")
        status = "known" if label else "unresolved"
        key_text = "".join(f"{key}:{n}" for key, n in keys[pua].most_common())
        lines.append(f"{pua}\t{label}\t{status}\t{key_text}\t{count}\t{''.join(samples[pua])}")
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"pua={len(occurrences)} known={sum(1 for p in occurrences if p in known)} "
          f"unresolved={sum(1 for p in occurrences if p not in known)} -> {OUT}")


if __name__ == "__main__":
    main()
