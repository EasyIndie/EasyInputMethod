"""Mock source registration and verify cleanup never touches prior resources."""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("probe", Path(__file__).with_name("run-isolated-source-probe.py"))
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


class SourceProbeTests(unittest.TestCase):
    def setUp(self):
        self.root = probe.isolated.create()
        self.addCleanup(lambda: shutil.rmtree(self.root) if self.root.exists() else None)
        (self.root / "LampyrisIMKTest.app").mkdir()
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.home = Path(self.directory.name)
        (self.home / "Library").mkdir()
        self.calls = []
        self.before = {"current": "original-id", "enabled": ["original-id"], "owned": []}
        self.register_error = None
        self.cleanup_changed = False
        self.recognition_error = False
        self.alias = self.home / "Library/Input Methods" / ("LampyrisIMKTest-" + self.root.name.removeprefix("lampyris-imk-") + ".app")

    def run_tool(self, args, **_kwargs):
        self.calls.append(args)
        if args[0] == probe.LSREGISTER and args[1] == "-f" and self.recognition_error:
            return subprocess.CompletedProcess(args, 1, "", "recognition denied")
        if args[0] == "swiftc" or args[0] == probe.LSREGISTER:
            return subprocess.CompletedProcess(args, 0, "", "")
        action = args[1]
        if action == "register" and self.register_error is not None:
            raise self.register_error
        result = dict(self.before)
        if action == "register":
            result["owned"] = [{"id": "owned-id", "enabled": False}]
        if action == "disable-owned" and self.cleanup_changed:
            result["current"] = "user-changed-id"
        return subprocess.CompletedProcess(args, 0, json.dumps(result), "")

    def run_case(self):
        with patch.object(sys, "argv", ["probe", str(self.root)]), patch.object(Path, "home", return_value=self.home), \
                patch.object(probe.subprocess, "run", side_effect=self.run_tool):
            return probe.main()

    def test_normal_only_owned_alias_removed(self):
        self.assertEqual(self.run_case(), 0)
        self.assertFalse(self.root.exists())
        self.assertFalse(self.alias.exists())
        self.assertFalse((self.home / "Library/Input Methods").exists())
        self.assertFalse(any("select" in args for args in self.calls))

    def test_register_failure_retains_evidence_but_removes_owned_alias(self):
        self.register_error = RuntimeError("injected registration failure")
        self.assertEqual(self.run_case(), 3)
        self.assertTrue((self.root / "source-state.json").is_file())
        self.assertFalse(self.alias.is_symlink())
        self.assertEqual((self.root / "source-state.json").stat().st_mode & 0o777, 0o600)

    def test_interrupt_runs_owned_cleanup(self):
        self.register_error = KeyboardInterrupt("injected interrupt")
        self.assertEqual(self.run_case(), 3)
        self.assertTrue(self.root.exists())
        self.assertFalse(self.alias.is_symlink())
        self.assertTrue(any(args[1] == "disable-owned" for args in self.calls if len(args) > 1))

    def test_changed_state_not_overwritten_or_marked_pass(self):
        self.cleanup_changed = True
        self.assertEqual(self.run_case(), 3)
        self.assertTrue(self.root.exists())
        self.assertTrue(self.alias.is_symlink())
        self.assertFalse(any(args[0] == probe.LSREGISTER and args[1] == "-u" for args in self.calls))

    def test_recognition_failure_records_diagnostic_and_never_registers(self):
        self.recognition_error = True
        self.assertEqual(self.run_case(), 3)
        record = self.root / "launchservices-recognition.json"
        self.assertEqual(json.loads(record.read_text())["stderr"], "recognition denied")
        self.assertEqual(record.stat().st_mode & 0o777, 0o600)
        self.assertFalse(any(len(args) > 1 and args[1] == "register" for args in self.calls))
        self.assertFalse(self.alias.is_symlink())

    def test_existing_alias_never_overwritten_or_removed(self):
        self.alias.parent.mkdir()
        self.alias.write_bytes(b"preexisting")
        self.assertEqual(self.run_case(), 3)
        self.assertEqual(self.alias.read_bytes(), b"preexisting")
        self.assertFalse(any(args[0] == probe.LSREGISTER for args in self.calls))


if __name__ == "__main__":
    unittest.main()
