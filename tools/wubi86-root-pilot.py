#!/usr/bin/env python3
"""五笔86 根序试点抽样（ADR-382 / T-ROOT86）。

从 B0 账本里按「首个不符位次」分层抽样，输出一张待判定表：
每条给出全码、D2 组件与键位、IDS、结构、每个码位上的标准字根候选，
判定列留空，由人或模型补 `roots / decision / evidence / seconds`。

只读本地数据，不联网；不修改任何产品数据。
"""
from __future__ import annotations

import argparse
import collections
import json
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GROUPS = ('1', '2', '3', '4', 'other')


def load_roots(path: Path) -> dict[str, list[str]]:
    by_key: dict[str, list[str]] = collections.defaultdict(list)
    for line in path.read_text(encoding='utf-8').splitlines():
        if not line.strip() or line.startswith('#'):
            continue
        fields = line.split('\t')
        if len(fields) >= 2:
            by_key[fields[1]].append(fields[0])
    return by_key


def load_scope(path: Path) -> set[str]:
    return {line.strip() for line in path.read_text(encoding='utf-8').splitlines()
            if line.strip() and not line.startswith('#')}


def classify(entry: dict) -> str:
    mismatch = entry.get('positionMismatch') or []
    if mismatch:
        first = str(mismatch[0])
        return first if first in ('1', '2', '3', '4') else 'other'
    return 'other'


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--ledger', default='build/b0/B0.json')
    parser.add_argument('--bundle', default='build/wubi86-std-1.0')
    parser.add_argument('--scope', default='data/generated/gb2312-level1.txt')
    parser.add_argument('--per-group', default='3,12,10,3,2')
    parser.add_argument('--seed', type=int, default=86)
    parser.add_argument('--out', default='build/pilot/pilot-30.tsv')
    args = parser.parse_args()

    ledger = json.loads(Path(args.ledger).read_text(encoding='utf-8'))
    by_key = load_roots(Path(args.bundle) / 'roots.tsv')
    scope = load_scope(Path(args.scope))
    quotas = [int(x) for x in args.per_group.split(',')]

    buckets: dict[str, list[dict]] = collections.defaultdict(list)
    for entry in ledger:
        if entry['char'] not in scope or entry['quality'] != 'partial':
            continue
        buckets[classify(entry)].append(entry)

    rng = random.Random(args.seed)
    picked: list[dict] = []
    plan = []
    for group, quota in zip(GROUPS, quotas):
        pool = sorted(buckets.get(group, []), key=lambda e: e['char'])
        take = rng.sample(pool, min(quota, len(pool)))
        plan.append(f'{group}:{len(take)}/{len(pool)}')
        picked.extend(take)
    picked.sort(key=lambda e: e['char'])

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    header = ['#', 'char', 'code', 'quality', 'firstMismatch', 'd2Components', 'd2Keys',
              'structure', 'ids', 'candidates', 'roots', 'decision', 'evidence', 'seconds']
    lines = ['# 五笔86 根序试点（ADR-382）：待判定表；roots 用空格分隔、按码位顺序；'
             'decision ∈ fix/keep-partial/new-root', '\t'.join(header)]
    for index, entry in enumerate(picked, start=1):
        code = entry['code']
        comps = [c for c in (entry.get('components') or []) if c]
        keys = [k for k in (entry.get('keys') or []) if k]
        positions = len(code) - (1 if entry.get('recognition') else 0)
        cand = []
        for i in range(min(positions, 4)):
            options = sorted(by_key.get(code[i], []))
            cand.append(f'{i + 1}:{"|".join(options[:8])}')
        lines.append('\t'.join([
            str(index), entry['char'], code, entry['quality'],
            ','.join(str(x) for x in (entry.get('positionMismatch') or [])) or '-',
            ' '.join(comps) or '-', ' '.join(keys) or '-',
            entry.get('structure') or '-', entry.get('ids') or '-',
            ' ; '.join(cand),
            '', '', '', '',
        ]))
    out.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print(f'写入 {out}：{len(picked)} 条（分层 {", ".join(plan)}，seed={args.seed}）')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
