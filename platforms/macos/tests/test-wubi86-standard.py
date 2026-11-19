#!/usr/bin/env python3
"""LWS-86 标准契约（ADR-381）。

守三件事：
1. 我们的数据包**自己通过** L4 一致性判定（含 SHA256SUMS 完整）；
2. 检查器**抓得到反例**（改一位码 / 改一个键位 → 必须 FAIL），否则判定形同虚设；
3. 规范文档齐全且被索引（spec / conformance / CHANGELOG），数据包不含私有区字形。
"""
from pathlib import Path
import json
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SPEC_DIR = ROOT / 'docs/standards/wubi86'
BUNDLE_TOOL = ROOT / 'tools/wubi86-std-bundle.py'
CHECK_TOOL = ROOT / 'tools/wubi86-std-check.py'


def run(*args, cwd=None):
    return subprocess.run([sys.executable, *args], capture_output=True, text=True, cwd=cwd)


class Wubi86StandardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = Path(tempfile.mkdtemp(prefix='lws86-'))
        cls.bundle = cls.tmp / 'bundle'
        built = run(str(BUNDLE_TOOL), '--out', str(cls.bundle))
        assert built.returncode == 0, built.stderr

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def test_documents_exist_and_are_linked(self):
        for name in ('spec-1.0.md', 'conformance-1.0.md', 'CHANGELOG.md'):
            self.assertTrue((SPEC_DIR / name).is_file(), f'缺 {name}')
        index = (ROOT / 'docs/standards/README.md').read_text(encoding='utf-8')
        self.assertIn('wubi86/spec-1.0.md', index, '规范未在 docs/standards/README.md 索引')
        top = (ROOT / 'docs/README.md').read_text(encoding='utf-8')
        self.assertIn('standards/README.md', top, '标准目录未在 docs/README.md 索引')

    def test_bundle_self_check_passes_l4(self):
        result = run(str(CHECK_TOOL), '--bundle', str(self.bundle), '--level', 'L4',
                     '--report', str(self.tmp / 'self.json'))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = json.loads((self.tmp / 'self.json').read_text(encoding='utf-8'))
        self.assertTrue(report['passed'])
        self.assertGreater(report['compared'], 3000, '自检覆盖字数过少')
        meta = json.loads((self.bundle / 'meta.json').read_text(encoding='utf-8'))
        self.assertEqual(meta['standard'], 'LWS-86')
        self.assertEqual(meta['scope']['inScope'], 3755)

    def test_bundle_has_no_private_use_glyphs(self):
        for name in ('chars.tsv', 'roots.tsv'):
            text = (self.bundle / name).read_text(encoding='utf-8')
            bad = [hex(ord(ch)) for ch in text if 0xE000 <= ord(ch) <= 0xF8FF or ord(ch) >= 0xF0000]
            self.assertEqual(bad, [], f'{name} 含私有区字形：{bad[:5]}')

    def test_checker_detects_code_and_key_mutations(self):
        # 变异 1：把某字的全码改掉；变异 2：把第一个字根换成「一」（键 g，键位必然不符）
        cases = {'code': 'code', 'root-key': 'key'}
        for name, kind in cases.items():
            impl = self.tmp / f'impl-{name}'
            shutil.copytree(self.bundle, impl)
            chars = impl / 'chars.tsv'
            lines = chars.read_text(encoding='utf-8').splitlines()
            index = next(i for i, line in enumerate(lines)
                         if line and not line.startswith('#')
                         and line.split('\t')[-1] == 'compound'
                         and line.split('\t')[1][:1] != 'g'
                         and line.split('\t')[3].strip())
            fields = lines[index].split('\t')
            if kind == 'code':
                fields[1] = 'zzzz'
            else:
                fields[3] = '一 ' + ' '.join(fields[3].split()[1:])
            lines[index] = '\t'.join(fields)
            chars.write_text('\n'.join(lines) + '\n', encoding='utf-8')
            (impl / 'SHA256SUMS').unlink()  # 变异后不再校验 SHA
            result = run(str(CHECK_TOOL), '--bundle', str(self.bundle), '--impl', str(impl),
                         '--level', 'L1', '--no-verify-sha')
            self.assertEqual(result.returncode, 1, f'{name} 变异未被抓到：{result.stdout}')
            self.assertIn('✗', result.stdout)


def _replace(line: str, column: int, value: str) -> str:
    fields = line.split('\t')
    fields[column] = value
    return '\t'.join(fields)


if __name__ == '__main__':
    unittest.main()
