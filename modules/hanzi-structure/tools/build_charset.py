#!/usr/bin/env python3
"""学习字表：GB2312-1980 一级 ∪ 一/二/三级简码表用字（ADR-377）。

为什么是并集：`学` 覆盖常用字，`练` 覆盖简码题；两者字表不一时会出现「练得到、学不到」
（报告 304 F5：三级简码 3,362 条里 1,264 个字的字不在 GB2312 一级里）。

输入（全部已登记）：
  data/generated/gb2312-level1.txt          GB2312-1980 一级汉字区（3,755，公开国家标准）
  data/sources/wubi86-level1-codes.tsv      D17 一级简码 25
  data/sources/wubi86-level2-codes.tsv      D17-bis 二级简码 598
  data/sources/wubi86-level3-codes.tsv      D17-ter 三级简码 3,362

输出：data/generated/learning-chars.tsv   `字\t来源`（gb2312-l1 / l1 / l2 / l3，可多个）
只做并集与去重，不改任何字、不引入新来源；顺序无意义（`build_b0.py` 按词频排）。
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'data/generated/learning-chars.tsv'
INPUTS = [
    ('gb2312-l1', ROOT / 'data/generated/gb2312-level1.txt', 0),
    ('l1', ROOT / 'data/sources/wubi86-level1-codes.tsv', 1),
    ('l2', ROOT / 'data/sources/wubi86-level2-codes.tsv', 1),
    ('l3', ROOT / 'data/sources/wubi86-level3-codes.tsv', 1),
]


def main() -> int:
    origins: dict[str, list[str]] = {}
    for name, path, column in INPUTS:
        if not path.is_file():
            print(f'缺少输入：{path}', file=sys.stderr)
            return 1
        for line in path.read_text(encoding='utf-8').splitlines():
            if not line or line.startswith('#'):
                continue
            char = line.split('\t')[column].strip()
            if len(char) != 1:
                continue
            bucket = origins.setdefault(char, [])
            if name not in bucket:
                bucket.append(name)
    rows = ['# 学习字表（ADR-377）：GB2312-1980 一级 ∪ 一/二/三级简码表用字；来源按上面输入顺序取前缀。',
            '# char\torigin']
    for char in sorted(origins):
        rows.append(f'{char}\t{'|'.join(origins[char])}')
    OUT.write_text('\n'.join(rows) + '\n', encoding='utf-8')
    from collections import Counter
    only_short = sum(1 for v in origins.values() if 'gb2312-l1' not in v)
    print(f'写入 {OUT.relative_to(ROOT)}：{len(origins)} 字（其中仅简码表用字 {only_short}）')
    print(dict(Counter(name for v in origins.values() for name in v)))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
