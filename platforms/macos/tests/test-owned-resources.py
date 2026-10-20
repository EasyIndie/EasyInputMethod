#!/usr/bin/env python3
"""Exercise cleanup ownership without accessing native applications."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

LIB = Path(__file__).with_name('owned-resources.sh')


class OwnershipTests(unittest.TestCase):
    def run_case(self, ending):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            mock = root / 'osascript'
            mock.write_text('#!/bin/bash\nprintf "%s\\n" "$*" >> "$CALL_LOG"\nexit 1\n')
            mock.chmod(0o700)
            env = dict(os.environ, PATH=f'{root}:{os.environ["PATH"]}', CALL_LOG=str(root / 'calls'))
            body = '''source "$1"
trap owned_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
OWNED_FILE=/tmp/owned-fixture.txt
OWNED_NAME=owned-fixture.txt
owned_record TextEdit window 101 || exit 9
owned_record 'Google Chrome' window 202 || exit 9
owned_record Safari window 303 || exit 9
owned_record Terminal window 404 || exit 9
if owned_record TextEdit window '1; bad'; then exit 9; fi
if owned_record Unknown window 5; then exit 9; fi
'''
            result = subprocess.run(['bash', '-c', body + ending, 'test', str(LIB)], env=env, capture_output=True)
            calls = (root / 'calls').read_text().splitlines()
            self.assertEqual(len(calls), 4)
            self.assertIn('Terminal" to close window id 404', calls[0])
            self.assertIn('owned-textedit.applescript close /tmp/owned-fixture.txt owned-fixture.txt 101', calls[3])
            self.assertFalse(any('front' in call or 'every' in call for call in calls))
            return result.returncode

    def test_success(self):
        self.assertEqual(self.run_case('exit 0\n'), 0)

    def test_failure(self):
        self.assertEqual(self.run_case('exit 7\n'), 7)

    def test_interrupt(self):
        self.assertEqual(self.run_case('kill -INT $$\n'), 130)

    def test_termination(self):
        self.assertEqual(self.run_case('kill -TERM $$\n'), 143)


class FocusTests(unittest.TestCase):
    def run_action(self, body, fail_at=0):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            mock = root / 'osascript'
            mock.write_text("""#!/usr/bin/env python3
import os
from pathlib import Path
import sys
p = Path(os.environ['CALL_LOG'])
previous = p.read_text() if p.exists() else ''
n = previous.count('CALL\\n') + 1
p.write_text(previous + 'CALL\\n' + ' '.join(sys.argv[1:]) + '\\n')
sys.exit(1 if n == int(os.environ['FAIL_AT']) else 0)
""")
            mock.chmod(0o700)
            env = dict(os.environ, PATH=f'{root}:{os.environ["PATH"]}',
                       CALL_LOG=str(root / 'calls'), FAIL_AT=str(fail_at))
            result = subprocess.run(['bash', '-c', 'source "$1"\n' + body, 'test', str(LIB)],
                                    env=env, capture_output=True)
            log = (root / 'calls').read_text() if (root / 'calls').exists() else ''
            return result, log

    def test_guard_before_each_character_and_stop(self):
        result, log = self.run_action('OWNED_FILE=/tmp/owned-fixture.txt\nOWNED_NAME=owned-fixture.txt\nowned_record TextEdit window 101\nowned_type wqz\n', 2)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(log.count('CALL\n'), 2)
        self.assertNotIn('keystroke "z"', log)
        self.assertLess(log.index('if not frontmost'), log.index('keystroke "w"'))
        self.assertIn('id of front window', log)
        self.assertIn('AXFocusedUIElement', log)

    def test_unowned_or_invalid_actions_never_reach_native_api(self):
        for body in ['owned_type w', 'OWNED_FILE=/tmp/owned-fixture.txt\nOWNED_NAME=owned-fixture.txt\nowned_record TextEdit window 101\nowned_do char 7']:
            result, log = self.run_action(body)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(log, '')

    def test_clear_addresses_owned_document(self):
        result, log = self.run_action('OWNED_FILE=/tmp/owned-fixture.txt\nOWNED_NAME=owned-fixture.txt\nowned_record TextEdit window 101\nowned_do clear\n')
        self.assertEqual(result.returncode, 0)
        self.assertIn('owned-textedit.applescript clear /tmp/owned-fixture.txt owned-fixture.txt 101', log)
        self.assertNotIn('set text of front document', log)

    def test_changed_source_stops_before_native_action(self):
        body = '''OWNED_FILE=/tmp/owned-fixture.txt
OWNED_NAME=owned-fixture.txt
owned_record TextEdit window 101
root=/tmp/lampyris-imk-test-identity
helper=source_mock
source_mock() { printf '%s' '{"current":"com.apple.keylayout.ABC"}'; }
owned_do key 49
'''
        result, log = self.run_action(body)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(log, '')

    def test_performance_shortcuts_share_atomic_window_guard(self):
        for name, key in [('settings', ','), ('about', 'a'), ('variant', 't')]:
            with self.subTest(name=name):
                result, log = self.run_action('OWNED_FILE=/tmp/owned-fixture.txt\nOWNED_NAME=owned-fixture.txt\nowned_record TextEdit window 101\nowned_do option ' + name + '\n')
                self.assertEqual(result.returncode, 0)
                self.assertLess(log.index('if not frontmost'), log.index('keystroke "' + key + '"'))
                self.assertIn('documentFile is not fixtureFile', log)
                self.assertIn('AXFocusedUIElement', log)


if __name__ == '__main__':
    unittest.main()
