#!/usr/bin/env python3
"""Run native-probe failure handling against fake executables, no UI calls."""
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('owned_probe', Path(__file__).with_name('run-owned-probe.py'))
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ProbeTests(unittest.TestCase):
    def run_fake(self, content, timeout=2):
        with tempfile.TemporaryDirectory() as folder:
            mock = Path(folder) / 'osascript'
            mock.write_text('#!/bin/bash\n' + content)
            mock.chmod(0o700)
            resources = Path(folder) / 'resources'
            resources.mkdir(mode=0o700)
            with patch.dict(os.environ, {'PATH': folder + ':' + os.environ['PATH']}), \
                    patch.object(MODULE.tempfile, 'mkdtemp', return_value=str(resources)):
                status = MODULE.probe('normal', timeout=timeout)
            if status == 0:
                self.assertFalse(resources.exists())
            else:
                fixture = resources / 'resources.txt'
                self.assertEqual(fixture.read_bytes(), b'')
                self.assertEqual(fixture.stat().st_mode & 0o777, 0o600)
            return status

    def test_no_output_is_not_pass(self):
        self.assertEqual(self.run_fake('exit 0\n'), 3)

    def test_failure_is_not_pass_even_with_pass_output(self):
        self.assertEqual(self.run_fake(f'echo "{MODULE.SUCCESS}"\nexit 1\n'), 3)

    def test_timeout_is_bounded(self):
        self.assertEqual(self.run_fake('exec sleep 3\n', timeout=0.1), 3)

    def test_success_requires_exact_evidence(self):
        self.assertEqual(self.run_fake(f'echo "{MODULE.SUCCESS}"\n'), 0)


if __name__ == '__main__':
    unittest.main()
