#!/usr/bin/env python3
"""Exercise configuration recovery with isolated files, never user settings."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

GUARD = Path(__file__).with_name('fixture-guard.py')


class FixtureTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.root = Path(self.folder.name)
        self.fixture = self.root / 'config.toml'
        self.journal = self.root / 'config.json'
        self.original = '# 用户注释\nmode = "mixed"\n'.encode()
        self.fixture.write_bytes(self.original)
        self.fixture.chmod(0o640)

    def tearDown(self):
        self.folder.cleanup()

    def call(self, operation, *args):
        return subprocess.run([sys.executable, str(GUARD), operation, str(self.journal), *map(str, args)],
                              capture_output=True)

    def save(self):
        self.assertEqual(self.call('save', self.fixture).returncode, 0)

    def mutate(self, exit_code=0):
        return self.call('run', sys.executable, '-c',
                         'from pathlib import Path; import sys; Path(sys.argv[1]).write_text("test"); sys.exit(int(sys.argv[2]))',
                         self.fixture, str(exit_code))

    def test_success_restore_preserves_bytes_and_permissions(self):
        self.save()
        self.assertEqual(self.mutate().returncode, 0)
        self.assertEqual(self.call('restore').returncode, 0)
        self.assertEqual(self.fixture.read_bytes(), self.original)
        self.assertEqual(self.fixture.stat().st_mode & 0o777, 0o640)
        self.assertEqual(self.journal.stat().st_mode & 0o777, 0o600)

    def test_external_change_not_overwritten(self):
        self.save()
        self.mutate()
        self.fixture.write_text('new user content')
        self.assertNotEqual(self.call('restore').returncode, 0)
        self.assertEqual(self.fixture.read_text(), 'new user content')
        self.assertEqual(self.journal.with_suffix('.original').read_bytes(), self.original)
        self.assertNotEqual(self.mutate().returncode, 0)
        self.assertEqual(self.fixture.read_text(), 'new user content')

    def test_partial_failed_write_not_claimed(self):
        self.save()
        self.assertEqual(self.mutate(7).returncode, 7)
        self.assertNotEqual(self.call('restore').returncode, 0)
        self.assertEqual(self.fixture.read_text(), 'test')

    def test_missing_or_symlink_rejected(self):
        self.fixture.unlink()
        self.assertNotEqual(self.call('save', self.fixture).returncode, 0)
        self.assertFalse(self.journal.exists())
        other = self.root / 'other'
        other.write_text('existing')
        self.fixture.symlink_to(other)
        self.assertNotEqual(self.call('save', self.fixture).returncode, 0)
        self.assertEqual(other.read_text(), 'existing')

    def test_normal_failure_and_signal_cleanup(self):
        for ending, code in [('exit 0', 0), ('exit 7', 7), ('kill -INT $$', 130), ('kill -TERM $$', 143)]:
            self.journal.unlink(missing_ok=True)
            self.journal.with_suffix('.original').unlink(missing_ok=True)
            self.save()
            self.mutate()
            script = '''trap 'python3 "$1" restore "$2"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
'''
            result = subprocess.run(['bash', '-c', script + ending, 'test', str(GUARD), str(self.journal)])
            self.assertEqual(result.returncode, code)
            self.assertEqual(self.fixture.read_bytes(), self.original)


if __name__ == '__main__':
    unittest.main()
