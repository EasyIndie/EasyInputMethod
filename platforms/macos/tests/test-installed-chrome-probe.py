#!/usr/bin/env python3
"""Chrome probe contract: UI preflight, offline fixture and the tab-title channel only."""
import importlib.util
from pathlib import Path
import subprocess
from types import SimpleNamespace
import unittest
from unittest.mock import patch

HERE = Path(__file__).with_name('run-installed-chrome-probe.py')
SPEC = importlib.util.spec_from_file_location('probe', HERE)
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


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


class ChannelContract(unittest.TestCase):
    def test_fixture_is_offline_and_declares_the_title_channel(self):
        fixture = Path(__file__).with_name('chrome-fixture.py').read_text(encoding='utf-8')
        self.assertIn("default-src 'none'", fixture)
        self.assertIn('document.title', fixture)
        self.assertIn('fixture-input', fixture)

    def test_probe_refuses_to_type_without_the_fixture_channel(self):
        # 前台不是本 fixture 的页面就 BLOCK，不在别人的标签页里打字。
        self.assertIn('BLOCKED 前台页面不是本 fixture', probe.BODY)
        self.assertIn('BLOCKED Chrome非前台', probe.BODY)

    def test_composition_must_not_reach_the_page_before_commit(self):
        self.assertIn('BLOCKED 组合期出现提交', probe.BODY)

    def test_only_the_owned_tab_is_closed(self):
        self.assertIn('starts with prefix', probe.BODY)
        self.assertIn('return "closed:"', probe.BODY)

    def test_scenarios_keep_their_expected_exit_codes(self):
        self.assertEqual(sorted(probe.SCENARIOS), ['INT', 'TERM', 'failure', 'normal'])
        self.assertIsNone(probe.SCENARIOS['normal'])
        self.assertEqual(probe.SCENARIOS['failure'], 'exit 7')


if __name__ == '__main__':
    unittest.main()
