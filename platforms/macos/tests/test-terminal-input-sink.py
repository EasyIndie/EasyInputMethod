#!/usr/bin/env python3
"""Exercise the byte receiver using a private PTY, without native UI."""
import importlib.util
import json
import os
from pathlib import Path
import pty
import signal
import subprocess
import sys
import tempfile
import termios
import time
import unittest


spec = importlib.util.spec_from_file_location('sink', Path(__file__).with_name('terminal-input-sink.py'))
sink = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sink)


class SinkTests(unittest.TestCase):
    def exercise(self, payload, interruption=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            master, slave = pty.openpty()
            before = termios.tcgetattr(slave)
            process = subprocess.Popen([sys.executable, str(Path(__file__).with_name('terminal-input-sink.py')), directory], stdin=slave, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            try:
                deadline = time.monotonic() + 3
                while not (root / 'ready.json').exists():
                    if process.poll() is not None or time.monotonic() > deadline:
                        self.fail('receiver did not become ready')
                    time.sleep(0.02)
                os.write(master, payload)
                time.sleep(0.15)
                if interruption:
                    process.send_signal(interruption)
                else:
                    (root / 'stop').touch()
                _, error = process.communicate(timeout=3)
                self.assertEqual(process.returncode, 0, error)
                result = json.loads((root / 'result.json').read_text())
                self.assertTrue(result['ttyRestored'])
                self.assertTrue(sink.tty_equivalent(termios.tcgetattr(slave), before))
                self.assertEqual((root / 'result.json').stat().st_mode & 0o777, 0o600)
                return result
            finally:
                try:
                    if process.poll() is None:
                        process.kill()
                        process.communicate(timeout=3)
                finally:
                    if process.stderr is not None:
                        process.stderr.close()
                    os.close(master)
                    os.close(slave)

    def test_committed_bytes(self):
        self.assertEqual(self.exercise('你'.encode())['classification'], 'committed')

    def test_prefix_signal_restore(self):
        for interruption in [signal.SIGINT, signal.SIGTERM]:
            result = self.exercise(b'wq', interruption)
            self.assertEqual(result['classification'], 'prefix')
            self.assertEqual(result['outcome'], 'interrupted')

    def test_unknown_command_is_only_classified(self):
        result = self.exercise(b'echo unsafe\n')
        self.assertEqual(result['classification'], 'unexpected')
        self.assertNotIn('unsafe', json.dumps(result))

    def test_buffer_limit(self):
        self.assertEqual(self.exercise(b'x' * 64)['outcome'], 'limit')


if __name__ == '__main__':
    unittest.main()
