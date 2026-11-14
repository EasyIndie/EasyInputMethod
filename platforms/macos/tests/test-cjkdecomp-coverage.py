"""D24 cjk-decomp 覆盖拆字契约（ADR-357 / 报告 283）。"""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
COVERAGE = ROOT / 'data/learning/wubi86-cjkdecomp-coverage.tsv'
CORPUS = ROOT / 'modules/hanzi-structure/corpus/B0.json'
CODES = ROOT / 'data/generated/wubi86-single.tsv'


def rows(path):
    return [line.split('\t') for line in path.read_text(encoding='utf-8').splitlines()
            if line and not line.startswith('#')]


def load_keys():
    keys = {}
    for path in (ROOT / 'data/learning/wubi86-readable-keys.tsv',):
        for line in path.read_text(encoding='utf-8').splitlines():
            if not line or line.startswith('#'):
                continue
            key, glyphs = line.split('\t')
            keys.update({g: key for g in glyphs})
    for line in (ROOT / 'modules/keymap/data/key-roots-wubi86.tsv').read_text(encoding='utf-8').splitlines():
        if not line or line.startswith('#'):
            continue
        fields = line.split('\t')
        for root in fields[5].split():
            keys.setdefault(root, fields[1].lower())
    for line in (ROOT / 'data/learning/wubi86-traditional-root-keys.tsv').read_text(encoding='utf-8').splitlines():
        if not line or line.startswith('#'):
            continue
        fields = line.split('\t')
        keys.setdefault(fields[0], fields[1].lower())
    return keys


class CjkDecompCoverageTests(unittest.TestCase):
    def test_rows_are_validated(self):
        data = rows(COVERAGE)
        self.assertGreaterEqual(len(data), 50)
        keys = load_keys()
        codes = {}
        for line in CODES.read_text(encoding='utf-8').splitlines():
            fields = line.split('\t')
            if len(fields) >= 2 and len(fields[1]) == 1 and len(fields[0]) > len(codes.get(fields[1], '')):
                codes[fields[1]] = fields[0]
        seen = set()
        for char, text, code, key_text, source, evidence in data:
            self.assertEqual(len(char), 1, char)
            self.assertNotIn(char, seen, f'重复字 {char}')
            seen.add(char)
            self.assertEqual(codes.get(char), code, f'{char}: 全码不符')
            self.assertEqual(source, 'D24')
            self.assertTrue(evidence)
            components = text.split()
            self.assertIn(len(components), (len(code), len(code) - 1), f'{char}: 组件数')
            self.assertEqual(key_text, code[:len(components)], f'{char}: keys')
            for component, key in zip(components, code):
                self.assertFalse(0xE000 <= ord(component[0]) <= 0xF8FF or ord(component[0]) >= 0xF0000,
                                 f'{char}: 组件含 PUA')
                self.assertEqual(keys.get(component), key, f'{char}: {component} 键位不符')

    def test_b0_uses_d24_and_is_full(self):
        entries = {e['char']: e for e in json.loads(CORPUS.read_text(encoding='utf-8'))}
        expected = {row[0]: row[1].split() for row in rows(COVERAGE)}
        for char, components in expected.items():
            entry = entries.get(char)
            if entry is None:
                continue  # 1,000 字语料只覆盖高频子集
            self.assertEqual(entry['componentsSource'], 'D24', char)
            self.assertEqual(entry['components'], components, char)
            self.assertEqual(entry['quality'], 'full', char)


if __name__ == '__main__':
    unittest.main()
