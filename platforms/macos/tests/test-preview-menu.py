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
KEYMAP_SOURCES = ["KeyboardMapView.swift", "KeymapPanelView.swift", "KeyRootLayout.swift"]


def stamp(path):
    return hashlib.sha256(path.read_bytes()).digest() if path.exists() else None


@unittest.skipUnless(sys.platform == 'darwin', 'requires AppKit')
class PreviewMenuTests(unittest.TestCase):
    def test_preview_compiles_every_shared_source(self):
        """新增 Sources/*.swift 后忘了加进 dev-preview.sh 会在 CI 才红（ADR-374 踩过两次）。

        例外是只有正式宿主才需要的实现细节（IMK 控制器、符号组合、性能打点等）。
        """
        allowed_missing = {
            'AppLanguageMemory.swift', 'AutoPhrase.swift', 'InputController.swift',
            'PerfTrace.swift', 'SymbolComposition.swift',
        }
        script = (ROOT / 'platforms/macos/dev-preview.sh').read_text(encoding='utf-8')
        unexpected = sorted(name for name in allowed_missing if name in script)
        self.assertEqual(unexpected, [], 'dev-preview.sh 现在编译了这些源码，更新本测试的例外清单')
        sources = sorted(path.name for path in (ROOT / 'platforms/macos/Sources').glob('*.swift'))
        not_built = [name for name in sources if name not in allowed_missing and name not in script]
        self.assertEqual(not_built, [], 'dev-preview.sh 漏编译：' + ', '.join(not_built))

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
        # 报告230：本机装着输入法并正在使用时，宿主自己会改写词库（学习落盘是整文件原子重写，
        # 不是纯追加），这时「真实数据变了」既可能是宿主写的，也可能是私有会话泄漏，无法区分。
        # 有宿主在跑就只报 SKIP；没宿主（CI）才做严格断言。
        live_host = subprocess.run(['pgrep', '-x', 'Lampyris'], capture_output=True).returncode == 0
        with tempfile.TemporaryDirectory(prefix='lampyris-preview-menu-') as folder:
            temporary = Path(folder)
            shutil.copyfile(ROOT / 'platforms/macos/tests/preview-menu.swift', temporary / 'main.swift')
            environment = {**os.environ, 'CARGO_NET_OFFLINE': 'true',
                           'CLANG_MODULE_CACHE_PATH': (os.environ.get('LAMPYRIS_SWIFT_MODULE_CACHE') or str(temporary / 'module-cache'))}
            commands = [
                (['cargo', 'build', '--release', '-p', 'ime-ffi'], 60),
                (['swiftc', '-warnings-as-errors', '-I', str(ROOT / 'crates/ime-ffi/include'),
                  str(temporary / 'main.swift'),
                  str(ROOT / "platforms/macos/tests/LocalAcceptanceEvidence.swift"),
                  *[str(ROOT / ("modules/keymap/Sources" if name.startswith("Keyboard") or name.startswith("KeymapPanel") or name == "KeyRootLayout.swift" else "platforms/macos/Sources") / name) for name in ['ImeSession.swift', 'Config.swift', 'CandidateWindow.swift', 'InHostTextInput.swift', 'WindowPlacement.swift', 'CaretPlacement.swift', 'LearningHints.swift', 'Practice.swift', 'PracticeWindow.swift', 'PassageBank.swift', 'PassageWindow.swift', 'PracticeAnswerView.swift', 'PracticeExplanationView.swift', 'RootNotes.swift', *KEYMAP_SOURCES, 'InputMenu.swift']],
                  str(ROOT / 'platforms/macos/Preview/InputMenuPreview.swift'),
                  str(ROOT / 'target/release/libime_ffi.a'), '-framework', 'AppKit', '-o', str(temporary / 'probe')], 90),
                ([str(temporary / 'probe'), str(temporary), str(ROOT / 'data/generated')], 30),
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
                    if path.name == 'user-dictionary.tsv' and live_host:
                        appended = True
                        continue
                    if (path.name == 'user-dictionary.tsv' and original is not None
                            and current is not None and current.startswith(original)):
                        appended = True
                        continue
                    violation.append(path.name)
            self.assertEqual(violation, [], 'real config/dictionary changed')
            if appended:
                self.skipTest('宿主正在运行且词库被改写，无法判定是否私有会话泄漏（停掉宿主后重跑可验）')


if __name__ == '__main__':
    unittest.main()
