#!/usr/bin/env python3
"""五笔86 根序**受控推断**（报告 323 §4 的方法，ADR-382 约束下使用）。

目的：给 `partial` 字生成**候选**根序，供人工复核；**产物quality 不变**，推断结果不进 D25、不进 `full`。

方法（组合式推断 + 码位校验，不做自由搜索）：
1. 用 IDS（D19）把字拆成部件树；每个叶子映射到"已知根序"：
   - 叶子本身是 `full` 字 → 用它的根序；
   - 叶子是标准字根 → `[叶子]`；
   - 否则视为未知 ⇒ 该字推断失败（记录原因）。
2. 顺序拼接后按取码规则裁剪：>4 根取 1·2·3·末；=4 全取；<4 若末位是识别码则按网格反推末笔。
3. **必须与码表逐位对齐**（键位 = 码位），否则失败。
4. 只有唯一候选才输出 `unique`，多候选输出 `ambiguous`，不猜。

用法（仓库根目录）：
  python3 tools/wubi86-root-infer.py [--limit N] [--out build/inference/root-inference.tsv]
"""
from __future__ import annotations

import argparse
import collections
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LEDGER = ROOT / 'build/b0/B0.json'
INVENTORY = ROOT / 'data/learning/wubi86-root-inventory.tsv'
IDS_PATH = ROOT / 'data/sources/ids_lv1.txt'

STROKE_GLYPHS = set('一丨丿丶乙乛亅ノ')

STRUCT_OP = {'⿰': '左右', '⿲': '左右', '⿱': '上下', '⿳': '上下'}
MODIFIER = set('⿴⿵⿶⿷⿸⿹⿺⿻⿼⿽⿾⿿')

GRID = {
    '横': {'左右': 'g', '上下': 'f', '杂合': 'd'},
    '竖': {'左右': 'h', '上下': 'j', '杂合': 'k'},
    '撇': {'左右': 't', '上下': 'r', '杂合': 'e'},
    '捺': {'左右': 'y', '上下': 'u', '杂合': 'i'},
    '折': {'左右': 'n', '上下': 'b', '杂合': 'v'},
}


# 已在本项目数据里确认过的「非字根部件」拆法（不是新猜测：每一条都在 D25 或既有 full 字里出现过）
# 只收**已在 D25 或既有 full 字里确认过**的拆法；未确认的一律留空（推断要受控，不能自我循环）
KNOWN_PARTS: dict[str, list[str]] = {
    '豖': ['豕', '丶'],          # 啄 KEYY（D25）
    '艮': ['彐', '衣', '丶'],    # 根/银/眼/限/退（D25，报告 306）
    '氐': ['氏', '弋', '丶'],    # 柢 SQAY（D25）
    '啇': ['六', '冂', '古'],    # 滴/摘/嫡（D25）
}


def load_inventory() -> dict[str, list[str]]:
    keys: dict[str, list[str]] = collections.defaultdict(list)
    for line in INVENTORY.read_text(encoding='utf-8').splitlines():
        if not line.strip() or line.startswith('#'):
            continue
        fields = line.split('\t')
        if len(fields) >= 2 and len(fields[0]) == 1:
            keys[fields[0]].append(fields[1])
    return keys


def load_ids() -> dict[str, str]:
    out: dict[str, str] = {}
    for line in IDS_PATH.read_text(encoding='utf-8').splitlines():
        if not line.strip() or line.startswith('#'):
            continue
        fields = line.split('\t')
        if len(fields) >= 2 and len(fields[0]) == 1:
            out[fields[0]] = fields[1]
    return out


def structure_of(ids: str) -> str:
    for ch in ids:
        if ch in STRUCT_OP:
            return STRUCT_OP[ch]
    return '杂合' if ids else '杂合'


