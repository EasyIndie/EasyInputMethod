#!/usr/bin/env python3
"""Require input and recovery evidence; never accept merely clean exit."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('probe', Path(__file__).with_name('run-installed-terminal-probe.py'))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class ResultTests(unittest.TestCase):
    def test_normal_requires_every_protection(self):
        evidence = dict.fromkeys(('bindingVerified', 'closed', 'focusVerified', 'sourceAndEnabledRestored', 'realDataUnchanged'), True)
        result = {'classification': 'committed', 'ttyRestored': True}
        self.assertTrue(probe.acceptance_passed(evidence, result, 'normal'))
        for field in evidence:
            self.assertFalse(probe.acceptance_passed({**evidence, field: False}, result, 'normal'))
        self.assertFalse(probe.acceptance_passed(evidence, {**result, 'classification': 'prefix'}, 'normal'))

    def test_interrupt_requires_prefix_injection_and_known_bytes(self):
        evidence = dict.fromkeys(('bindingVerified', 'closed', 'focusVerified', 'sourceAndEnabledRestored', 'realDataUnchanged', 'prefixVerified'), True)
        evidence['injected'] = 15
        result = {'classification': 'empty', 'ttyRestored': True}
        self.assertTrue(probe.acceptance_passed(evidence, result, 'TERM'))
        self.assertFalse(probe.acceptance_passed({**evidence, 'prefixVerified': False}, result, 'TERM'))
        self.assertFalse(probe.acceptance_passed({k: v for k, v in evidence.items() if k != 'injected'}, result, 'TERM'))
        self.assertFalse(probe.acceptance_passed(evidence, {**result, 'classification': 'unexpected'}, 'TERM'))


if __name__ == '__main__':
    unittest.main()
