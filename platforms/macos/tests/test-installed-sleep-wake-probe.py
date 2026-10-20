#!/usr/bin/env python3
"""Sleep/wake probe contract: judge by the proven TextEdit probe on both sides."""
import importlib.util
from pathlib import Path
import unittest

HERE = Path(__file__).with_name('run-installed-sleep-wake-probe.py')
SPEC = importlib.util.spec_from_file_location('probe', HERE)
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


class Contract(unittest.TestCase):
    def test_uses_the_textedit_probe_as_the_judge(self):
        self.assertTrue(probe.TEXTEDIT.exists())
        self.assertIn('run-installed-textedit-probe.py', probe.TEXTEDIT.name)

    def test_records_state_on_both_sides_and_real_data(self):
        source = HERE.read_text(encoding='utf-8')
        for field in ("'preSource'", "'postSource'", "'preHost'", "'postHost'",
                      "'realDataUnchanged'", "'sourceResetOnWake'"):
            self.assertIn(field, source)

    def test_sleep_goes_through_pmset_and_reanchors_the_source(self):
        source = HERE.read_text(encoding='utf-8')
        self.assertIn("'/usr/bin/pmset', 'sleepnow'", source)
        self.assertIn('journal_path', source)

    def test_result_is_written_owner_only(self):
        source = HERE.read_text(encoding='utf-8')
        self.assertIn('os.chmod(result, 0o600)', source)


if __name__ == '__main__':
    unittest.main()
