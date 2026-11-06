"""Every probe that opens UI windows must clean up after itself (report 231).

这条测试把「验收跑完必须清场」固化成机器门禁：新增一个会开窗口/拉起应用的探针脚本，
却没有接 cleanup-windows.sh + trap，就会在这里挂掉。
"""
from pathlib import Path
import re
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
PROBE_DIR = ROOT / 'tools/macos-probe'

# 只要脚本里出现这些动作，就说明它会留下窗口或进程，必须自清场。
GUI_MARKERS = (
    'open -a TextEdit', 'open -a Safari', 'open -a "Google Chrome"',
    'open -a "/Applications/Xcode', 'open -n /tmp/lampyris-imetype.app',
    'lampyris-imetype.app',
)
# 这些脚本本身就是"清理器/构建器/探测器"，不产生窗口，不需要接 trap。
ALLOWLIST = {
    'cleanup-windows.sh',
    'build-imetype-app.sh',
    'acceptance-preflight.sh',
}

CLEANUP_CALL = 'cleanup-windows.sh'
TRAP = re.compile(r'^\s*trap\s+.+\b(EXIT|INT)\b', re.M)


def violations_for(path: Path, text: str):
    """返回该脚本的违规说明列表（空 = 合规）。"""
    problems = []
    if path.name in ALLOWLIST:
        return problems
    touches_gui = [marker for marker in GUI_MARKERS if marker in text]
    if not touches_gui:
        return problems
    if CLEANUP_CALL not in text:
        problems.append(f'{path.name}: 会开窗口（{touches_gui[0]}…）但没有调用 {CLEANUP_CALL}')
    if not TRAP.search(text):
        problems.append(f'{path.name}: 会开窗口但没有 trap EXIT/INT，失败或 Ctrl-C 时会留下窗口')
    return problems


class ProbeCleanupTests(unittest.TestCase):
    def test_gui_probes_register_cleanup(self):
        problems = []
        for path in sorted(PROBE_DIR.glob('*.sh')):
            problems.extend(violations_for(path, path.read_text(encoding='utf-8')))
        self.assertEqual(problems, [], '探针脚本必须自清场：\n' + '\n'.join(problems))

    def test_cleanup_script_is_executable_and_safe(self):
        cleanup = PROBE_DIR / 'cleanup-windows.sh'
        self.assertTrue(cleanup.is_file(), '缺少 cleanup-windows.sh')
        self.assertTrue(cleanup.stat().st_mode & 0o111, 'cleanup-windows.sh 必须可执行')
        text = cleanup.read_text(encoding='utf-8')
        # 浏览器永不退出：用户可能开着真实会话，只允许关我们自己的标签。
        self.assertIn('never-quit', text, '清理器必须显式拒绝退出浏览器')
        # 只在应用已在运行时才发 AppleScript，否则 `tell application` 会把应用重新拉起来。
        self.assertIn('is_running', text, '清理器必须先用 pgrep 判断应用是否在运行')

    def test_entry_points_all_wire_cleanup(self):
        for name in ('acceptance-auto.sh', 'quality-samples.sh', 'client-matrix.sh', 'acceptance-full.sh'):
            text = (PROBE_DIR / name).read_text(encoding='utf-8')
            self.assertIn(CLEANUP_CALL, text, f'{name} 必须调用 {CLEANUP_CALL}')
            self.assertTrue(TRAP.search(text), f'{name} 必须 trap EXIT/INT')

    def test_violation_is_actually_detected(self):
        """反向自检：没有 trap 的假脚本必须被判违规，否则这条门禁是空转。"""
        with tempfile.TemporaryDirectory() as folder:
            fake = Path(folder) / 'fake-probe.sh'
            fake.write_text('#!/bin/sh\nopen -a TextEdit\nprint stuff\n', encoding='utf-8')
            problems = violations_for(fake, fake.read_text(encoding='utf-8'))
            self.assertGreaterEqual(len(problems), 2, problems)

            good = Path(folder) / 'good-probe.sh'
            good.write_text('#!/bin/sh\ntrap cleanup_run EXIT\ncleanup_run() { cleanup-windows.sh; }\nopen -a TextEdit\n', encoding='utf-8')
            self.assertEqual(violations_for(good, good.read_text(encoding='utf-8')), [])


if __name__ == '__main__':
    unittest.main()
