#!/usr/bin/env python3
"""五笔86 根序判定表（D25，报告 306 / ADR-382）的契约。

判的是「人可以复核」这件事：
1. 每一行的字根都能在标准字根清单里找到，且**该字根在那一键上**（码位—字根—键位三元组对齐）；
2. 根数符合 R3（码长 或 码长−1）；码长−1 时末位必须是识别码网格能推出的字母；
3. 表里不带私有区字形、不带占位，且被判定的字在码表里确实存在。
"""
from pathlib import Path
import collections
import unittest

ROOT = Path(__file__).resolve().parents[3]
TABLE = ROOT / 'data/learning/wubi86-root-order.tsv'
ERRATA = ROOT / 'data/learning/wubi86-code-errata.tsv'
INVENTORY = ROOT / 'data/learning/wubi86-root-inventory.tsv'
CODES = ROOT / 'data/generated/wubi86-single.tsv'

GRID = {
    '横': {'左右': 'g', '上下': 'f', '杂合': 'd'},
    '竖': {'左右': 'h', '上下': 'j', '杂合': 'k'},
    '撇': {'左右': 't', '上下': 'r', '杂合': 'e'},
    '捺': {'左右': 'y', '上下': 'u', '杂合': 'i'},
    '折': {'左右': 'n', '上下': 'b', '杂合': 'v'},
}


def rows(path: Path):
    for line in path.read_text(encoding='utf-8').splitlines():
        if not line.strip() or line.startswith('#'):
            continue
        yield line.split('\t')


def load_codes() -> dict[str, str]:
    codes: dict[str, str] = {}
    for parts in rows(CODES):
        code, char = parts[0], parts[1]
        if len(char) == 1 and len(code) > len(codes.get(char, '')):
            codes[char] = code
    return codes


class RootOrderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        everything = list(rows(TABLE))
        cls.blocked = [p for p in everything if p[6] == 'blocked']
        cls.entries = [p for p in everything if p[6] != 'blocked']
        cls.codes = load_codes()
        cls.keys: dict[str, set[str]] = collections.defaultdict(set)
        for parts in rows(INVENTORY):
            if len(parts) >= 2 and len(parts[0]) == 1:
                cls.keys[parts[0]].add(parts[1])

    def test_table_is_not_empty(self):
        self.assertGreaterEqual(len(self.entries), 20, '根序判定表为空或过短')

    def test_positions_align_with_code(self):
        for parts in self.entries:
            char, components, keys, code = parts[0], parts[1].split(), parts[2], parts[3]
            self.assertEqual(len(char), 1)
            self.assertIn(char, self.codes, f'{char} 不在码表里')
            self.assertEqual(code, self.codes[char], f'{char} 的码与码表不一致')
            self.assertEqual(len(keys), len(components), f'{char} keys 与字根数不一致')
            self.assertIn(len(components), (len(code), len(code) - 1),
                          f'{char} 根数 {len(components)} 与码长 {len(code)} 不符（R3）')
            for index, glyph in enumerate(components):
                self.assertIn(glyph, self.keys, f'{char} 的字根 {glyph} 不在标准清单里')
                self.assertIn(code[index], self.keys[glyph],
                              f'{char} 第 {index + 1} 位：{glyph} 不在 {code[index]} 键上')

    def test_recognition_derivable(self):
        for parts in self.entries:
            char, components, code, structure, last = (
                parts[0], parts[1].split(), parts[3], parts[4], parts[5])
            if len(components) == len(code):
                self.assertEqual(last, '', f'{char} 四根取全时不应有末笔')
                continue
            self.assertIn(last, GRID, f'{char} 缺末笔')
            self.assertIn(structure, GRID[last], f'{char} 缺结构')
            self.assertEqual(GRID[last][structure], code[-1],
                             f'{char} 识别码应为 {GRID[last][structure]}，码表是 {code[-1]}')

    def test_blocked_rows_are_explained(self):
        self.assertGreater(len(self.blocked), 0, '没有 blocked 行，说明还没开始全量判定')
        for parts in self.blocked:
            self.assertEqual(parts[1], '', f'{parts[0]} 已 blocked 却带了字根')
            self.assertGreaterEqual(len(parts[8].strip()), 8, f'{parts[0]} 的卡点说明太短')

    def test_rows_are_unique(self):
        chars = [p[0] for p in self.entries + self.blocked]
        dup = {c for c in chars if chars.count(c) > 1}
        self.assertEqual(dup, set(), f'重复条目：{dup}')

    def test_code_errata_is_justified(self):
        """ADR-384：勘误必须带同族字与推导，且不能与码表原值相同。"""
        entries = list(rows(ERRATA))
        self.assertGreaterEqual(len(entries), 1, '勘误表为空')
        for parts in entries:
            char, wrong, right, family, status, evidence = (
                parts[0], parts[1], parts[2], parts[3], parts[4], parts[5])
            self.assertIn(status, ('active', 'pending', 'withdrawn'), f'{char} 的 status 非法')
            self.assertEqual(len(char), 1)
            self.assertIn(char, self.codes, f'{char} 不在码表里')
            self.assertNotEqual(wrong, right, f'{char} 的勘误前后相同')
            self.assertEqual(len(wrong), len(right), f'{char} 勘误改变了码长')
            self.assertGreaterEqual(len(family), 1, f'{char} 缺同族字')
            self.assertGreaterEqual(len(evidence), 12, f'{char} 的勘误说明太短')

    def test_no_private_use_glyphs(self):
        text = TABLE.read_text(encoding='utf-8')
        bad = [hex(ord(ch)) for ch in text if 0xE000 <= ord(ch) <= 0xF8FF or ord(ch) >= 0xF0000]
        self.assertEqual(bad, [], f'含私有区字形：{bad[:5]}')


if __name__ == '__main__':
    unittest.main()
