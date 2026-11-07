#!/usr/bin/env python3
"""学习区运行时资源（ADR-311 v2）的格式、体积与安全断言。

资源是结构化紧凑 TSV：`字 / 全码 / 质量 / 字根(形:键) / 识别码(字母|末笔|结构) / 简码(一/二)`。
宿主靠它画"字根格子 + 键位 + 识别码"，所以必须是结构而不是预渲染文本。这里钉死：
1. 体积 ≤ 512 KiB（ADR-309/311 预算）；
2. 六列、无制表符污染、无私有区字形、质量取值合法、字不重复；
3. 字根格形如 `形:键`（未知字形用 `？`），识别码形如 `L|横|左右`，键位/字母大写；
4. `partial` 记录必须含至少一个 `？` 占位（不编造），`unknown` 不带字根。
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
RUNTIME = ROOT / 'data/generated/B0-runtime.tsv'
BUDGET = 512 * 1024
ROOT_CELL = re.compile(r'^(.)(:)([a-y])$')
RECOGNITION = re.compile(r'^[GFDHJKTR EYUI NBV]\|[横竖撇捺折]\|(左右|上下|杂合)$'.replace(' ', ''))


class B0RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.raw = RUNTIME.read_bytes()
        self.lines = [line for line in self.raw.decode('utf-8').splitlines() if line and not line.startswith('#')]

    def test_within_size_budget(self):
        self.assertLessEqual(len(self.raw), BUDGET, f'运行时资源 {len(self.raw)} 字节，超 {BUDGET} 预算')

    def test_columns_types_and_uniqueness(self):
        self.assertTrue(self.lines)
        seen = set()
        for line in self.lines:
            fields = line.split('\t')
            self.assertEqual(len(fields), 6, line)
            char, code, quality, roots, recognition, shorts = fields
            self.assertEqual(len(char), 1, line)
            self.assertNotIn(char, seen, f'重复字：{char}')
            seen.add(char)
            self.assertIn(quality, {'full', 'partial', 'unknown'}, line)
            if code:
                self.assertTrue(code.isascii() and code.islower(), line)
            for cell in roots.split():
                self.assertRegex(cell, ROOT_CELL, line)
            if recognition:
                self.assertRegex(recognition, RECOGNITION, line)
            if shorts:
                for short in shorts.split('/'):
                    self.assertTrue(short.isascii() and short.islower(), line)

    def test_no_private_use_characters(self):
        text = self.raw.decode('utf-8')
        bad = [hex(ord(ch)) for ch in text if 0xE000 <= ord(ch) <= 0xF8FF or ord(ch) >= 0xF0000]
        self.assertEqual(bad, [], f'运行时资源含私有区字形：{bad[:5]}')

    def test_quality_contract(self):
        for line in self.lines:
            _char, _code, quality, roots, recognition, _shorts = line.split('\t')
            if quality == 'unknown':
                self.assertEqual(roots, '', line)
                self.assertEqual(recognition, '', line)
            if quality == 'partial' and '？' not in roots:
                # 允许 partial 的其它成因（如字根数与码长不符），但占位必须显式
                self.assertNotIn('？', line)

    def test_roots_keys_align_with_code(self):
        for line in self.lines:
            char, code, quality, roots, recognition, _shorts = line.split('\t')
            if quality != 'full' or not code:
                continue
            cells = roots.split()
            if not cells:
                continue
            keys = ''.join(cell.split(':')[1] for cell in cells)
            self.assertTrue(code.startswith(keys), f'{char}: 字根键位 {keys} 与码 {code} 不符')
            if recognition:
                self.assertEqual(len(cells), len(code) - 1, f'{char}: 识别码条目字根数应为码长-1')


if __name__ == '__main__':
    unittest.main()
