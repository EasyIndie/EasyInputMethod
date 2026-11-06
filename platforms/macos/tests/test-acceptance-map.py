"""Guard against the IT-22 coverage map rotting (report 230)."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]

MAPS = [
    ROOT / 'docs/tasks/T-ITER-22-coverage.md',
    ROOT / 'docs/tasks/T-ITER-22-1.1.0-affected.md',
]

# make 目标与脚本/测试文件都必须真实存在，否则说明文档在骗人。
MAKE_TARGETS = [
    'verify', 'test', 'macos-offline-tests', 'macos-acceptance-full', 'macos-auto-acceptance',
    'macos-ui-contrast', 'macos-multi-display', 'macos-soak',
]

REQUIRED = [
    'Makefile',
    'tools/macos-probe/quality-samples.sh',
    'tools/macos-probe/client-matrix.sh',
    'tools/macos-probe/acceptance-auto.sh',
    'tools/macos-probe/perf-session.sh',
    'tools/macos-probe/cleanup-windows.sh',
    'tools/macos-probe/axclose.swift',
    'tools/check-level1-codes.py',
    'platforms/macos/tests/test-settings-presentation.py',
    'platforms/macos/tests/test-candidate-presentation.py',
    'platforms/macos/tests/test-wubi-learning.py',
    'platforms/macos/tests/test-tools-presentation.py',
    'platforms/macos/tests/test-caret-placement.py',
    'docs/tasks/T-ITER-22.md',
]


class AcceptanceMapTests(unittest.TestCase):
    def test_maps_exist_and_reference_live_paths(self):
        text = ''
        for path in MAPS:
            self.assertTrue(path.is_file(), f'缺少映射文件 {path}')
            text += path.read_text(encoding='utf-8')
        for name in REQUIRED:
            self.assertTrue((ROOT / name).exists(), f'映射引用了不存在的路径 {name}')
        for target in MAKE_TARGETS:
            self.assertIn(f'\n{target}:', (ROOT / 'Makefile').read_text(encoding='utf-8'), f'Makefile 缺少目标 {target}')
        self.assertRegex(text, r'人工必做', '映射必须保留人工必做清单')
        self.assertRegex(text, r'A 档', '映射必须区分每次换包与每版一次')

    def test_probe_suites_do_not_duplicate_cases(self):
        """报告230：两份探针脚本按行为分工——质量样本断言"打字产物"，热键探针断言"状态语义"。"""
        quality_text = (ROOT / 'tools/macos-probe/quality-samples.sh').read_text(encoding='utf-8')
        auto_text = (ROOT / 'tools/macos-probe/acceptance-auto.sh').read_text(encoding='utf-8')

        # 已删掉的重复项不允许回流（它们分别由对方的状态往返用例覆盖）。
        for name in ['全角数字往返', '简繁往返', '单 Shift 切英文直通']:
            self.assertNotIn(f'"{name}"', quality_text, f'{name} 与 acceptance-auto 的状态往返重复，不应回到质量样本')
        self.assertNotIn('"混输+标点"', auto_text, '混输+标点与质量样本的兜底/标点用例重复')

        quality_total = len(re.findall(r'^run\s+"', quality_text, re.M)) + len(re.findall(r'^case_[a-z_]+\(\) \{', quality_text, re.M))
        auto_total = len(re.findall(r'^assert_text\s+"', auto_text, re.M))
        coverage = (ROOT / 'docs/tasks/T-ITER-22-coverage.md').read_text(encoding='utf-8')
        self.assertIn(f'（{quality_total} 项）', coverage, f'覆盖映射里的质量样本计数应为 {quality_total}')
        self.assertIn(f'（{auto_total} 项）', coverage, f'覆盖映射里的热键项计数应为 {auto_total}')

    def test_item_ids_are_unique_and_covered(self):
        coverage = (ROOT / 'docs/tasks/T-ITER-22-coverage.md').read_text(encoding='utf-8')
        ids = re.findall(r'^\| ?([0-9]+\.[0-9]+)', coverage, re.M)
        self.assertTrue(ids, '自动覆盖映射里应当出现条目编号')
        # 人工清单里的编号同样要唯一，避免"某项被写了两遍"。
        manual = coverage[coverage.index('## 2. 人工必做'):]
        manual_ids = re.findall(r'\b([0-9]+\.[0-9]+)\b', manual)
        repeated = [item for item in set(manual_ids) if manual_ids.count(item) > 1]
        self.assertEqual(repeated, [], f'人工清单重复条目 {repeated}')


if __name__ == '__main__':
    unittest.main()
