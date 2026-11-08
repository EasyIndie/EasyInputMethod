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
    lines = ["# scheme\tletter\tzone\tkeyname\troots(按使用频次降序，空格分隔)",
             "# 由 modules/keymap/tools/build_key_roots.py 生成，勿手改。",
             "# 只收录可渲染为汉字的字根；康熙部首/注音符号等无字形码位见文末注释。"]
    dropped: list[str] = []
    for letter in "QWERTYUIOPASDFGHJKLZXCVBNM":
        name, zone = KEYNAME[letter]
        ranked = sorted(counts[letter].items(), key=lambda kv: (-kv[1], kv[0]))
        roots = [glyph for glyph, _ in ranked if glyph != name]
        kept = [glyph for glyph in roots if renderable(glyph)]
        removed = [glyph for glyph in roots if not renderable(glyph)]
        if removed:
            dropped.append(f"{letter}:{' '.join(removed)}")
        lines.append("\t".join([SCHEME, letter, str(zone), name, " ".join(kept)]))
    if dropped:
        lines.append("# 未收录（系统字体无字形，显示为 ?）：" + "；".join(dropped))
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime", default="data/generated/B0-runtime.tsv")
    parser.add_argument("--out", default="modules/keymap/data/key-roots-wubi86.tsv")
    args = parser.parse_args()
    runtime = pathlib.Path(args.runtime)
    if not runtime.is_file():
        print(f"缺少运行时资源：{runtime}", file=sys.stderr)
        return 1
    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(build(runtime), encoding="utf-8")
    print(f"写出 {out}（{out.stat().st_size} B）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
