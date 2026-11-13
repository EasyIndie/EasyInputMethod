#!/usr/bin/env python3
"""校验三级简码表（D17-ter）与生成结果。

要求（ADR-345）：
- 条数 = 3,362（D9 三字母条目里，全码为四码且以该三码开头的 3,405 条，去掉 42 条与三码全码字撞码的、并合并 1 个重复码位）；
- 三码键位唯一、字唯一；
- 每条都满足「简码 = 该字全码的前三码」；
- 码不能是现有三码全码字（否则会把它顶掉）；
- 生成结果里包含全部条目。
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LEVEL3 = ROOT / "data/sources/wubi86-level3-codes.tsv"
SINGLE = ROOT / "data/generated/wubi86-single.tsv"
CORE = ROOT / "data/generated/wubi86-core.tsv"
EXPECTED = 3362


def rows(path: Path) -> list[list[str]]:
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        out.append(line.split("\t"))
    return out


def main() -> int:
    problems: list[str] = []
    level3 = rows(LEVEL3)
    if len(level3) != EXPECTED:
        problems.append(f"三级简码应为 {EXPECTED} 条，实际 {len(level3)} 条")

    codes = [r[0] for r in level3]
    chars = [r[1] for r in level3]
    if any(len(c) != 3 or any(k not in "abcdefghijklmnopqrstuvwxy" for k in c) for c in codes):
        problems.append("码必须是三个 a–y 字母")
    if len(set(codes)) != len(codes):
        problems.append("三码键位有重复")
    if len(set(chars)) != len(chars):
        problems.append("字有重复")

    full: dict[str, str] = {}
    three_full: set[str] = set()
    for code, text, *_ in rows(SINGLE):
        if len(text) != 1:
            continue
        if len(code) > len(full.get(text, "")):
            full[text] = code
        if len(code) == 3:
            three_full.add(code)
    for code, char in zip(codes, chars):
        if len(char) != 1:
            problems.append(f"必须是单字：{code!r} → {char!r}")
            continue
        whole = full.get(char)
        if not whole:
            problems.append(f"字不在全码表里：{char}")
        elif not whole.startswith(code):
            problems.append(f"简码不是全码前缀：{code} → {char}（全码 {whole}）")
        if code in three_full:
            problems.append(f"三码与现有三码全码字撞码：{code}")

    core = {(r[0], r[1]) for r in rows(CORE)}
    missing = [(c, ch) for c, ch in zip(codes, chars) if (c, ch) not in core]
    if missing:
        problems.append(f"生成结果缺少 {len(missing)} 条：{missing[:5]}")

    if problems:
        for p in problems:
            print(f"❌ {p}")
        return 1
    print(f"✅ 三级简码表通过：{len(level3)} 条，三码唯一，全部为全码前缀，无三码撞码，生成结果包含全部条目")
    return 0


if __name__ == "__main__":
    sys.exit(main())
