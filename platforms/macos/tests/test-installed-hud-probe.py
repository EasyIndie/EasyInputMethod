#!/usr/bin/env python3
"""HUD probe contract: geometry decides the panel kind and the guard stays local."""
import importlib.util
from pathlib import Path
import unittest

HERE = Path(__file__).with_name('run-installed-hud-probe.py')
SPEC = importlib.util.spec_from_file_location('probe', HERE)
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)

SCRIPTS = Path(__file__).with_name('isolated-imk')
SWIFT = (SCRIPTS / 'hud-probe.swift').read_text(encoding='utf-8')


def window(number, height, width=400, on_screen=True, layer=101, alpha=1):
    return {'number': number, 'height': height, 'width': width, 'layer': layer,
            'alpha': alpha, 'onScreen': on_screen, 'screen': 0}


class PanelKinds(unittest.TestCase):
    def test_candidate_and_hud_are_told_apart_by_height(self):
        windows = [window(1, 70, 531), window(2, 32)]
        self.assertEqual([w['number'] for w in probe.pick(windows, 'candidate')], [1])
        self.assertEqual([w['number'] for w in probe.pick(windows, 'hud')], [2])

    def test_hidden_and_foreign_windows_are_ignored(self):
        windows = [window(1, 70, 531, on_screen=False), window(2, 32, layer=3), window(3, 32, alpha=0)]
        self.assertEqual(probe.pick(windows, 'candidate'), [])
        self.assertEqual(probe.pick(windows, 'hud'), [])

    def test_named_reports_flag_missing_or_duplicate_panels(self):
        problems = []
        probe.check_screen('hud', [window(1, 32), window(2, 32)], 0, 'hud', problems)
        self.assertTrue(any('数量' in problem for problem in problems))
        problems = []
        probe.check_screen('hud', [window(1, 32)], 1, 'hud', problems)
        self.assertTrue(any('屏' in problem for problem in problems))

    def test_frontmost_check_accepts_both_localisations(self):
        self.assertTrue(probe.client_frontmost({'frontmost': 'TextEdit'}))
        self.assertTrue(probe.client_frontmost({'frontmost': '文本编辑'}))
        self.assertFalse(probe.client_frontmost({'frontmost': 'Safari'}))


class HelperContract(unittest.TestCase):
    def test_helper_only_touches_the_owned_root(self):
        self.assertIn('独有目录身份不符', SWIFT)
        self.assertIn('截图目录不在独有根内', SWIFT)
        self.assertIn('LampyrisIMKTest.', SWIFT)

    def test_control_experiment_is_limited_to_the_production_bundle(self):
        self.assertIn('--host-bundle', SWIFT)
        self.assertIn('对照宿主只允许生产身份', SWIFT)
        self.assertIn('cn.jokerhub.inputmethod.Lampyris"', SWIFT)

    def test_capture_shells_out_because_the_probe_lacks_screen_recording(self):
        self.assertIn('/usr/sbin/screencapture', SWIFT)
        self.assertIn('onScreen', SWIFT)


if __name__ == '__main__':
    unittest.main()
