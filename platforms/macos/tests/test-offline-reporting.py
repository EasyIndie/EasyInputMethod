"""Failed offline checks must expose actionable evidence without losing a failing exit."""
import contextlib
import importlib.util
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("offline_runner", Path(__file__).with_name("run-offline-tests.py"))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

class OfflineReportingTests(unittest.TestCase):
    def test_failure_remains_failure_and_is_visible(self):
        with tempfile.TemporaryDirectory() as directory:
            calls = 0
            def run(command, **options):
                nonlocal calls
                calls += 1
                options["stdout"].write("AssertionError: receiver did not become ready\n" if calls == 1 else "Ran 1 test\nOK\n")
                return subprocess.CompletedProcess(command, 1 if calls == 1 else 0)
            output = io.StringIO()
            with patch.object(runner.subprocess, "run", side_effect=run), patch.object(runner.tempfile, "mkdtemp", return_value=directory), contextlib.redirect_stdout(output):
                self.assertEqual(runner.main(), 1)
            self.assertIn("AssertionError: receiver did not become ready", output.getvalue())
            self.assertIn('"passed": false', (Path(directory) / "summary.json").read_text())

    def test_large_diagnostic_preserves_traceback_and_private_full_log(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "failure.log"
            text = "test_prefix_signal_restore\n" + "fixture output\n" * 4000 + "AssertionError: classification mismatch\n"
            log.write_text(text)
            excerpt = runner.failure_excerpt(log)
            self.assertLess(len(excerpt), 16100)
            self.assertIn("test_prefix_signal_restore", excerpt)
            self.assertIn("AssertionError: classification mismatch", excerpt)
            self.assertEqual(log.read_text(), text)

if __name__ == "__main__":
    unittest.main()
