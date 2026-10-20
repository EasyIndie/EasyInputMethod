"""UI permission failures must stop before any test resource or source action."""
import importlib.util
from pathlib import Path
import subprocess
import os
import re
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('probe', Path(__file__).with_name('run-installed-textedit-probe.py'))
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


class PermissionPreflight(unittest.TestCase):
    def test_false_and_unexpected_output_block_before_resources(self):
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


class ClientLifecycle(unittest.TestCase):
    def exercise(self, fail, scenario="normal"):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            helper = root / 'helper'
            helper.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
r=pathlib.Path(sys.argv[2]); action=sys.argv[1]
with (r/'events').open('a') as f: f.write(action+'\\n')
if action=='select-owned' and os.environ['FAIL']=='selection': sys.exit(3)
if action=='select-owned': (r/'state').write_text('selected')
if action=='restore-original': (r/'state').write_text('original')
print(json.dumps({'current':(r/'state').read_text()}))
''')
            helper.chmod(0o700)
            library = root / 'library.sh'
            library.write_text('''owned_textedit_create() {
 [ "$(cat "$WORK/state")" = selected ] || return 1
 echo create >> "$WORK/events"
}
owned_cleanup() {
 [ "$(cat "$WORK/state")" = original ] || return 1
 echo close >> "$WORK/events"
}
owned_do() {
 if [ "$1" = marked-range ]; then
  if [ "$FAIL" = marked ]; then printf "missing value"; return 0; fi
  if [ -f "$WORK/committed" ]; then printf '2, 1'; else printf '1, 2'; fi
  return 0
 fi
 if [ "$1" = read ]; then
  if [ -f "$WORK/committed" ]; then printf '你'; elif [ -f "$WORK/prefix" ]; then printf wq; fi
  return 0
 fi
 echo "$2" >> "$WORK/events"
 [ "$FAIL" != focus ] || exit 1
 [ "$2" != 12 ] || touch "$WORK/prefix"
 [ "$2" != 49 ] || touch "$WORK/committed"
}
''')
            (root / 'state').write_text('original')
            (root / 'osascript').write_text('''#!/bin/sh
case "$*" in
 *AXFocusedUIElement*)
  if [ "$FAIL" = refocus ]; then printf AXWindow; else printf AXTextArea; fi ;;
esac
exit 0
''')
            (root / 'osascript').chmod(0o700)
            environment = dict(os.environ, FAIL=fail, PATH=str(root) + ':' + os.environ['PATH'])
            body = re.sub(r'(?m)^([ \t]*)sleep 0\.[0-9]+$', r'\1sleep 0', probe.scenario_body(scenario))
            result = subprocess.run(['bash', '-c', body, 'mock', str(library), str(root), str(helper), str(root)], env=environment, capture_output=True, timeout=10)
            self.assertEqual((root / 'state').read_text(), 'original')
            return result.returncode, (root / 'events').read_text().splitlines()

    def test_select_precedes_client_creation_and_restores_before_close(self):
        status, events = self.exercise('none')
        self.assertEqual(status, 0)
        self.assertLess(events.index('select-owned'), events.index('create'))
        self.assertEqual([event for event in events if event.isdigit()], ['13', '12', '49'])
        self.assertEqual(events[-2:], ['restore-original', 'close'])

    def test_focus_failure_stops_remaining_keys_and_restores(self):
        status, events = self.exercise('focus')
        self.assertEqual(status, 1)
        self.assertNotIn('12', events)
        self.assertNotIn('49', events)
        self.assertEqual(events[-2:], ['restore-original', 'close'])

    def test_prefix_interruptions_restore_without_commit_key(self):
        for scenario, expected in [('failure', 7), ('INT', 130), ('TERM', 143)]:
            with self.subTest(scenario=scenario):
                status, events = self.exercise('none', scenario)
                self.assertEqual(status, expected)
                self.assertIn('12', events)
                self.assertNotIn('49', events)
                self.assertEqual(events[-2:], ['restore-original', 'close'])

    def test_unreadable_marked_range_prevents_commit(self):
        status, events = self.exercise('marked')
        self.assertEqual(status, 95)
        self.assertIn('12', events)
        self.assertNotIn('49', events)
        self.assertEqual(events[-2:], ['restore-original', 'close'])

    def test_selection_failure_does_not_create_client(self):
        status, events = self.exercise('selection')
        self.assertEqual(status, 98)
        self.assertNotIn('create', events)
        self.assertFalse(any(event.isdigit() for event in events))

    def test_refocus_failure_prevents_all_keys_and_restores(self):
        status, events = self.exercise('refocus')
        self.assertEqual(status, 98)
        self.assertFalse(any(event.isdigit() for event in events))
        self.assertEqual(events[-2:], ['restore-original', 'close'])


if __name__ == '__main__':
    unittest.main()
