#!/usr/bin/env python3
"""Safari probe contract: UI preflight stops early and the page load keeps ownership guards."""
import importlib.util
from pathlib import Path
import subprocess
import unittest
from types import SimpleNamespace
from unittest.mock import patch

HERE = Path(__file__).with_name('run-installed-safari-probe.py')
SPEC = importlib.util.spec_from_file_location('probe', HERE)
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)

SCRIPT = (Path(__file__).with_name('owned-safari.applescript')).read_text(encoding='utf-8')


class PermissionPreflight(unittest.TestCase):
    def test_unusable_ui_scripting_blocks_before_resources(self):
        for response in ['false\n', '', 'true false', 'TRUE']:
            with self.subTest(response=response), patch.object(probe, 'run', return_value=SimpleNamespace(stdout=response)), patch.object(probe.tempfile, 'mkdtemp') as create, patch('sys.argv', ['probe', '/invalid-root', '/invalid-helper']):
                self.assertEqual(probe.main(), 3)
                create.assert_not_called()

    def test_timeout_blocks_before_resources(self):
        with patch.object(probe, 'run', side_effect=subprocess.TimeoutExpired('osascript', 15)), patch.object(probe.tempfile, 'mkdtemp') as create, patch('sys.argv', ['probe', '/invalid-root', '/invalid-helper']):
            self.assertEqual(probe.main(), 3)
            create.assert_not_called()

    def test_true_passes_only_preflight(self):
        with patch.object(probe, 'run', return_value=SimpleNamespace(stdout='true\n')):
            probe.require_ui_scripting()


class FixtureContract(unittest.TestCase):
    def test_probe_only_accepts_offline_pages(self):
        self.assertIn('file:///', SCRIPT)
        self.assertIn('BLOCKED 非离线页面', SCRIPT)

    def test_page_is_delivered_through_launch_services(self):
        # Safari 18.6 refuses the sandbox extension for AppleScript-delivered file:// URLs (report 102).
        self.assertIn('/usr/bin/open -a Safari ', SCRIPT)
        self.assertIn('quoted form of fixtureURL', SCRIPT)

    def test_window_must_be_new_and_carry_the_fixture_page(self):
        self.assertIn('if previousIDs contains targetID then error "BLOCKED 未取得独有窗口"', SCRIPT)
        self.assertIn('if landedID is 0 then error "BLOCKED 未取得独有窗口"', SCRIPT)
        self.assertIn('(previousIDs does not contain candidateID)', SCRIPT)
        self.assertIn('if URL of current tab of targetWindow is not fixtureURL then error "BLOCKED 测试页面身份改变"', SCRIPT)
        self.assertIn('if (count of tabs of targetWindow) is not 1 then error "BLOCKED 测试窗口标签集合改变"', SCRIPT)

    def test_extra_tabs_are_only_closed_when_they_are_not_the_fixture(self):
        self.assertIn('if tabURL is not fixtureURL then close tab tabIndex of targetWindow', SCRIPT)

    def test_focus_actions_refuse_a_foreign_window(self):
        self.assertIn('if not frontmost then error "BLOCKED Safari非前台"', SCRIPT)
        self.assertIn('if id of front window is not targetID then error "BLOCKED Safari窗口焦点改变"', SCRIPT)


if __name__ == '__main__':
    unittest.main()
