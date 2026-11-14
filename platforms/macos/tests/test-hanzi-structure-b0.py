"""B0 结构事实库必须可复现且通过独立校验（报告 240）。"""
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
MODULE = ROOT / 'modules/hanzi-structure'


INPUTS = {
    'codes': ROOT / 'data/generated/wubi86-single.tsv',
    'radicals': ROOT / 'data/sources/wubi-lex-86.txt',
    'short1': ROOT / 'data/sources/wubi86-level1-codes.tsv',
    'short2': ROOT / 'data/sources/wubi86-level2-codes.tsv',
    'pinyin': ROOT / 'data/generated/pinyin-chars.tsv',
}


class B0CorpusTests(unittest.TestCase):
    def test_corpus_validates_against_inputs(self):
        """独立重算需要下载型输入（D2/D17）；CI 不下载它们时跳过，改由内部一致性用例把关。"""
        missing = [name for name, path in INPUTS.items() if not path.is_file()]
        if missing:
            self.skipTest('缺少下载型输入，跳过独立重算：' + ', '.join(missing))
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
        # U3-4/N1-d 后「是」已 full；用一个仍有占位字根的字验证降级契约。
        partial = subprocess.run(query + ['被'], cwd=ROOT, capture_output=True, text=True, timeout=60)
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
        result = subprocess.run(query + ['万'], cwd=ROOT, capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('？(n)', result.stdout)
        self.assertIn('参考识别码 v', result.stdout)

    def test_component_counts_align_with_codes(self):
        """v4：合体字的组件数必须与码长自洽（n 或 n-1），且成字字根带笔画（报告 244）。"""
        import json
        entries = json.loads((MODULE / 'corpus/B0.json').read_text(encoding='utf-8'))
        unaligned = []
        for entry in entries:
            if entry['class'] != 'compound' or not entry['code']:
                continue
            if len(entry['components']) in (len(entry['code']), len(entry['code']) - 1):
                continue
            # D2 自身漏拆的极少数条目：允许存在，但必须 partial 且写明原因
            self.assertEqual(entry['quality'], 'partial', f"{entry['char']}: 对不上却非 partial")
            self.assertTrue(any('对不上' in n for n in entry['notes']), f"{entry['char']}: 缺原因说明")
            unaligned.append(entry['char'])
        self.assertLessEqual(len(unaligned), len(entries) // 100,
                             f'组件数对不上的条目过多：{len(unaligned)}')
        radical_chars = [e for e in entries if e['class'] == 'radical-char']
        self.assertTrue(radical_chars)
        for entry in radical_chars:
            if entry['code'][:2] == entry['code'][0] * 2 and entry['code'][2:] == 'll':
                continue  # 单笔画：XXLL，没有笔画序列
            self.assertTrue(entry['strokes'], f"{entry['char']}: 成字字根缺笔画序列")
            self.assertEqual(entry['quality'], 'full', f"{entry['char']}: 有笔画却非 full")
        query = [sys.executable, str(MODULE / 'tools/b0_query.py')]
        strokes = subprocess.run(query + ['用'], cwd=ROOT, capture_output=True, text=True, timeout=60)
        self.assertIn('成字字根', strokes.stdout)
        self.assertIn('丿', strokes.stdout)

    def test_corpus_internal_consistency(self):
        """不依赖下载型输入：字段、等级、识别码、键位、结构、无 PUA 的机器不变量。"""
        import json
        entries = json.loads((MODULE / 'corpus/B0.json').read_text(encoding='utf-8'))
        report = json.loads((MODULE / 'corpus/B0-report.json').read_text(encoding='utf-8'))
        self.assertEqual(report['entries'], len(entries))
        self.assertEqual(report['schemaVersion'], 6)
        recognition = {
            'g': ('横', '左右'), 'f': ('横', '上下'), 'd': ('横', '杂合'),
            'h': ('竖', '左右'), 'j': ('竖', '上下'), 'k': ('竖', '杂合'),
            't': ('撇', '左右'), 'r': ('撇', '上下'), 'e': ('撇', '杂合'),
            'y': ('捺', '左右'), 'u': ('捺', '上下'), 'i': ('捺', '杂合'),
            'n': ('折', '左右'), 'b': ('折', '上下'), 'v': ('折', '杂合'),
        }
        for entry in entries:
            char = entry['char']
            if entry['class'] == 'compound':
                self.assertEqual(len(entry['keys']), len(entry['components']), f'{char}: keys 长度')
            for glyph in entry['components']:
                if glyph is None:
                    continue
                self.assertFalse(any(0xE000 <= ord(c) <= 0xF8FF or ord(c) >= 0xF0000 for c in glyph),
                                 f'{char}: 组件含私有区字形')
            if entry['quality'] != 'full':
                self.assertTrue(entry['notes'], f'{char}: 非 full 必须有 notes')
            record = entry['recognition']
            if record:
                self.assertEqual(record['key'], entry['code'][-1], f'{char}: 识别码不是末位')
                self.assertEqual((record['stroke'], record['structure']), recognition[record['key']])
                self.assertEqual(len(entry['components']), len(entry['code']) - 1)
            self.assertIsInstance(entry.get('positionMismatch'), list)

    def test_no_unlicensed_source_in_corpus(self):
        """ADR-310：D3（未声明许可）只能作 oracle，产物里不得出现其组件来源。"""
        import json
        entries = json.loads((MODULE / 'corpus/B0.json').read_text(encoding='utf-8'))
        sources = {e.get('componentsSource') for e in entries}
        self.assertNotIn('D3', sources)
        self.assertTrue(sources <= {None, 'D1', 'D2', 'D18', 'D24'}, sources)

    def test_ids_structure_is_consistent(self):
        """v5：ids 必须是 IDS 序列，idsStructure 必须与根算子一致（报告 245）。"""
        import json
        entries = json.loads((MODULE / 'corpus/B0.json').read_text(encoding='utf-8'))
        ops = set('⿰⿱⿲⿳⿴⿵⿶⿷⿸⿹⿺⿻')
        self.assertTrue(any(e['ids'] for e in entries))
        for entry in entries:
            seq, structure = entry['ids'], entry['idsStructure']
            if seq is None:
                self.assertIsNone(structure, f"{entry['char']}: 无 ids 却给了结构")
                continue
            self.assertIn(seq[0], ops, f"{entry['char']}: ids 不是 IDS 序列")
            expected = ('左右' if seq[0] in '⿰⿲' else '上下' if seq[0] in '⿱⿳' else '杂合')
            self.assertEqual(structure, expected, f"{entry['char']}: 结构与根算子不一致")

    def test_ids_filled_placeholders_match_keys(self):
        """v5：IDS 补进来的字根必须与码位键一致，占位不得因此被"凑"出来。"""
        import json
        entries = json.loads((MODULE / 'corpus/B0.json').read_text(encoding='utf-8'))
        keys = {}
        for line in (ROOT / 'data/learning/wubi86-readable-keys.tsv').read_text(encoding='utf-8').splitlines():
            if not line or line.startswith('#'):
                continue
            key, glyphs = line.split('\t')
            for glyph in glyphs:
                keys.setdefault(glyph, key)
        filled = [e for e in entries if any('按 IDS' in n for n in e['notes'])]
        self.assertTrue(filled, 'IDS 应至少补齐一条占位')
        for entry in filled:
            skip = set(entry.get('positionMismatch') or [])
            for index, (glyph, key) in enumerate(zip(entry['components'], entry['keys']), start=1):
                if index in skip:
                    continue
                self.assertIsNotNone(glyph, f"{entry['char']}: 填过占位却残留 null")
                if glyph in keys:
                    self.assertEqual(keys[glyph], key, f"{entry['char']}: {glyph} 的键位与码位不符")

    def test_n2_writing_strokes_for_radical_chars(self):
        """N2：B0 成字字根必须来自 D18 真实笔顺，不能是取码笔顺。"""
        import json
        entries = json.loads((MODULE / 'corpus/B0.json').read_text(encoding='utf-8'))
        radical_chars = [e for e in entries if e['class'] == 'radical-char']
        self.assertTrue(radical_chars)
        for entry in radical_chars:
            self.assertEqual(entry.get('strokesKind'), 'writing', entry['char'])
            self.assertEqual(entry.get('strokesSource'), 'D18', entry['char'])
            self.assertTrue(entry.get('strokes'), entry['char'])
            self.assertTrue(all(s in '一丨丿丶乙' for s in entry['strokes']), entry['char'])

    def test_n3_structure_sources_are_consistent(self):
        """N3：识别码结构优先；没有识别码时用 IDS，并记录口径冲突。"""
        import json
        entries = json.loads((MODULE / 'corpus/B0.json').read_text(encoding='utf-8'))
        with_structure = [e for e in entries if e.get('structure')]
        self.assertGreaterEqual(len(with_structure), 950)
        for entry in with_structure:
            self.assertIn(entry['structure'], ('左右', '上下', '杂合'))
            self.assertIn(entry['structureSource'], ('recognition', 'IDS'))
            if entry['structureSource'] == 'recognition':
                self.assertEqual(entry['structure'], entry['recognition']['structure'])
            else:
                self.assertEqual(entry['structure'], entry.get('idsStructure'))
            if entry.get('structureConflict'):
                self.assertTrue(entry.get('recognition') and entry.get('idsStructure'))
                self.assertNotEqual(entry['recognition']['structure'], entry['idsStructure'])

    def test_n4_d2_gaps_have_manual_decomposition(self):
        """N4：8 个 D2 漏拆字必须由 D18 补成完整拆字。"""
        import json
        entries = {e['char']: e for e in json.loads((MODULE / 'corpus/B0.json').read_text(encoding='utf-8'))}
        expected = {
            '没': ['氵', '几', '又'], '城': ['土', '厂', '𠃌'], '余': ['人', '禾'],
            '代': ['亻', '弋'], '件': ['亻', '牛', '丨'], '凭': ['亻', '丿', '士', '几'],
            '俄': ['亻', '丿', '扌'], '浠': ['氵', '乂', '𠂇', '丨'],
        }
        for char, components in expected.items():
            entry = entries[char]
            self.assertEqual(entry['components'], components, char)
            self.assertEqual(entry['componentsSource'], 'D18', char)
            self.assertEqual(entry['quality'], 'full', char)

    def test_provenance_records_hashes(self):
        text = (MODULE / 'provenance/B0.md').read_text(encoding='utf-8')
        for marker in ('D2', 'D17-bis', 'SHA-256', 'CC-BY-SA-4.0'):
            self.assertIn(marker, text)
        report = (MODULE / 'corpus/B0-report.json').read_text(encoding='utf-8')
        self.assertIn('sha256', report)


if __name__ == '__main__':
    unittest.main()
