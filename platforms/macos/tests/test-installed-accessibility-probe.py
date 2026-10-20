#!/usr/bin/env python3
"""Accessibility probe contract: needs VoiceOver, judges announcements and client focus."""
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

    def test_watcher_only_observes(self):
        watcher = (Path(__file__).with_name('isolated-imk') / 'ax-announcement-watch.swift').read_text(encoding='utf-8')
        self.assertIn('AXObserverCreateWithInfoCallback', watcher)
        self.assertIn('kAXAnnouncementRequestedNotification', watcher)
        self.assertNotIn('AXUIElementPost', watcher)
        self.assertNotIn('CGEvent', watcher)

    def test_client_focus_must_survive_the_toggle(self):
        self.assertIn('BLOCKED 状态切换后客户端焦点被夺走', probe.BODY)
        self.assertIn('keystroke \\"m\\" using {option down}', probe.BODY)

    def test_announcements_are_required_for_a_pass(self):
        source = HERE.read_text(encoding='utf-8')
        self.assertIn("announcements = [event", source)
        self.assertIn('bool(announced)', source)


if __name__ == '__main__':
    unittest.main()
