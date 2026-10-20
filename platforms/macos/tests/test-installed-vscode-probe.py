#!/usr/bin/env python3
"""VS Code probe contract: preflight, owned file, and never type into a foreign window."""
import importlib.util
from pathlib import Path
import subprocess
from types import SimpleNamespace
import unittest
from unittest.mock import patch

HERE = Path(__file__).with_name('run-installed-vscode-probe.py')
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


class OwnedFileContract(unittest.TestCase):
    def test_probe_creates_and_saves_its_own_file(self):
        self.assertIn('vscode-fixture-$$.txt', probe.BODY)
        self.assertIn('keystroke "s" using command down', probe.BODY)
        self.assertIn('fixtureName=$(basename', probe.BODY)

    def test_window_must_match_the_fixture_before_typing(self):
        self.assertIn('BLOCKED VS Code 窗口未就绪或不是本 fixture', probe.BODY)
        self.assertIn('does not contain wanted', probe.BODY)

    def test_close_only_matches_our_window(self):
        self.assertIn('BLOCKED 没有本 fixture 的窗口', probe.BODY)

    def test_composition_must_not_touch_the_file(self):
        self.assertIn('[ "$(cat "$fixture")" = "seed" ]', probe.BODY)

    def test_scenarios_keep_their_expected_exit_codes(self):
        for scenario, action in (('failure', 'exit 7'), ('INT', 'kill -INT $$'), ('TERM', 'kill -TERM $$')):
            self.assertIn(action, probe.body_for(scenario))
        self.assertEqual(probe.body_for('normal'), probe.BODY)


if __name__ == '__main__':
    unittest.main()