def leaves(ids: str) -> tuple[list[str], list[str], bool]:
    """返回（顶层叶子序列, 遇到的全部叶子, 是否能完全线性化）。"""
    top: list[str] = []
    flat: list[str] = []

    def walk(node: str, depth: int) -> bool:
        if not node:
            return True
        head = node[0]
        if head in STRUCT_OP or head in MODIFIER:
            n = 3 if head in ('⿲', '⿳') else 2
            parts, rest = [], node[1:]
            ok = True
            for _ in range(n):
                if not rest:
                    ok = False
                    break
                parts.append(rest[0])
                rest = rest[1:]
            for part in parts:
                if part in STRUCT_OP or part in MODIFIER:
                    ok = walk(part, depth + 1) and ok
                    if depth == 0:
                        top.extend(sub_leaves(part))
                else:
                    flat.append(part)
                    if depth == 0:
                        top.append(part)
                rest = rest[n:]
            return ok
        flat.append(node)
        if depth == 0:
            top.append(node)
        return True

    def sub_leaves(node: str) -> list[str]:
        if not node:
            return []
        head = node[0]
        if head in STRUCT_OP or head in MODIFIER:
            n = 3 if head in ('⿲', '⿳') else 2
            out: list[str] = []
            rest = node[1:]
            for _ in range(n):
                if not rest:
                    break
                out.extend(sub_leaves(rest[0]))
                rest = rest[1:]
            return out
        return [node]

    ok = walk(ids, 0)
    return top, flat, ok


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--ledger', default=str(LEDGER))
    parser.add_argument('--limit', type=int, default=0)
    parser.add_argument('--out', default='build/inference/root-inference.tsv')
    args = parser.parse_args()

    entries = json.loads(Path(args.ledger).read_text(encoding='utf-8'))
    keys_of = load_inventory()
    ids_of = load_ids()

    def expand(glyph: str, depth: int = 0) -> list[str] | None:
        """叶子 → 根序。

        规则：**成字字根/键名字在合体字里算一个根**（它们的根序是「自己 + 笔画」，那是单字取码，
        不是部件拆法）。否则用该字的根序；再否则递归 IDS。
        """
        seq_of = rootseq.get(glyph)
        if seq_of:
            tail = seq_of[1:]
            # 成字字根的尾巴若是「纯笔画」（一丨丿丶乙 等），合体内部算一个根；
            # 若尾巴里含真部件（如 卯=[卯,丿,卩]），说明它是 R9-bis 的"报户口+部件尾"，要展开。
            if seq_of[0] == glyph and tail and all(t in STROKE_GLYPHS for t in tail):
                return [glyph]
            return list(seq_of)
        if glyph in keys_of:
            return [glyph]
        if glyph in KNOWN_PARTS:
            return list(KNOWN_PARTS[glyph])
        sub = ids_of.get(glyph)
        if depth < 3 and sub and sub != glyph:
            _, flat_sub, _ = leaves(sub)
            if len(flat_sub) >= 2:
                out: list[str] = []
                for inner in flat_sub:
                    part = expand(inner, depth + 1)
                    if part is None:
                        return None
                    out.extend(part)
                return out
        return None
    rootseq = {e['char']: [c for c in (e.get('components') or []) if c]
               for e in entries if e['quality'] == 'full'}

    targets = [e for e in entries if e['quality'] != 'full']
    targets.sort(key=lambda e: -(e.get('frequency') or 0))
    if args.limit:
        targets = targets[: args.limit]

    stats = collections.Counter()
    rows = []
    for entry in targets:
        char, code = entry['char'], entry['code']
        ids = ids_of.get(char)
        if not ids:
            stats['无 IDS'] += 1
            continue
        top, flat, _ = leaves(ids)
        seq: list[str] = []
        unknown: list[str] = []
        for leaf in flat:
            part = expand(leaf)
            if part is None:
                seq.append(leaf)
                unknown.append(leaf)
            else:
                seq.extend(part)
        structure = structure_of(ids)
        if len(seq) < 2:
            stats['根数不足'] += 1
            rows.append((char, code, '', '', structure, '', 'fail',
                         f'IDS 只解析出 {len(seq)} 段（{"".join(seq) or "空"}），不足以推断'))
            continue
        # 按取码规则裁剪
        cand = list(seq)
        if len(cand) > 4:
            cand = [cand[0], cand[1], cand[2], cand[-1]]
        derivation = f'IDS 组合：{"+".join(flat)} → {"".join(cand)}（{len(seq)} 根取{"一二三末" if len(seq) > 4 else "全部"}）'
        if len(cand) < 4:
            last = code[-1]
            strokes = [s for s, m in GRID.items() if m[structure] == last]
            if len(strokes) != 1:
                stats['末位非识别码'] += 1
                rows.append((char, code, '', '', structure, '', 'fail', f'根数 {len(cand)} 且末位 {last} 不是 {structure} 结构的识别码'))
                continue
            cand.append(f'识别码{strokes[0]}')
            derivation += f'；末笔 {strokes[0]}（{structure}）⇒ 识别码 {last}'
        if len(cand) != len(code):
            stats['长度不符'] += 1
            rows.append((char, code, ' '.join(cand), '', structure, '', 'fail',
                         f'根数+识别码 {len(cand)} 与码长 {len(code)} 不符（{derivation}）'))
            continue
        # 校验键位
        keys = []
        bad = []
        for index, glyph in enumerate(cand):
            if glyph.startswith('识别码'):
                keys.append(code[index])
                continue
            options = keys_of.get(glyph, [])
            if code[index] not in options:
                bad.append(f'第 {index + 1} 位 {glyph} 不在 {code[index]} 键')
            keys.append(code[index] if code[index] in options else (options[0] if options else '?'))
        if bad:
            stats['键位不符'] += 1
            rows.append((char, code, ' '.join(cand), ''.join(keys), structure, '', 'fail',
                         '；'.join(bad) + f'（未知部件：{"".join(unknown) or "无"}）'))
            continue
        decision = 'unique' if len(seq) <= 4 else 'unique-by-rule'
        stats[decision] += 1
        rows.append((char, code, ' '.join(cand), ''.join(keys), structure, '', decision, derivation))

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    header = '# 五笔86 根序受控推断（报告 323 §4；仅候选，不入产品数据）\n# char\tcode\troots\tkeys\tstructure\trecognition\tstatus\tevidence'
    lines = [header] + ['\t'.join(r) for r in rows]
    out.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print(f'写入 {out}：{len(rows)} 条；{dict(stats)}')
    print(f'（其中 unique/unique-by-rule {stats["unique"] + stats["unique-by-rule"]} 条可交人工复核）')
    return 0


if __name__ == '__main__':
    sys.exit(main())
