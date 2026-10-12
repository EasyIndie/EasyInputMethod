#!/usr/bin/env python3
"""Reject identity drift before permitting Terminal fixture actions."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('ownership', Path(__file__).with_name('run-terminal-ownership.py'))
ownership = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ownership)


class IdentityTests(unittest.TestCase):
    def test_identity_drift(self):
        runtime = Path('/private/python')
        receiver = Path('/private/receiver')
        command = ' '.join([str(runtime), str(ownership.BASE / 'terminal-input-sink.py'), str(receiver)])
        self.assertTrue(ownership.process_matches('ttys123', command, '/dev/ttys123', runtime, receiver))
        for tty, altered in [('ttys124', command), ('ttys123', command + ' extra'), ('ttys123', command.replace('/private/receiver', '/private/other')), ('ttys123', command.replace('/private/python', '/private/unknown'))]:
            self.assertFalse(ownership.process_matches(tty, altered, '/dev/ttys123', runtime, receiver))


if __name__ == '__main__':
    unittest.main()
