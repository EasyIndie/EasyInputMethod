#!/usr/bin/env python3
"""用 cjk-decomp（Apache-2.0）为 B0 非 full 字生成完整拆字候选。

方法：把 cjk-decomp 的分解树切成恰好 n 或 n-1 个叶子（n = 全码长度），
枚举叶子顺序，只保留**每个叶子的五笔键位都与码位一致**的候选；
n-1 个叶子时还要求末位识别码的结构与 IDS 结构一致。多个候选视为歧义，不猜。

输出：字 / 组件 / 全码 / 键位 / 来源 / 证据（TSV），供 build_b0 --coverage-decomp 使用。
"""
from __future__ import annotations

import argparse
import itertools
import json
from pathlib import Path

OPS = set('⿰⿱⿲⿳⿴⿵⿶⿷⿸⿹⿺⿻')
RECOGNITION = {
    'g': ('横', '左右'), 'f': ('横', '上下'), 'd': ('横', '杂合'),
    'h': ('竖', '左右'), 'j': ('竖', '上下'), 'k': ('竖', '杂合'),
    't': ('撇', '左右'), 'r': ('撇', '上下'), 'e': ('撇', '杂合'),
    'y': ('捺', '左右'), 'u': ('捺', '上下'), 'i': ('捺', '杂合'),
    'n': ('折', '左右'), 'b': ('折', '上下'), 'v': ('折', '杂合'),
}

# cjk-decomp uses 36 CJK stroke glyphs; normalize to the five basic glyphs.
STROKE_NORMALIZE = {
    '㇐': '一', '㇀': '一',
    '㇑': '丨',
    '㇒': '丿', '㇓': '丿',
    '㇔': '丶', '㇏': '丶',
}


def normalize_leaf(leaf: str) -> str:
    return STROKE_NORMALIZE.get(leaf, leaf)


def rows(path: Path, minimum: int = 2):
    for line in path.read_text(encoding='utf-8').splitlines():
        if not line or line.startswith('#'):
            continue
        parts = line.split('\t')
        if len(parts) >= minimum:
            yield parts


def load_keys(paths: list[Path]) -> dict[str, str]:
    keys: dict[str, str] = {}
    for path in paths:
        for parts in rows(path):
            if len(parts) >= 2:
                for glyph in parts[1]:
                    keys.setdefault(glyph, parts[0].lower())
    return keys


def load_traditional(path: Path) -> dict[str, str]:
    out = {}
    for parts in rows(path, 2):
        if len(parts[0]) == 1:
            out[parts[0]] = parts[1].lower()
    return out


def load_tree(path: Path) -> dict[str, list[str]]:
    tree = {}
    for line in path.read_text(encoding='utf-8').splitlines():
        if ':' not in line:
            continue
        char, rest = line.split(':', 1)
        if '(' not in rest or not rest.endswith(')'):
            continue
        _kind, comps = rest.split('(', 1)
        parts = [c for c in comps[:-1].split(',') if c]
        if parts:
            tree[char] = parts
    return tree


def load_structures(path: Path) -> dict[str, str]:
    out = {}
    for line in path.read_text(encoding='utf-8').splitlines():
        parts = line.split('\t')
        if len(parts) < 2:
            continue
        for seq in parts[1].split(';'):
            seq = seq.split('(')[0].strip()
            if seq and seq[0] in OPS:
                out[parts[0]] = ('左右' if seq[0] in '⿰⿲'
                                 else '上下' if seq[0] in '⿱⿳' else '杂合')
                break
    return out


