#!/usr/bin/env python3
"""LWS-86 标准契约（ADR-381）。

守三件事：
1. 我们的数据包**自己通过** L4 一致性判定（含 SHA256SUMS 完整）；
2. 检查器**抓得到反例**（改一位码 / 改一个键位 → 必须 FAIL），否则判定形同虚设；
3. 规范文档齐全且被索引（spec / conformance / CHANGELOG），数据包不含私有区字形。
"""
from pathlib import Path
import hashlib
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
REFERENCE_IMPL = ROOT / 'tools/lws86-reference-impl.py'
PACKAGE_TOOL = ROOT / 'tools/wubi86-std-package.py'


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

    def test_bundle_is_reproducible(self):
        """同一提交两次生成必须逐字节一致（S-1：第三方要能核对 SHA-256）。"""
        again = self.tmp / 'bundle-again'
        built = run(str(BUNDLE_TOOL), '--out', str(again))
        self.assertEqual(built.returncode, 0, built.stderr)
        first = (self.bundle / 'SHA256SUMS').read_text(encoding='utf-8')
        second = (again / 'SHA256SUMS').read_text(encoding='utf-8')
        self.assertEqual(first, second, '数据包不可复现：两次生成的摘要不同')
        self.assertEqual((self.bundle / 'meta.json').read_text(encoding='utf-8'),
                         (again / 'meta.json').read_text(encoding='utf-8'), 'meta.json 含非确定性字段')

    def test_chengzi_exceptions_are_declared(self):
        """R9e：推不出来的成字字根必须标 exception，不许硬塞成 radical-char（ADR-388）。"""
        classes = {}
        for line in (self.bundle / 'chars.tsv').read_text(encoding='utf-8').splitlines():
            if not line or line.startswith('#'):
                continue
            fields = line.split('\t')
            if len(fields) >= 9:
                classes[fields[0]] = (fields[8], fields[1])
        for char in ('母', '方', '车', '止'):
            self.assertEqual(classes[char][0], 'radical-char-exception', f'{char} 应标 exception')
        self.assertEqual(classes['方'][1], 'yygn')
        self.assertEqual(classes['车'][1], 'lgnh')
        self.assertEqual(classes['止'][1], 'hhhg')
        self.assertEqual(classes['母'][1], 'xgui')

    def test_independent_implementation_reproduces_the_codes(self):
        """S-3：另一个只读规范、不引用判定器的实现，能被判定器判为通过（L4）。"""
        impl = self.tmp / 'reference-impl'
        built = run(str(REFERENCE_IMPL), '--bundle', str(self.bundle), '--out', str(impl))
        self.assertEqual(built.returncode, 0, built.stderr)
        stats = json.loads((impl / 'impl.json').read_text(encoding='utf-8'))
        self.assertGreater(stats['derived'], 4000, '独立实现派生的字数过少')
        result = run(str(CHECK_TOOL), '--bundle', str(self.bundle), '--impl', str(impl),
                     '--level', 'L4', '--no-verify-sha', '--report', str(self.tmp / 'impl.json.report'))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = json.loads((self.tmp / 'impl.json.report').read_text(encoding='utf-8'))
        self.assertTrue(report['passed'], report['failures'][:5])
        self.assertEqual(report['failureCount'], 0)
        self.assertGreater(report['compared'], 3700, '独立实现应覆盖绝大多数一级字')
        # 未覆盖的只能来自两条**已列明**的缺口：规范特例与缺笔顺数据。
        self.assertLessEqual(report['missing']['partial'], 12,
                             f'独立实现缺口过大：{report["missing"]}')

    def test_standard_bundle_zip_is_reproducible(self):
        """S-1：发布资产（zip）也必须可复现，否则 .sha256 没有意义。"""
        first, second = self.tmp / 'zip1', self.tmp / 'zip2'
        for out in (first, second):
            packaged = run(str(PACKAGE_TOOL), '--bundle', str(self.bundle), '--out', str(out))
            self.assertEqual(packaged.returncode, 0, packaged.stderr)
        archives = sorted(p.name for p in first.glob('*.zip'))
        self.assertEqual(archives, ['LWS-86-1.0.zip'])
        digests = {p.name: p.read_bytes() for p in first.glob('*.zip')}
        again = {p.name: p.read_bytes() for p in second.glob('*.zip')}
        self.assertEqual(digests, again, '标准数据包 zip 不可复现')
        sidecar = (first / 'LWS-86-1.0.zip.sha256').read_text(encoding='utf-8').split()[0]
        self.assertEqual(sidecar, hashlib.sha256(digests['LWS-86-1.0.zip']).hexdigest(),
                         '.sha256 与 zip 不符')

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
