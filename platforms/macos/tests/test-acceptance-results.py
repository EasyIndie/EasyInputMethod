"""Regression tests for false-green reports and blocked live entries."""
import copy
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("results", HERE / "acceptance-results.py")
results = importlib.util.module_from_spec(spec)
spec.loader.exec_module(results)


class AcceptanceResultsTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / "evidence.txt").write_text("synthetic gate fixture, not native evidence")
        self.report = results.template()
        self.report["candidate"] = {
            "sha256": "a" * 64, "commit": "b" * 40,
            "architectures": ["arm64", "x86_64"], "signature": "developer-id-notarized",
        }
        self.report["environment"] = {
            "system": "synthetic", "applications": {name: "fixture" for name in results.APPLICATIONS},
        }
        for case in self.report["cases"]:
            case.update(status="PASS", evidence=["evidence.txt"])

    def check(self, report):
        return results.validate(report, self.root)[0]

    def test_old_schema_and_two_person_id_do_not_pass_current_scope(self):
        self.assertEqual(self.report["schema"], 2)
        self.assertIn("one-person-five-days", results.REQUIRED)
        old = copy.deepcopy(self.report)
        old["schema"] = 1
        self.assertEqual(self.check(old), 2)
        old = copy.deepcopy(self.report)
        for case in old["cases"]:
            if case["id"] == "one-person-five-days":
                case["id"] = "two-person-five-days"
        self.assertEqual(self.check(old), 2)

    def test_complete_fixture_passes(self):
        self.assertEqual(self.check(self.report), 0)

    def test_each_required_case_cannot_be_skipped_or_missing(self):
        for index, case in enumerate(self.report["cases"]):
            with self.subTest(case=case["id"]):
                skipped = copy.deepcopy(self.report)
                skipped["cases"][index].update(status="SKIP", reason="not executed")
                self.assertEqual(self.check(skipped), 2)
                missing = copy.deepcopy(self.report)
                missing["cases"].pop(index)
                self.assertEqual(self.check(missing), 2)

    def test_fail_and_blocked_are_distinct(self):
        self.report["cases"][0].update(status="BLOCKED", reason="no owned input context")
        self.assertEqual(self.check(self.report), 3)
        self.report["cases"][1].update(status="FAIL", reason="restore failed")
        self.assertEqual(self.check(self.report), 1)

    def test_duplicate_or_unknown_case_rejected(self):
        self.report["cases"].append(copy.deepcopy(self.report["cases"][0]))
        self.assertEqual(self.check(self.report), 2)
        self.report["cases"][-1]["id"] = "optional-substitute"
        self.assertEqual(self.check(self.report), 2)

    def test_pass_requires_existing_evidence(self):
        for evidence in ([], ["missing"], [None]):
            self.report["cases"][0]["evidence"] = evidence
            self.assertEqual(self.check(self.report), 2)

    def test_candidate_and_app_identity_required(self):
        for field in self.report["candidate"]:
            report = copy.deepcopy(self.report)
            report["candidate"].pop(field)
            self.assertEqual(self.check(report), 2)
        for name in results.APPLICATIONS:
            report = copy.deepcopy(self.report)
            report["environment"]["applications"][name] = ""
            self.assertEqual(self.check(report), 2)

    def test_malformed_types_do_not_crash_or_pass(self):
        for report in (None, [], {}, {"schema": 2, "candidate": []}, {"schema": 2, "cases": {}}):
            self.assertEqual(self.check(report), 2)
        self.report["cases"][0]["id"] = []
        self.assertEqual(self.check(self.report), 2)

    def test_live_entries_block_before_external_commands(self):
        calls = self.root / "calls"
        for name in ("dirname", "mktemp", "osascript", "swiftc", "cp", "rm", "pbcopy"):
            command = self.root / name
            command.write_text('#!/bin/bash\nprintf "%s\\n" "$0" >> "$GATE_CALLS"\nexit 99\n')
            command.chmod(0o700)
        env = dict(os.environ, PATH=str(self.root), GATE_CALLS=str(calls))
        for entry in ("run-imk-acceptance.sh", "run-input-apps.sh"):
            for args in ([], ["--force"], ["--isolated"]):
                with self.subTest(entry=entry, args=args):
                    completed = subprocess.run(["/bin/bash", str(HERE / entry), *args], env=env,
                                               capture_output=True, text=True, timeout=5, check=False)
                    self.assertEqual(completed.returncode, 3)
                    self.assertIn("BLOCKED", completed.stderr)
                    self.assertFalse(calls.exists())

    def test_template_does_not_overwrite_existing_report(self):
        report = self.root / "report.json"
        report.write_bytes(b"existing evidence")
        completed = subprocess.run(["python3", str(HERE / "acceptance-results.py"), "template", str(report)],
                                   capture_output=True, text=True, check=False)
        self.assertEqual(completed.returncode, 2)
        self.assertEqual(report.read_bytes(), b"existing evidence")


if __name__ == "__main__":
    unittest.main()