def all_cuts(tree: dict[str, list[str]], keys: dict[str, str],
             node: str, max_leaves: int) -> list[list[str]]:
    """返回所有“展开到不超过 max_leaves 个叶子”的叶子序列（树序）。"""
    if node not in tree or node in keys:
        return [[node]] if max_leaves >= 1 else []
    comps = tree[node]
    if max_leaves < len(comps):
        return []

    def rec(index: int, budget: int) -> list[list[str]]:
        if index == len(comps):
            return [[]]
        out: list[list[str]] = []
        for leaves in all_cuts(tree, keys, comps[index], budget - (len(comps) - index - 1)):
            if len(leaves) > budget:
                continue
            for rest in rec(index + 1, budget - len(leaves)):
                out.append(leaves + rest)
        return out

    return rec(0, max_leaves)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--corpus', required=True)
    parser.add_argument('--cjk-decomp', required=True)
    parser.add_argument('--ids', required=True)
    parser.add_argument('--readable-keys', required=True)
    parser.add_argument('--key-roots', required=True)
    parser.add_argument('--traditional-keys', required=True)
    parser.add_argument('--out', required=True)
    parser.add_argument('--report', required=True)
    args = parser.parse_args()

    corpus = json.loads(Path(args.corpus).read_text(encoding='utf-8'))
    tree = load_tree(Path(args.cjk_decomp))
    keys = load_keys([Path(args.readable_keys), Path(args.key_roots)])
    keys.update(load_traditional(Path(args.traditional_keys)))
    structures = load_structures(Path(args.ids))

    accepted = []
    counts = {'targets': 0, 'accepted': 0, 'ambiguous': 0,
              'no_tree': 0, 'no_cut': 0, 'key_mismatch': 0, 'recognition_mismatch': 0}
    for entry in corpus:
        if entry.get('quality') == 'full':
            continue
        counts['targets'] += 1
        char = entry['char']
        code = entry.get('code') or ''
        if char not in tree or not code:
            counts['no_tree'] += 1
            continue
        structure = structures.get(char)
        candidates = set()
        cut_any = False
        key_bad = False
        rec_bad = False
        for want in (len(code), len(code) - 1):
            if want < 2:
                continue
            for leaves in all_cuts(tree, keys, char, want):
                if len(leaves) != want:
                    continue
                cut_any = True
                for perm in itertools.permutations(leaves):
                    norm = tuple(normalize_leaf(leaf) for leaf in perm)
                    if norm in candidates:
                        continue
                    if not all(keys.get(leaf) == key for leaf, key in zip(norm, code)):
                        key_bad = True
                        continue
                    if len(norm) == len(code) - 1:
                        key = code[-1]
                        if key not in RECOGNITION or structure is None or RECOGNITION[key][1] != structure:
                            rec_bad = True
                            continue
                    candidates.add(norm)
        if not cut_any:
            counts['no_cut'] += 1
            continue
        if not candidates:
            counts['recognition_mismatch' if rec_bad else 'key_mismatch'] += 1
            continue
        if len(candidates) > 1:
            counts['ambiguous'] += 1
            continue
        components = list(next(iter(candidates)))
        accepted.append((char, components, code, ''.join(code[:len(components)]),
                         'D24', f'cjk-decomp 树切分（Apache-2.0）+ 码位键位匹配'
                                + (f' + IDS 结构 {structure}' if len(components) == len(code) - 1 else '')))
        counts['accepted'] += 1

    out = ['# cjk-decomp（Apache-2.0）为 B0 非 full 字生成的完整拆字，项目自编编排 CC-BY-SA-4.0。',
           '# 每个叶子的五笔键位必须与码位一致；n-1 个叶子时识别码结构必须与 IDS 一致；歧义不猜。',
           '# char\tcomponents\tcode\tkeys\tsource\tevidence']
    for char, components, code, keys_text, source, evidence in accepted:
        out.append(f'{char}\t{" ".join(components)}\t{code}\t{keys_text}\t{source}\t{evidence}')
    Path(args.out).write_text('\n'.join(out) + '\n', encoding='utf-8')
    report = {'generator': 'modules/hanzi-structure/tools/coverage_decomp.py',
              'cjkDecomp': str(args.cjk_decomp), 'counts': counts}
    Path(args.report).write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(counts, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
