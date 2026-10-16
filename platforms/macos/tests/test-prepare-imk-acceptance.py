#!/usr/bin/env python3
"""Preparation must never execute or promote unfinished IMK acceptance."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('prepare_imk', HERE / 'prepare-imk-acceptance.py')
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)


class PreparationTests(unittest.TestCase):
    def test_preparation_has_no_desktop_or_process_calls(self):
        with tempfile.TemporaryDirectory() as temp, patch('subprocess.Popen', side_effect=AssertionError('process forbidden')), patch('os.system', side_effect=AssertionError('shell forbidden')):
            path = Path(temp) / 'new'
            self.assertEqual(prepare.prepare(path), 12)
            plan = json.loads((path / 'checklist.json').read_text())
            self.assertFalse(plan['executed'])
            self.assertEqual(len({s['id'] for s in plan['scenarios']}), 12)
            for case in plan['scenarios']:
                self.assertEqual(case['status'], 'BLOCKED')
                self.assertEqual(case['actual'], '')
                self.assertEqual(case['evidence'], [])
                self.assertTrue(case['steps'] and case['expected'] and case['required_evidence'])
            formal = prepare.formal_module()
            report = json.loads((path / 'formal-report.json').read_text())
            self.assertEqual(report, formal.template())
            self.assertEqual(len(report['cases']), 23)
            self.assertEqual(formal.validate(report, path)[0], 2)  # missing real identity
            report['candidate'] = {'sha256': 'a' * 64, 'commit': 'b' * 40, 'architectures': ['arm64', 'x86_64'], 'signature': 'developer-id-notarized'}
            report['environment'] = {'system': 'synthetic fixture', 'applications': {name: 'fixture' for name in formal.APPLICATIONS}}
            self.assertEqual(formal.validate(report, path)[0], 3)  # still BLOCKED

    def test_existing_directory_is_preserved(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)
            (path / 'formal-report.json').write_text('existing evidence')
            with self.assertRaises(FileExistsError):
                prepare.prepare(path)
            self.assertEqual((path / 'formal-report.json').read_text(), 'existing evidence')
            self.assertEqual(len(list(path.iterdir())), 1)

    def test_symlink_destination_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            target = Path(temp) / 'target'
            target.mkdir()
            link = Path(temp) / 'link'
            link.symlink_to(target, target_is_directory=True)
            with self.assertRaises(FileExistsError):
                prepare.prepare(link)
            self.assertEqual(list(target.iterdir()), [])


if __name__ == '__main__':
    unittest.main()
