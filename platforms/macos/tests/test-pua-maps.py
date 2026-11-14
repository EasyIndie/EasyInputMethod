"""N1-d 扩展映射：D2 BMP PUA 与逐字语境表（ADR-353/355）。"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
CORPUS = ROOT / 'modules/hanzi-structure/corpus'
D2_BMP = CORPUS / 'pua-d2-bmp.tsv'
CONTEXT = CORPUS / 'pua-context.tsv'


def rows(path):
    return [line.split('\t') for line in path.read_text(encoding='utf-8').splitlines()
            if line and not line.startswith('#')]


def pua(value):
    return chr(int(value.strip().upper().removeprefix('U+'), 16))


def is_pua(value):
    return 0xE000 <= ord(value[0]) <= 0xF8FF or ord(value[0]) >= 0xF0000


class PuaMapTests(unittest.TestCase):
    def test_d2_bmp_rows(self):
        data = rows(D2_BMP)
        self.assertEqual(len(data), 3)
        seen = set()
        for value, key, label, status, evidence in data:
            cp = pua(value)
            self.assertTrue(0xE000 <= ord(cp) <= 0xF8FF, value)
            self.assertRegex(key, r'^[a-y]$')
            self.assertTrue(label and not is_pua(label))
            self.assertEqual(status, 'verified')
            self.assertTrue(evidence)
            self.assertNotIn((cp, key), seen, f'重复 (PUA, 键位) {value}/{key}')
            seen.add((cp, key))

    def test_context_rows(self):
        data = rows(CONTEXT)
        self.assertGreaterEqual(len(data), 30)
        seen = set()
        for char, value, key, label, evidence in data:
            self.assertEqual(len(char), 1, char)
            cp = pua(value)
            self.assertTrue(0xE000 <= ord(cp) <= 0xF8FF or ord(cp) >= 0xF0000, value)
            self.assertRegex(key, r'^[a-y]$')
            self.assertTrue(label and not is_pua(label))
            self.assertTrue(evidence)
            self.assertNotIn((char, cp, key), seen, f'重复语境 {char}/{value}/{key}')
            seen.add((char, cp, key))

    def test_context_covers_the_ambiguous_roots(self):
        data = rows(CONTEXT)
        covered = {(char, key) for char, _pua, key, _label, _evidence in data}
        # 这些是 N1-d 的语境歧义：氏/卯、才、乚/匕、儿。
        for item in (('低', 'q'), ('留', 'q'), ('才', 'f'), ('我', 'n'), ('拽', 'x'), ('逃', 'q')):
            self.assertIn(item, covered, f'缺语境条 {item}')


if __name__ == '__main__':
    unittest.main()
