#!/usr/bin/env python3
"""Feature probe contract: preflight, owned document, and no typing without the guard."""
import importlib.util
from pathlib import Path
import subprocess
from types import SimpleNamespace
import unittest
from unittest.mock import patch

HERE = Path(__file__).with_name('run-installed-ime-features-probe.py')
SPEC = importlib.util.spec_from_file_location('probe', HERE)
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


class PermissionPreflight(unittest.TestCase):
    def test_unusable_ui_scripting_blocks_before_resources(self):
        for response in ['false\n', '', 'true false', 'TRUE']:
            with self.subTest(response=response), patch.object(probe, 'run', return_value=SimpleNamespace(stdout=response)), patch.object(probe.tempfile, 'mkdtemp') as create, patch('sys.argv', ['probe', '/invalid-root', '/invalid-helper', '/invalid-hud', '--scenario', 'long']):
                self.assertEqual(probe.main(), 3)
                create.assert_not_called()

    def test_timeout_blocks_before_resources(self):
        with patch.object(probe, 'run', side_effect=subprocess.TimeoutExpired('osascript', 15)), patch.object(probe.tempfile, 'mkdtemp') as create, patch('sys.argv', ['probe', '/invalid-root', '/invalid-helper', '/invalid-hud', '--scenario', 'long']):
            self.assertEqual(probe.main(), 3)
            create.assert_not_called()


class ScenarioContract(unittest.TestCase):
    def test_only_known_scenarios_exist(self):
        self.assertEqual(sorted(probe.BODIES), ['long', 'mode', 'undo'])

    def test_commit_scenarios_go_through_the_owned_document_guard(self):
        for name in ('long', 'undo'):
            with self.subTest(scenario=name):
                self.assertIn('owned_do key 49', probe.BODIES[name])
                self.assertIn('owned_do read', probe.BODIES[name])

    def test_every_scenario_stops_on_the_guard(self):
        for name, body in probe.BODIES.items():
            with self.subTest(scenario=name):
                self.assertIn('exit 98', body)

    def test_mode_cycle_reads_the_host_config_and_returns(self):
        body = probe.BODIES['mode']
        self.assertIn('config.toml', body)
        self.assertIn('BLOCKED 模式未回到起点', body)
        self.assertIn('keystroke \\"m\\" using {option down}', probe.PRELUDE)

    def test_long_composition_must_recover_after_escape(self):
        body = probe.BODIES['long']
        self.assertIn('zhongguorenmingonghe', body)
        self.assertIn('BLOCKED Esc 后未回到已提交文本', body)

    def test_undo_must_revert_the_committed_text(self):
        body = probe.BODIES['undo']
        self.assertIn('owned_do undo', body)
        self.assertIn('BLOCKED ⌘Z 未回退', body)


if __name__ == '__main__':
    unittest.main()
