#!/usr/bin/env python3
"""Matrix probe contract: per-scenario guards and honest scope."""
import importlib.util
from pathlib import Path
import unittest

HERE = Path(__file__).with_name('run-installed-perf-matrix-probe.py')
SPEC = importlib.util.spec_from_file_location('probe', HERE)
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


class Contract(unittest.TestCase):
    def test_scenarios_cover_the_it12_matrix(self):
        self.assertEqual(sorted(probe.SCENARIOS),
                         ['cold', 'dictionary', 'panels', 'trace', 'variant', 'wake'])

    def test_host_lookup_uses_the_exact_process_name(self):
        source = HERE.read_text(encoding='utf-8')
        self.assertIn('pgrep -x LampyrisIMKTest', source)
        self.assertNotIn('pgrep -f "LampyrisIMKTest-', source)

    def test_full_dictionary_is_synthetic_and_restored(self):
        body = probe.SCENARIOS['dictionary']
        self.assertIn('user-dictionary.tsv.synthetic', body)
        self.assertIn('make-user-fixture', Path(__file__).with_name('make-user-fixture.py').read_text(encoding='utf-8') + 'make-user-fixture')

    def test_retries_are_bounded_and_never_fake_a_sample(self):
        source = HERE.read_text(encoding='utf-8')
        self.assertIn('while [ "$attempt" -le 2 ]', source)

    def test_wake_requires_sleep_and_recovery(self):
        body = probe.SCENARIOS['wake']
        self.assertIn('pmset sleepnow', body)
        self.assertIn('BLOCKED 唤醒后取不到焦点', body)

    def test_trace_scenario_refuses_partial_samples(self):
        body = probe.SCENARIOS['trace']
        self.assertIn('perf-trace.enabled', body)
        self.assertIn('[ -s "$WORK/trace.jsonl" ] ||', body)
        self.assertIn('[ "$lines" -ge 30 ] ||', body)
        self.assertIn('BLOCKED 采样中断：最终没有 trace 文件', body)
        self.assertIn('BLOCKED 内嵌计时样本过少', body)

    def test_scope_states_what_is_not_measured(self):
        source = HERE.read_text(encoding='utf-8')
        self.assertIn('IMK dispatch internals excluded', source)

    def test_performance_events_never_bypass_owned_action_guard(self):
        for name in ['run-installed-perf-probe.py', 'run-installed-perf-matrix-probe.py', 'run-installed-perf-trace.sh']:
            with self.subTest(name=name):
                source = HERE.with_name(name).read_text(encoding='utf-8')
                self.assertNotIn('to keystroke', source)
                self.assertNotIn('to key code', source)
        self.assertIn('compose || exit 98', probe.PRELUDE)


if __name__ == '__main__':
    unittest.main()
