#!/usr/bin/env python3
"""Guard the ADR-293 evidence index and the CI lane classifier."""
import importlib.util
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
SCRIPT = ROOT / 'scripts/acceptance-evidence.py'


def load():
    spec = importlib.util.spec_from_file_location('acceptance_evidence', SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class EvidenceIndex(unittest.TestCase):
    """ADR-293：证据绑定产物执行 SHA，索引要能按 SHA 找到报告与覆盖项。"""

    def test_index_reads_reports_and_items(self):
        module = load()
        sha = 'a' * 64
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            reviews = root / 'docs/reviews'
            reviews.mkdir(parents=True)
            (reviews / '300-demo.md').write_text(
                f'# 300 演示报告\n\n| 执行 SHA | {sha} |\n\n质量样本 16/16；VoiceOver 播报已确认。\n',
                encoding='utf-8')
            data = module.index(root)
            self.assertIn(sha, data)
            row = data[sha][0]
            self.assertEqual(row['report'], 'docs/reviews/300-demo.md')
            self.assertIn('quality', row['items'])
            self.assertIn('voiceover', row['items'])

    def test_short_sha_in_report_matches_full_query(self):
        """早期报告只写了前 8 位（`a165f05c…`），按完整 SHA 查询也要命中。"""
        module = load()
        full = 'a165f05c' + 'b' * 56
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            reviews = root / 'docs/reviews'
            reviews.mkdir(parents=True)
            (reviews / '301-short.md').write_text('# 301 短 SHA\n\n执行 SHA `a165f05c…`，睡眠唤醒 PASS。\n',
                                                  encoding='utf-8')
            result = subprocess.run(['python3', str(SCRIPT), 'for', full, '--root', str(root), '--json'],
                                    capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('docs/reviews/301-short.md', result.stdout)
            self.assertIn('sleep', result.stdout)

    def test_unknown_sha_exits_nonzero(self):
        module = load()  # noqa: F841 - 只确认模块可加载
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / 'docs/reviews').mkdir(parents=True)
            result = subprocess.run(['python3', str(SCRIPT), 'for', 'f' * 64, '--root', str(root)],
                                    capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 1)
            self.assertIn('没有找到', result.stdout)

    def test_template_report_is_skipped(self):
        module = load()
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            reviews = root / 'docs/reviews'
            reviews.mkdir(parents=True)
            (reviews / 'TEMPLATE-report.md').write_text('# 模板\n\n' + 'c' * 64 + '\n', encoding='utf-8')
            self.assertEqual(module.index(root), {})


class CiLanes(unittest.TestCase):
    """ADR-293：CI 三条泳道，产品码 full、工具 tooling、文档 docs。"""

    def detect(self, files):
        script = ROOT / 'scripts/ci-detect-code-changes.sh'
        with tempfile.TemporaryDirectory() as directory:
            repo = pathlib.Path(directory)
            run = ['git', 'init', '-q', str(repo)]
            subprocess.run(run, check=True)
            subprocess.run(['git', '-C', str(repo), 'config', 'user.email', 't@example.com'], check=True)
            subprocess.run(['git', '-C', str(repo), 'config', 'user.name', 'test'], check=True)
            (repo / 'seed').write_text('x')
            subprocess.run(['git', '-C', str(repo), 'add', '.'], check=True)
            subprocess.run(['git', '-C', str(repo), 'commit', '-qm', 'seed'], check=True)
            base = subprocess.run(['git', '-C', str(repo), 'rev-parse', 'HEAD'],
                                  capture_output=True, text=True, check=True).stdout.strip()
            for name in files:
                target = repo / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text('y')
            subprocess.run(['git', '-C', str(repo), 'add', '.'], check=True)
            subprocess.run(['git', '-C', str(repo), 'commit', '-qm', 'change'], check=True)
            result = subprocess.run(['bash', str(script)], cwd=repo, capture_output=True, text=True,
                                    check=True,
                                    env={'GITHUB_EVENT_NAME': 'pull_request', 'GITHUB_BASE_SHA': base,
                                         'PATH': '/usr/bin:/bin:/usr/sbin:/sbin'})
            return dict(line.split('=', 1) for line in result.stdout.split())

    def test_product_change_is_full(self):
        self.assertEqual(self.detect(['platforms/macos/Sources/CandidateWindow.swift'])['lane'], 'full')
        self.assertEqual(self.detect(['crates/ime-core/src/lib.rs'])['lane'], 'full')

    def test_tooling_change_is_tooling(self):
        self.assertEqual(self.detect(['tools/macos-probe/README.md'])['lane'], 'tooling')
        self.assertEqual(self.detect(['scripts/check-clean.sh'])['lane'], 'tooling')

    def test_docs_change_is_docs(self):
        out = self.detect(['docs/reviews/212-demo.md'])
        self.assertEqual(out['lane'], 'docs')
        self.assertEqual(out['code'], 'false')

    def test_product_wins_over_tooling(self):
        self.assertEqual(self.detect(['tools/x.sh', 'crates/ime-core/src/lib.rs'])['lane'], 'full')

    def test_test_only_paths_are_tooling(self):
        """测试代码不进入产物字节，不该触发 universal 构建（报告212 里这类 PR 白跑 10 分钟）。"""
        self.assertEqual(self.detect(['platforms/macos/tests/test-demo.py'])['lane'], 'tooling')
        self.assertEqual(self.detect(['crates/ime-core/tests/roundtrip.rs'])['lane'], 'tooling')


if __name__ == '__main__':
    unittest.main()
