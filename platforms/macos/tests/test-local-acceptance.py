"""Synthetic fixtures test rejection paths, never count as native acceptance."""
import copy
import importlib.util
import json
import os
import sys
import subprocess
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('local_acceptance', HERE / 'run-local-acceptance.py')
local = importlib.util.module_from_spec(spec)
spec.loader.exec_module(local)


class LocalAcceptanceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        source = {'head_commit': 'a' * 40, 'product_revision': 'a' * 40,
                  'product_sha256': 'b' * 64, 'cargo_lock_sha256': 'c' * 64,
                  'toolchain_sha256': 'd' * 64, 'modified_product_files': []}
        self.report = {'schema': 1, 'scope': 'native-offscreen-components',
                       'mvp_result': 'BLOCKED', 'formal_cases': local.formal_gaps(),
                       'source_before': source, 'source_after': copy.deepcopy(source),
                       'harness_before': {'synthetic': 'e' * 64}, 'harness_after': {'synthetic': 'e' * 64},
                       'local_result': 'PASS', 'suites': []}
        (self.root / 'harness').mkdir()
        (self.root / 'harness/synthetic').write_text('synthetic source fixture')
        digest = local.sha(self.root / 'harness/synthetic')
        self.report['harness_before'] = {'synthetic': digest}
        self.report['harness_after'] = {'synthetic': digest}
        for name, (script, required) in local.SUITES.items():
            work = self.root / name
            work.mkdir()
            cases = [{'id': case, 'status': 'PASS', 'scope': 'native-offscreen-components',
                      'expected': 'synthetic validator fixture only', 'actual': {'fixture': True},
                      'observed_at': '2026-10-16T00:00:00Z'} for case in required]
            (work / 'observations.json').write_text(json.dumps({'schema': 1, 'cases': cases}))
            (work / 'probe.json').write_text(json.dumps({'sha256': 'f' * 64, 'bytes': 1, 'cargo_lock_sha256': 'c' * 64}))
            (work / 'run.log').write_text('synthetic fixture, not actual native proof')
            for artifact in local.REQUIRED_ARTIFACTS[name]:
                (work / artifact).write_text('synthetic fixture, not a screenshot')
            self.report['suites'].append({'id': name, 'script': script, 'command': ['/fixture/python', '/fixture/' + script],
                                         'exit': 0, 'status': 'PASS', 'cases': cases})
        self.report['case_count'] = sum(len(j['cases']) for j in self.report['suites'])
        self.save()

    def save(self, remanifest=True):
        if remanifest:
            self.report['artifacts'] = local.manifest(self.root)
        (self.root / 'report.json').write_text(json.dumps(self.report))

    def rejected(self):
        with self.assertRaises((ValueError, KeyError)):
            local.check(self.root)

    def test_valid_format_still_blocks_entire_mvp(self):
        self.assertEqual(local.check(self.root), 64)
        self.assertTrue(all(c['status'] == 'BLOCKED' for c in self.report['formal_cases']))

    def test_mvp_cannot_be_promoted_or_required_case_omitted(self):
        self.report['mvp_result'] = 'PASS'
        self.save()
        self.rejected()
        self.report['mvp_result'] = 'BLOCKED'
        self.report['formal_cases'].pop()
        self.save()
        self.rejected()

    def test_missing_duplicate_and_unknown_observations_rejected(self):
        path = self.root / 'menu/observations.json'
        original = json.loads(path.read_text())
        for mutation in ['missing', 'duplicate', 'unknown']:
            observed = copy.deepcopy(original)
            if mutation == 'missing':
                observed['cases'].pop()
            elif mutation == 'duplicate':
                observed['cases'].append(observed['cases'][0])
            else:
                observed['cases'][0]['id'] = 'invented'
            path.write_text(json.dumps(observed))
            self.save()
            self.rejected()
        path.write_text(json.dumps(original))

    def test_changed_or_deleted_evidence_rejected(self):
        path = self.root / 'tools/about-light.png'
        path.write_text('changed')
        self.rejected()
        path.unlink()
        self.rejected()
        self.save()
        self.rejected()  # Rewriting the manifest must not hide missing mandatory artifacts.

    def test_source_change_and_missing_probe_rejected(self):
        self.report['source_after']['product_sha256'] = '0' * 64
        self.save()
        self.rejected()
        self.report['source_after'] = copy.deepcopy(self.report['source_before'])
        (self.root / 'menu/probe.json').unlink()
        self.save()
        self.rejected()

    def test_failed_suite_or_summary_rewrite_rejected(self):
        self.report['suites'][0]['exit'] = 1
        self.save()
        self.rejected()
        self.report['suites'][0]['exit'] = 0
        self.report['suites'][0]['cases'][0]['actual'] = 'invented'
        self.save()
        self.rejected()

    def test_evidence_cannot_escape_report_root(self):
        self.report['artifacts'][0]['path'] = '../outside'
        self.save(remanifest=False)
        self.rejected()

    def test_timeout_cleans_owned_process_group(self):
        if sys.platform == 'win32':
            self.skipTest('requires POSIX process groups')
        with (self.root / 'timeout.log').open('w') as stream:
            with self.assertRaises(subprocess.TimeoutExpired):
                local.execute([sys.executable, '-c', 'import os,time; print(os.getpid(), flush=True); time.sleep(30)'],
                              os.environ.copy(), stream, timeout=0.2)
        pid = int((self.root / 'timeout.log').read_text().strip())
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)

    def test_harness_snapshot_cannot_be_dropped(self):
        (self.root / 'harness/synthetic').unlink()
        self.save()
        self.rejected()

    def test_local_probe_must_bind_dependency_lock(self):
        path = self.root / 'menu/probe.json'
        data = json.loads(path.read_text())
        data['cargo_lock_sha256'] = '0' * 64
        path.write_text(json.dumps(data))
        self.save()
        self.rejected()


if __name__ == '__main__':
    unittest.main()
