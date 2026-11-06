#!/usr/bin/env python3
"""校验二级简码表（D17-bis）与生成结果。

要求（报告 237/238）：
- 条数 = 598（公开 86 版二级简码，去掉极爽词库新增的 17 个码位与 2 条前缀不符项）；
- 两码键位唯一、字唯一；
- **每条都满足「简码 = 该字全码的前两码」**（这是它能叫"简码"的硬条件）；
- 生成结果里包含全部条目。
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LEVEL2 = ROOT / "data/sources/wubi86-level2-codes.tsv"
SINGLE = ROOT / "data/generated/wubi86-single.tsv"
CORE = ROOT / "data/generated/wubi86-core.tsv"
EXPECTED = 598


def rows(path: Path) -> list[list[str]]:
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        out.append(line.split("\t"))
    return out


def main() -> int:
    problems: list[str] = []
    level2 = rows(LEVEL2)
    if len(level2) != EXPECTED:
        problems.append(f"二级简码应为 {EXPECTED} 条，实际 {len(level2)} 条")

    codes = [r[0] for r in level2]
    chars = [r[1] for r in level2]
    if any(len(c) != 2 or any(k not in "abcdefghijklmnopqrstuvwxy" for k in c) for c in codes):
        problems.append("码必须是两个 a–y 字母")
    if len(set(codes)) != len(codes):
        problems.append("两码键位有重复")
    if len(set(chars)) != len(chars):
        problems.append("字有重复")

    full: dict[str, str] = {}
    for code, text, *_ in rows(SINGLE):
        if len(text) == 1 and len(code) > len(full.get(text, "")):
            full[text] = code
    for code, char in zip(codes, chars):
        if len(char) != 1:
            problems.append(f"必须是单字：{code!r} → {char!r}")
            continue
        whole = full.get(char)
        if not whole:
            problems.append(f"字不在全码表里：{char}")
        elif not whole.startswith(code):
            problems.append(f"简码不是全码前缀：{code} → {char}（全码 {whole}）")

    core = {(r[0], r[1]) for r in rows(CORE)}
    missing = [(c, ch) for c, ch in zip(codes, chars) if (c, ch) not in core]
    if missing:
        problems.append(f"生成结果缺少 {len(missing)} 条：{missing[:5]}")

    if problems:
        for p in problems:
            print(f"❌ {p}")
        return 1
    print(f"✅ 二级简码表通过：{len(level2)} 条，两码唯一，全部为全码前缀，生成结果包含全部条目")
    return 0


if __name__ == "__main__":
    sys.exit(main())
