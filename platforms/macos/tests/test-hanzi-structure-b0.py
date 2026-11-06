"""B0 结构事实库必须可复现且通过独立校验（报告 240）。"""
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
MODULE = ROOT / 'modules/hanzi-structure'


class B0CorpusTests(unittest.TestCase):
    def test_corpus_validates_against_inputs(self):
        cmd = [sys.executable, str(MODULE / 'tests/validate_b0.py'),
               '--corpus', str(MODULE / 'corpus/B0.json'),
               '--report', str(MODULE / 'corpus/B0-report.json'),
               '--codes', str(ROOT / 'data/generated/wubi86-single.tsv'),
               '--radicals', str(ROOT / 'data/sources/wubi-lex-86.txt'),
               '--short1', str(ROOT / 'data/sources/wubi86-level1-codes.tsv'),
               '--short2', str(ROOT / 'data/sources/wubi86-level2-codes.tsv'),
               '--pinyin', str(ROOT / 'data/generated/pinyin-chars.tsv')]
        result = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('B0 校验通过', result.stdout)

    def test_query_degrades_partial_entries(self):
        """消费契约：full 给完整解释，partial 必须带"拆解待核验"。"""
        query = [sys.executable, str(MODULE / 'tools/b0_query.py')]
        full = subprocess.run(query + ['和'], cwd=ROOT, capture_output=True, text=True, timeout=60)
        self.assertEqual(full.returncode, 0, full.stderr)
        self.assertIn('识别码 g', full.stdout)
        partial = subprocess.run(query + ['一'], cwd=ROOT, capture_output=True, text=True, timeout=60)
        self.assertEqual(partial.returncode, 0, partial.stderr)
        self.assertIn('拆解待核验', partial.stdout)

    def test_placeholder_components_stay_partial(self):
        """schema v3：字形未识别的字根用 null 占位，带键位，且不得判 full（报告 243）。"""
        import json
        entries = json.loads((MODULE / 'corpus/B0.json').read_text(encoding='utf-8'))
        with_placeholder = [e for e in entries if any(c is None for c in e['components'])]
        self.assertTrue(with_placeholder, 'v3 至少应有一条占位条目')
        for entry in with_placeholder:
            self.assertNotEqual(entry['quality'], 'full', f"{entry['char']}: 占位条目不得为 full")
            self.assertTrue(entry['notes'], f"{entry['char']}: 占位条目必须写 notes")
            for index, glyph in enumerate(entry['components']):
                if glyph is None:
                    self.assertTrue(entry['keys'] and index < len(entry['keys']),
                                    f"{entry['char']}: 占位缺少键位")
            text = json.dumps(entry, ensure_ascii=False)
            self.assertNotIn('\ue000', ''.join(c for c in text if 0xE000 <= ord(c) <= 0xF8FF))
        query = [sys.executable, str(MODULE / 'tools/b0_query.py')]
        result = subprocess.run(query + ['在'], cwd=ROOT, capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('？(d)', result.stdout)
        self.assertIn('参考识别码 d', result.stdout)

    def test_provenance_records_hashes(self):
        text = (MODULE / 'provenance/B0.md').read_text(encoding='utf-8')
        for marker in ('D2', 'D17-bis', 'SHA-256', 'CC-BY-SA-4.0'):
            self.assertIn(marker, text)
        report = (MODULE / 'corpus/B0-report.json').read_text(encoding='utf-8')
        self.assertIn('sha256', report)


if __name__ == '__main__':
    unittest.main()
