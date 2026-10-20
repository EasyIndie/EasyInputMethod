#!/usr/bin/env python3
"""VS Code probe contract: preflight, owned file, and never type into a foreign window."""
import importlib.util
from pathlib import Path
import subprocess
import json
import os
import tempfile
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
    def test_changed_source_prevents_native_actions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'selected.json').write_text(json.dumps({'current': 'owned'}))
            helper = root / 'helper'
            helper.write_text('#!/bin/sh\nprintf \'{"current":"%s"}\\n\' "$TEST_SOURCE"\n')
            helper.chmod(0o700)
            native = root / 'osascript'
            native.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$TEST_CALLS"\n')
            native.chmod(0o700)
            library = root / 'library.sh'
            library.write_text('')
            body = probe.BODY.split('cleanup() {', 1)[0] + '\nfixtureName=owned.txt\nguarded_action w || exit 98\n'
            for source, expected in [('owned', 0), ('foreign', 98)]:
                with self.subTest(source=source):
                    calls = root / (source + '.calls')
                    result = subprocess.run(['bash', '-c', body, 'test', str(library), str(root), str(helper), str(root)],
                        env={**os.environ, 'PATH': str(root) + ':' + os.environ['PATH'],
                             'TEST_SOURCE': source, 'TEST_CALLS': str(calls)}, capture_output=True, timeout=5)
                    self.assertEqual(result.returncode, expected, result.stderr)
                    self.assertEqual(calls.exists(), source == 'owned')

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
