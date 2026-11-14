#!/usr/bin/env python3
"""N1-d 补充区 PUA 清单（ADR-353）：B0 3,000 字实际用到的 D2 私有区字形。

D2（aardio/wubi-lex，MIT）把部分字根写成**补充区 PUA**（U+F00xx）。本脚本只读
D2 位序、全码键位与 N1-d 核验表，列出这些 PUA 的身份与覆盖状态；不猜字形、不改 B0。

输出：corpus/pua-inventory.tsv
  pua	label	status	keys	occurrences	samples

status：
  verified  —— 所有出现都已在核验表（PUA+键位）中给出可读字根；
  partial   —— 部分键位可用，其余仍缺；
  unresolved—— 尚无任何可读字根（label 留空，不猜）。
"""
from pathlib import Path
import collections

ROOT = Path(__file__).resolve().parents[3]
D2 = ROOT / "data/sources/wubi-lex-86.txt"
CODES = ROOT / "data/generated/wubi86-single.tsv"
RUNTIME = ROOT / "data/generated/B0-runtime.tsv"
SUPPLEMENTARY = ROOT / "modules/hanzi-structure/corpus/pua-supplementary.tsv"
OUT = ROOT / "modules/hanzi-structure/corpus/pua-inventory.tsv"


def is_pua(char: str) -> bool:
    return 0xE000 <= ord(char) <= 0xF8FF or ord(char) >= 0xF0000


def is_supplementary(char: str) -> bool:
    return ord(char) >= 0xF0000


def load_d2() -> dict[str, list[str]]:
    out = {}
    for line in D2.read_text(encoding="utf-8").splitlines():
        line = line.lstrip("﻿").rstrip("\r")
        if not line.strip() or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) >= 2:
            out[fields[0]] = [c for c in fields[1] if not c.isspace()]
    return out


def load_codes() -> dict[str, str]:
    out = {}
    for line in CODES.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) >= 2 and len(fields[1]) == 1:
            if len(fields[0]) > len(out.get(fields[1], "")):
                out[fields[1]] = fields[0]
    return out


def load_supplementary() -> dict[tuple[str, str], str]:
    out = {}
    for line in SUPPLEMENTARY.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) < 3:
            continue
        pua = chr(int(fields[0].strip().upper().removeprefix("U+"), 16))
        out[(pua, fields[1].strip().lower())] = fields[2].strip()
    return out


def roots_with_keys(glyphs: list[str], code: str) -> tuple[list[str], list[str | None]]:
    """按 B0 的 v4 规则取字根位。

    - D2 与全码等长：末位 PUA 是识别码槽，丢弃；其余逐位对码。
    - D2 比全码少一位：少的是识别码，所有字形都是字根，逐位对码。
    - 其它长度：位次不可靠，只列字形、不给键位。
    """
    if glyphs and len(glyphs) in (len(code), len(code) - 1):
        roots = glyphs[:-1] if len(glyphs) == len(code) and is_supplementary(glyphs[-1]) else glyphs
        return roots, list(code[: len(roots)])
    # 位次不可靠（D2 比码长多出 1 位以上或多出识别码槽）：不把这些字形算作可定位字根，
    # 以免把识别码槽误当成待自绘字根。
    return [], []


def main() -> int:
    d2 = load_d2()
    codes = load_codes()
    supplementary = load_supplementary()
    runtime_chars = {
        line.split("\t")[0]
        for line in RUNTIME.read_text(encoding="utf-8").splitlines()
        if line and not line.startswith("#")
    }
    occurrences = collections.Counter()
    keys = collections.defaultdict(collections.Counter)
    samples = collections.defaultdict(list)
    labels = collections.defaultdict(collections.Counter)
    mapped = collections.Counter()

    for char in runtime_chars:
        code = codes.get(char, "")
        glyphs = d2.get(char, [])
        if not code or not glyphs:
            continue
        roots, root_keys = roots_with_keys(glyphs, code)
        for glyph, key in zip(roots, root_keys):
            if not is_supplementary(glyph):
                continue
            occurrences[glyph] += 1
            keys[glyph][key or "-"] += 1
            if len(samples[glyph]) < 8:
                samples[glyph].append(char)
            label = (supplementary.get((glyph, key)) if key else None) or supplementary.get((glyph, "*"))
            if label:
                labels[glyph][label] += 1
                mapped[glyph] += 1

    lines = [
        "# N1-d 自绘清单（ADR-353）：B0 3,000 字实际用到的 D2 补充区 PUA。",
        "# 源：data/sources/wubi-lex-86.txt（D2，MIT）；身份核验见 pua-supplementary.tsv。",
        "# pua\tlabel\tstatus\tkeys\toccurrences\tsamples",
    ]
    for pua in sorted(occurrences, key=lambda p: (-occurrences[p], ord(p))):
        total = occurrences[pua]
        got = mapped[pua]
        if got == 0:
            status, label = "unresolved", ""
        else:
            label = labels[pua].most_common(1)[0][0]
            status = "verified" if got == total and len(labels[pua]) == 1 else "partial"
        key_text = ",".join(f"{key}:{n}" for key, n in keys[pua].most_common())
        lines.append(f"{pua}\t{label}\t{status}\t{key_text}\t{total}\t{''.join(samples[pua])}")
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    verified = sum(1 for p in occurrences if mapped[p] == occurrences[p] and len(labels[p]) == 1)
    partial = sum(1 for p in occurrences if 0 < mapped[p] < occurrences[p] or len(labels[p]) > 1)
    unresolved = sum(1 for p in occurrences if mapped[p] == 0)
    print(f"pua={len(occurrences)} verified={verified} partial={partial} "
          f"unresolved={unresolved} -> {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
