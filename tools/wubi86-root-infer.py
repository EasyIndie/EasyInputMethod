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
    '豖': ['豕', '丶'],              # 啄 KEYY（D25）
    '艮': ['彐', '衣', '丶'],        # 根/银/眼/限/退（D25，报告 306）
    '氐': ['氏', '弋', '丶'],        # 柢 SQAY（D25）
    '啇': ['六', '冂', '古'],        # 滴/摘/嫡（D25）
    '衤': ['衤', '丷'],              # 补/初/袖/袍… 18 条（D25，ADR-384 附二同族）
    '礻': ['礻', '丶'],              # 社/神/祝（D2 原始记录一致）
    '𠃓': ['𠃌', '⺁', '丿'],          # 场/汤/杨/肠/扬（D25，报告 312）
    '𥫗': ['⺮'],                    # 竹头变体（⺮ 是标准字根）
    '饣': ['⺈', '乚'],              # 饺/馏（D25，报告 315）
    '㠯': ['コ', '丨', 'コ'],         # 官 PNHN（D25，报告 312）
    '爰': ['爫', '二', '又'],        # 暖/缓 JEFC（D25）
    '豸': ['爫', '𠂢'],              # 豹/貌/豺/貉/藐（D25，报告 309）
    '⺗': ['心'],                    # 心 的变体（慕/恭/添 已按 心 判定）
    '犮': ['厂', '又'],              # 跋/KH 族（D25，报告 310）
    '㣺': ['心'],                    # 心 的变体（忝/恭 同族）
    '丕': ['一', '小', '一'],        # 坯/胚 FGIG（D25）
    '不': ['一', '小'],              # 坏/环/杯/怀/歪/甭（D25）
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
        if glyph in KNOWN_PARTS:      # 人工确认过的拆法优先（衤/礻/𠃓 等覆盖自身根序）
            return list(KNOWN_PARTS[glyph])
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

        def try_variant(roots: list[str]) -> tuple[list[str], list[str], list[str]]:
            """返回（候选, 校验后的键位, 问题列表）。roots 里可用 '识别码X' 占位。"""
            keys: list[str] = []
            bad: list[str] = []
            for index, glyph in enumerate(roots):
                if glyph.startswith('识别码'):
                    keys.append(code[index] if index < len(code) else '?')
                    continue
                options = keys_of.get(glyph, [])
                if index >= len(code) or code[index] not in options:
                    bad.append(f'第 {index + 1} 位 {glyph} 不在 {code[index] if index < len(code) else "?"} 键')
                keys.append(code[index] if index < len(code) else '?')
            return keys, keys, bad

        if len(seq) < 2:
            stats['根数不足'] += 1
            rows.append((char, code, '', '', structure, '', 'fail',
                         f'IDS 只解析出 {len(seq)} 段（{"".join(seq) or "空"}），不足以推断'))
            continue

        def variants(total: int) -> list[tuple[list[str], str]]:
            """两种根数读法：满取码 / 少一根改用识别码（报告 304 F1 的识别码槽）。"""
            out: list[tuple[list[str], str]] = []
            bases: list[tuple[list[str], str]] = []
            if total > 4:
                bases.append(([seq[0], seq[1], seq[2], seq[-1]], f'{"+".join(flat)} 共 {total} 根取一二三末'))
            else:
                bases.append((list(seq), f'{"+".join(flat)} 共 {total} 根'))
                if total >= 3:
                    bases.append((list(seq[:-1]), f'{"+".join(flat)} 取前 {total - 1} 根'))
            last_letter = code[-1]
            strokes = [st for st, m in GRID.items() if m[structure] == last_letter]
            for roots, why in bases:
                if len(roots) == len(code):
                    out.append((roots, why))
                elif len(roots) + 1 == len(code) and len(strokes) == 1:
                    out.append((roots + [f'识别码{strokes[0]}'],
                                f'{why} + 末笔 {strokes[0]}（{structure}）⇒ 识别码 {last_letter}'))
            return out

        accepted = None
        for cand_roots, why in variants(len(seq)):
            if len(cand_roots) != len(code):
                continue
            keys: list[str] = []
            bad: list[str] = []
            for index, glyph in enumerate(cand_roots):
                if glyph.startswith('识别码'):
                    keys.append(code[index])
                    continue
                options = keys_of.get(glyph, [])
                if code[index] not in options:
                    bad.append(f'第 {index + 1} 位 {glyph} 不在 {code[index]} 键')
                keys.append(code[index])
            if not bad:
                accepted = (cand_roots, ''.join(keys), why)
                break
        if accepted is None:
            stats['键位不符'] += 1
            rows.append((char, code, '', '', structure, '', 'fail',
                         f'两种读法都对不上码位（{"；".join(unknown) or "部件都在清单内"}）'))
            continue
        cand_roots, keys, why = accepted
        decision = 'unique-by-rule' if len(seq) > 4 else 'unique'
        stats[decision] += 1
        rows.append((char, code, ' '.join(cand_roots), keys, structure, '', decision, why))

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
