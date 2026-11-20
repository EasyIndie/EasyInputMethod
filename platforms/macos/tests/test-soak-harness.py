#!/usr/bin/env python3
"""久用探针的口径契约（报告 331 / ADR-389）。

久用验收最容易出的错不是产品，而是**探针把自己量进去**：
- `vmmap` 会 task_suspend 目标，被暂停期间的按键被记成 300–600 ms 的"卡顿"（实测 10/10 轮）；
- footprint 只有冷启动窗口内可比（ADR-385），窗口外的读数不能当门禁；
- 久用以前完全不看延迟，内存好看但手感可能已经坏了。

这三条都不该靠人记住，所以钉成测试。
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SOAK = ROOT / 'tools/macos-probe/soak-session.sh'
FOOTPRINT = ROOT / 'tools/macos-probe/footprint.swift'


class SoakHarnessTests(unittest.TestCase):
    def test_sampling_never_suspends_the_target(self):
        text = SOAK.read_text(encoding='utf-8')
        code = '\n'.join(line.split('#', 1)[0] for line in text.splitlines())
        self.assertNotIn('vmmap', code, '久用探针不得用 vmmap 采样：它会挂起宿主，把按键量成卡顿')
        self.assertIn('BIN/footprint', code, '久用探针必须用不挂起的 footprint 采样')
        self.assertTrue(FOOTPRINT.is_file(), '缺少 tools/macos-probe/footprint.swift')
        source = FOOTPRINT.read_text(encoding='utf-8')
        self.assertIn('proc_pid_rusage', source, 'footprint 必须走 proc_pid_rusage（不暂停进程）')
        self.assertIn('ri_phys_footprint', source)

    def test_footprint_gate_matches_the_project_limit(self):
        text = SOAK.read_text(encoding='utf-8')
        match = re.search(r'FOOTPRINT_HARD_MB="\$\{FOOTPRINT_HARD_MB:-(\d+)\}"', text)
        self.assertIsNotNone(match, '久用探针缺少 FOOTPRINT_HARD_MB 默认值')
        self.assertEqual(match.group(1), '44', '久用硬门应与 perf-session 一致（44 MiB，不加高）')
        self.assertIn('footprint_gate', text, '必须报告 footprint 门禁是否在冷窗口内')
        self.assertIn('900 // 5', text, '冷启动窗口 900 s（ADR-385）没有被使用')

    def test_soak_gates_key_latency(self):
        text = SOAK.read_text(encoding='utf-8')
        self.assertIn('latency_p95_median_ms', text)
        self.assertIn('LATENCY_LIMIT_MS', text)
        match = re.search(r'LATENCY_LIMIT_MS = ([0-9.]+)', text)
        self.assertIsNotNone(match, '久用探针缺少延迟门禁阈值')
        self.assertEqual(float(match.group(1)), 40.0, '延迟门禁应等于 P2-3 的 40 ms 触发线')
        self.assertIn('latency_median <= LATENCY_LIMIT_MS', text, '延迟没有被真正判定')


if __name__ == '__main__':
    unittest.main()
