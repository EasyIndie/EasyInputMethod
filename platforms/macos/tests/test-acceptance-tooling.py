#!/usr/bin/env python3
"""Guard the acceptance driver contracts that reports 207/209/212 were about."""
import json
import pathlib
import re
import shutil
import stat
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
PROBE = ROOT / 'tools/macos-probe'


class AcceptanceDriver(unittest.TestCase):
    def test_scripts_parse(self):
        for name in ('acceptance-preflight.sh', 'acceptance-full.sh', 'quality-samples.sh'):
            result = subprocess.run(['sh', '-n', str(PROBE / name)], capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 0, f'{name}: {result.stderr}')

    def test_full_driver_records_tsv(self):
        """步骤明细用 TSV：各步骤自己输出 JSON，嵌进 JSON 会写坏（报告212 的实施笔记）。"""
        text = (PROBE / 'acceptance-full.sh').read_text()
        self.assertIn('steps.tsv', text)
        self.assertNotIn('steps.jsonl', text)
        self.assertIn('SKIP_MEMORY', text)

    def test_preflight_reports_lock_and_single_instance(self):
        """报告209（锁屏白等半小时）与报告207（多实例 TextEdit 假 FAIL）都要在前置里挡掉。"""
        text = (PROBE / 'acceptance-preflight.sh').read_text()
        self.assertIn('screen_lock', text)
        self.assertIn('clients_single_instance', text)
        self.assertIn('session', text)

    def test_session_probe_exists_and_builds(self):
        self.assertTrue((PROBE / 'session.swift').is_file())
        binary = PROBE / 'bin' / 'session'
        if not binary.exists():  # 未构建时跳过（CI 不跑 native 探针）
            self.skipTest('探针未构建')
        result = subprocess.run([str(binary)], capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertIn('locked', payload)
        self.assertIn('on_console', payload)

    def test_preflight_marks_lock_as_blocked(self):
        """用假 session 二进制模拟锁屏：必须落到 ready=false（调用方据此 SKIP，而不是记 FAIL）。"""
        with tempfile.TemporaryDirectory() as directory:
            fake = pathlib.Path(directory)
            # 复制前置脚本到临时目录，旁边放一个只会说谎的 bin/ 目录。
            shutil.copy(PROBE / 'acceptance-preflight.sh', fake / 'acceptance-preflight.sh')
            (fake / 'bin').mkdir()
            session = fake / 'bin' / 'session'
            session.write_text('#!/bin/sh\necho \'{"locked":true,"on_console":true,"user":"x"}\'\n')
            session.chmod(session.stat().st_mode | stat.S_IXUSR)
            for name in ('tissrc', 'imetype', 'axfocus'):
                stub = fake / 'bin' / name
                stub.write_text('#!/bin/sh\nexit 0\n')
                stub.chmod(stub.stat().st_mode | stat.S_IXUSR)
            result = subprocess.run(['sh', str(fake / 'acceptance-preflight.sh')],
                                    capture_output=True, text=True, check=False,
                                    env={'HOME': str(fake), 'PATH': '/usr/bin:/bin:/usr/sbin:/sbin'})
            self.assertEqual(result.returncode, 78, result.stdout + result.stderr)
            self.assertRegex(result.stdout, r'"screen_lock":"[^"]*锁定')


if __name__ == '__main__':
    unittest.main()
