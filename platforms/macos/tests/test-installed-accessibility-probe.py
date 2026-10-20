#!/usr/bin/env python3
"""Accessibility probe contract: requires VoiceOver, checks the AX surface and client focus."""
import importlib.util
from pathlib import Path
import unittest

HERE = Path(__file__).with_name('run-installed-accessibility-probe.py')
SPEC = importlib.util.spec_from_file_location('probe', HERE)
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


class Contract(unittest.TestCase):
    def test_blocks_when_voiceover_is_not_running(self):
        source = HERE.read_text(encoding='utf-8')
        self.assertIn('VoiceOver 未运行', source)
        self.assertIn('voiceover_running()', source)

    def test_surface_tokens_are_required(self):
        source = HERE.read_text(encoding='utf-8')
        for token in ('输入编码', '输入模式', '上一页', '下一页'):
            self.assertIn(token, source)
        self.assertIn('axMissing', source)

    def test_client_focus_must_survive_the_toggle(self):
        self.assertIn('BLOCKED 状态切换后客户端焦点被夺走', probe.BODY)
        self.assertIn('keystroke \\"m\\" using {option down}', probe.BODY)

    def test_probe_only_reads_the_host_window_tree(self):
        self.assertIn('process "LampyrisIMKTest"', probe.BODY)
        self.assertNotIn('click at', probe.BODY)


if __name__ == '__main__':
    unittest.main()
