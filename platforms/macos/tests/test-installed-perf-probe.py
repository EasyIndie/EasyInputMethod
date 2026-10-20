#!/usr/bin/env python3
"""Perf probe contract: owned document, sampled latency, and an honest scope note."""
import importlib.util
from pathlib import Path
import unittest

HERE = Path(__file__).with_name('run-installed-perf-probe.py')
SPEC = importlib.util.spec_from_file_location('probe', HERE)
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


class Contract(unittest.TestCase):
    def test_requires_enough_samples(self):
        source = HERE.read_text(encoding='utf-8')
        self.assertIn('len(latencies) >= 12', source)
        self.assertIn('while [ "$attempt" -lt 15 ]', probe.BODY)

    def test_measures_host_memory_and_idle_cpu(self):
        self.assertIn('ps -o rss= -p "$host"', probe.BODY)
        self.assertIn('ps -o %cpu= -p "$host"', probe.BODY)

    def test_reports_the_harness_overhead_separately(self):
        source = HERE.read_text(encoding='utf-8')
        self.assertIn('osascriptOverheadMs', source)
        self.assertIn("'-e', 'return 1'", source)

    def test_scope_says_what_is_not_measured(self):
        source = HERE.read_text(encoding='utf-8')
        self.assertIn('excludes IMK dispatch internals', source)

    def test_waiter_reads_the_client_not_the_host(self):
        waiter = (Path(__file__).with_name('isolated-imk') / 'ax-text-wait.swift').read_text(encoding='utf-8')
        self.assertIn('kAXFocusedUIElementAttribute', waiter)
        self.assertIn('AXTextArea', waiter)


if __name__ == '__main__':
    unittest.main()
