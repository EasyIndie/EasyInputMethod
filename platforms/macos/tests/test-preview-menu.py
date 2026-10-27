"""Exercise the isolated preview menu with real FFI, without displaying windows."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from local_acceptance_support import output_directory, record_probe

ROOT = Path(__file__).resolve().parents[3]


def stamp(path):
    return hashlib.sha256(path.read_bytes()).digest() if path.exists() else None


@unittest.skipUnless(sys.platform == 'darwin', 'requires AppKit')
class PreviewMenuTests(unittest.TestCase):
    def test_real_shared_menu_and_private_session(self):
        # 断言读的是系统共享输入菜单；若本机还开着调试窗口（LampyrisPreview），菜单会多出条目，
        # 这条就会假失败（报告207 实测一次）。此时记 SKIP，不要当产品回归。
        running = subprocess.run(['pgrep', '-f', 'LampyrisPreview.app/Contents/MacOS/LampyrisPreview'],
                                 capture_output=True, text=True, check=False)
        if running.stdout.strip():
            self.skipTest('调试窗口 LampyrisPreview 正在运行，输入菜单不干净')
        real = Path.home() / 'Library/Application Support/Lampyris'
        protected = [real / 'config.toml', real / 'user-dictionary.tsv']
        before = {path: (path.read_bytes() if path.exists() else None) for path in protected}
        with tempfile.TemporaryDirectory(prefix='lampyris-preview-menu-') as folder:
            temporary = Path(folder)
            shutil.copyfile(ROOT / 'platforms/macos/tests/preview-menu.swift', temporary / 'main.swift')
            environment = {**os.environ, 'CARGO_NET_OFFLINE': 'true',
                           'CLANG_MODULE_CACHE_PATH': str(temporary / 'module-cache')}
            commands = [
                (['cargo', 'build', '--release', '-p', 'ime-ffi'], 60),
                (['swiftc', '-warnings-as-errors', '-I', str(ROOT / 'crates/ime-ffi/include'),
                  str(temporary / 'main.swift'),
                  str(ROOT / "platforms/macos/tests/LocalAcceptanceEvidence.swift"),
                  *[str(ROOT / 'platforms/macos/Sources' / name) for name in ['ImeSession.swift', 'Config.swift', 'CandidateWindow.swift', 'InputMenu.swift']],
                  str(ROOT / 'platforms/macos/Preview/InputMenuPreview.swift'),
                  str(ROOT / 'target/release/libime_ffi.a'), '-framework', 'AppKit', '-o', str(temporary / 'probe')], 45),
                ([str(temporary / 'probe'), str(temporary), str(ROOT / 'data/generated')], 10),
            ]
            try:
                for command, timeout in commands:
                    if command[0] == str(temporary / "probe"):
                        record_probe(temporary / "probe")
                    result = subprocess.run(command, cwd=ROOT, env=environment, capture_output=True, text=True, timeout=timeout)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('PASS preview-menu', result.stdout)
            finally:
                violation, appended = [], False
                for path in protected:
                    original = before[path]
                    current = path.read_bytes() if path.exists() else None
                    if current == original:
                        continue
                    # 真实词库是追加写的：用户在本机并发键入会让它变长。那不是私有会话泄漏，
                    # 但也无法区分「只追加」的泄漏，所以只记 SKIP，不冒充 PASS（报告213）。
                    if (path.name == 'user-dictionary.tsv' and original is not None
                            and current is not None and current.startswith(original)):
                        appended = True
                        continue
                    violation.append(path.name)
            self.assertEqual(violation, [], 'real config/dictionary changed')
            if appended:
                self.skipTest('真实词库在运行期间被键入追加，无法判定是否私有会话泄漏')


if __name__ == '__main__':
    unittest.main()
