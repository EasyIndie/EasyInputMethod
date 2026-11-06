#!/usr/bin/env python3
"""校验一级简码键位表（D17）与生成结果。

ADR-304 要求：**25 条、键位唯一、字唯一、字在全码表内、码长一致**。
`make verify` 之外的独立脚本，便于改表后单独跑（生成器本身也会拒绝坏表，
这个脚本让"表本身对不对"和"生成出来对不对"两件事都能一眼看到）。
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LEVEL1 = ROOT / "data/sources/wubi86-level1-codes.tsv"
SINGLE = ROOT / "data/generated/wubi86-single.tsv"
CORE = ROOT / "data/generated/wubi86-core.tsv"

EXPECTED_KEYS = set("gfdsahjklmtrewqyuiopnbvcx")


def rows(path: Path) -> list[list[str]]:
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        out.append(line.split("\t"))
    return out


def main() -> int:
    problems: list[str] = []

    level1 = rows(LEVEL1)
    if len(level1) != 25:
        problems.append(f"一级简码应为 25 条，实际 {len(level1)} 条")

    keys = [r[0] for r in level1]
    chars = [r[1] for r in level1]
    if len(set(keys)) != len(keys):
        problems.append("键位有重复")
    if len(set(chars)) != len(chars):
        problems.append("字有重复")
    if set(keys) != EXPECTED_KEYS:
        problems.append(f"键位集合不符：多 {sorted(set(keys) - EXPECTED_KEYS)} 少 {sorted(EXPECTED_KEYS - set(keys))}")
    for key, char in zip(keys, chars):
        if len(key) != 1 or len(char) != 1:
            problems.append(f"必须是单键单字：{key!r} → {char!r}")

    single_codes: dict[str, list[str]] = {}
    for code, text, _weight in rows(SINGLE):
        single_codes.setdefault(text, []).append(code)
    for char in chars:
        codes = single_codes.get(char)
        if not codes:
            problems.append(f"字不在全码表里：{char}")
        elif not all(2 <= len(c) <= 4 for c in codes):
            # 五笔86 全码有 3 码字（如 地=fbn）与 4 码字；1 码只应来自简码层本身。
            problems.append(f"字的全码长度非法：{char} → {codes}")

    core_rows = rows(CORE)
    core_index = {(code, text) for code, text, _weight in core_rows}
    for key, char in zip(keys, chars):
        if (key, char) not in core_index:
            problems.append(f"生成结果缺少简码行：{key} → {char}")
    one_code = [r for r in core_rows if len(r[0]) == 1]
    if len(one_code) != 25:
        problems.append(f"核心码表中 1 码的行应为 25，实际 {len(one_code)}")
    two_code = [r for r in core_rows if len(r[0]) == 2]
    if len(two_code) != 598:
        problems.append(f"核心码表中 2 码的行应为 598（二级简码 D17-bis），实际 {len(two_code)}")

    if problems:
        for p in problems:
            print(f"❌ {p}")
        return 1
    print(f"✅ 一级简码表通过：{len(level1)} 条，键位与字均唯一，全码一致，生成结果包含全部 25 条")
    return 0


if __name__ == "__main__":
    sys.exit(main())
