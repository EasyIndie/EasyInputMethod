#!/usr/bin/env python3
"""教学运行时资源（ADR-311）的格式、体积与安全断言。

资源是预渲染 TSV（字 / 全码 / 质量 / 讲解），宿主只展示不推导。这里钉死：
1. 体积 ≤ 512 KiB（ADR-309/311 预算，报告 252）；
2. 四列、无制表符污染、无私有区字形、质量取值合法、字不重复；
3. `partial` 必须带「拆解待核验」，`unknown` 只说缺资料——与 `b0_query.py` 的消费契约一致。
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
RUNTIME = ROOT / 'data/generated/B0-runtime.tsv'
BUDGET = 512 * 1024


class B0RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.raw = RUNTIME.read_bytes()
        self.lines = [line for line in self.raw.decode('utf-8').splitlines() if line and not line.startswith('#')]

    def test_within_size_budget(self):
        self.assertLessEqual(len(self.raw), BUDGET, f'运行时资源 {len(self.raw)} 字节，超 {BUDGET} 预算')

    def test_columns_and_uniqueness(self):
        self.assertTrue(self.lines)
        seen = set()
        for line in self.lines:
            fields = line.split('\t')
            self.assertEqual(len(fields), 4, line)
            char, code, quality, text = fields
            self.assertEqual(len(char), 1, line)
            self.assertNotIn(char, seen, f'重复字：{char}')
            seen.add(char)
            self.assertIn(quality, {'full', 'partial', 'unknown'}, line)
            self.assertTrue(text.strip(), line)
            if code:
                self.assertTrue(code.isascii() and code.islower(), line)

    def test_no_private_use_characters(self):
        text = self.raw.decode('utf-8')
        bad = [hex(ord(ch)) for ch in text if 0xE000 <= ord(ch) <= 0xF8FF or ord(ch) >= 0xF0000]
        self.assertEqual(bad, [], f'运行时资源含私有区字形：{bad[:5]}')

    def test_quality_contract(self):
        for line in self.lines:
            _char, _code, quality, text = line.split('\t')
            if quality == 'partial':
                self.assertIn('拆解待核验', text, line)
            if quality == 'unknown':
                self.assertIn('暂无', text, line)


if __name__ == '__main__':
    unittest.main()
