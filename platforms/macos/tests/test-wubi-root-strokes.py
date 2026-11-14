"""N2/N4 D18 数据契约：成字字根真实笔顺 + D2 漏拆完整拆字（ADR-355 / 报告 281）。"""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
MODULE = ROOT / 'modules/hanzi-structure'
STROKES = ROOT / 'data/learning/wubi86-root-strokes.tsv'
DECOMP = ROOT / 'data/learning/wubi86-complete-decomp.tsv'
CORPUS = MODULE / 'corpus/B0.json'
GLYPHS = set('一丨丿丶乙')


def rows(path):
    return [line.split('\t') for line in path.read_text(encoding='utf-8').splitlines()
            if line and not line.startswith('#')]


class RootStrokeTests(unittest.TestCase):
    def test_stroke_rows_are_well_formed(self):
        data = rows(STROKES)
        self.assertGreaterEqual(len(data), 50)
        seen = set()
        for char, text, count, source, evidence in data:
            self.assertEqual(len(char), 1, char)
            self.assertNotIn(char, seen, f'重复字 {char}')
            seen.add(char)
            strokes = text.split()
            self.assertTrue(strokes, char)
            self.assertTrue(all(s in GLYPHS for s in strokes), f'{char}: 非五类笔画 {strokes}')
            self.assertEqual(int(count), len(strokes), f'{char}: count 与序列长度不符')
            self.assertEqual(source, 'D18')
            self.assertTrue(evidence)
        self.assertEqual(seen & set('一丨丿丶乙'), set('一丨丿丶乙'), '五类基本笔画本身也要有正条')

    def test_all_b0_radical_chars_are_covered(self):
        entries = json.loads(CORPUS.read_text(encoding='utf-8'))
        radical_chars = {e['char'] for e in entries if e['class'] == 'radical-char'}
        expected = {row[0]: row[1].split() for row in rows(STROKES)}
        self.assertEqual(radical_chars - set(expected), set(), 'B0 成字字根缺 D18 笔顺')
        for entry in entries:
            if entry['char'] in radical_chars:
                self.assertEqual(entry.get('strokesKind'), 'writing', entry['char'])
                self.assertEqual(entry.get('strokesSource'), 'D18', entry['char'])
                self.assertEqual(entry.get('strokes'), expected[entry['char']], entry['char'])


class CompleteDecompTests(unittest.TestCase):
    def test_rows_are_well_formed_and_cover_d2_gaps(self):
        data = rows(DECOMP)
        self.assertEqual(len(data), 8)
        codes = {}
        for line in (ROOT / 'data/generated/wubi86-single.tsv').read_text(encoding='utf-8').splitlines():
            if not line or line.startswith('#'):
                continue
            fields = line.split('\t')
            if len(fields) >= 2 and len(fields[1]) == 1 and len(fields[0]) > len(codes.get(fields[1], '')):
                codes[fields[1]] = fields[0]
        for char, text, code, source, evidence in data:
            components = text.split()
            self.assertTrue(components, char)
            self.assertEqual(codes.get(char), code, f'{char}: 全码不符')
            self.assertEqual(source, 'D18')
            self.assertTrue(evidence)
            self.assertIn(len(components), (len(code), len(code) - 1), f'{char}: 组件数与码长不符')
            for component in components:
                self.assertFalse(any(0xE000 <= ord(c) <= 0xF8FF or ord(c) >= 0xF0000 for c in component),
                                 f'{char}: 组件含 PUA')

    def test_b0_entries_use_d18_for_gaps(self):
        entries = {e['char']: e for e in json.loads(CORPUS.read_text(encoding='utf-8'))}
        expected = {row[0]: row[1].split() for row in rows(DECOMP)}
        for char, components in expected.items():
            entry = entries[char]
            self.assertEqual(entry['componentsSource'], 'D18', char)
            self.assertEqual(entry['quality'], 'full', char)
            self.assertEqual(entry['components'], components, char)


if __name__ == '__main__':
    unittest.main()
