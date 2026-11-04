#!/usr/bin/env python3
"""报告 224 复现脚本：一级简码在当前码表下能排到首选的比例。

用法：python3 docs/reviews/224-repro-first-level-codes.py [码表路径]
只读；不修改任何文件。
"""

import pathlib
import sys

DEFAULT = "data/generated/wubi86-single.tsv"
# 五笔86 一级简码（公开标准：25 个键位字）
FIRST_LEVEL = {
    "g": "一", "f": "地", "d": "在", "s": "要", "a": "工",
    "h": "上", "j": "是", "k": "中", "l": "国", "m": "同",
    "t": "和", "r": "的", "e": "有", "w": "人", "q": "我",
    "y": "主", "u": "产", "i": "不", "o": "为", "p": "这",
    "n": "民", "b": "了", "v": "发", "c": "以", "x": "经",
}


def main() -> int:
    path = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else DEFAULT)
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        try:
            weight = int(parts[2])
        except ValueError:
            continue
        rows.append((parts[0], parts[1], weight))

    hit = 0
    for key, expected in FIRST_LEVEL.items():
        group = sorted(
            ((w, t) for code, t, w in rows if code.startswith(key)), reverse=True
        )[:3]
        if group and group[0][1] == expected:
            hit += 1
        else:
            print(f"{key}: 期望「{expected}」，实际前三 {[t for _, t in group]}")
    print(f"一级简码命中 {hit} / {len(FIRST_LEVEL)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
