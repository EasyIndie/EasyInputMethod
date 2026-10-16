"""Exercise the isolated preview menu with real FFI, without displaying windows."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


def stamp(path):
    return hashlib.sha256(path.read_bytes()).digest() if path.exists() else None


@unittest.skipUnless(sys.platform == 'darwin', 'requires AppKit')
class PreviewMenuTests(unittest.TestCase):
    def test_real_shared_menu_and_private_session(self):
        real = Path.home() / 'Library/Application Support/Lampyris'
        protected = [real / 'config.toml', real / 'user-dictionary.tsv']
        before = [stamp(path) for path in protected]
        with tempfile.TemporaryDirectory(prefix='lampyris-preview-menu-') as folder:
            temporary = Path(folder)
            shutil.copyfile(ROOT / 'platforms/macos/tests/preview-menu.swift', temporary / 'main.swift')
            environment = {**os.environ, 'CARGO_NET_OFFLINE': 'true',
                           'CLANG_MODULE_CACHE_PATH': str(temporary / 'module-cache')}
            commands = [
                (['cargo', 'build', '--release', '-p', 'ime-ffi'], 60),
                (['swiftc', '-warnings-as-errors', '-I', str(ROOT / 'crates/ime-ffi/include'),
                  str(temporary / 'main.swift'),
                  *[str(ROOT / 'platforms/macos/Sources' / name) for name in ['ImeSession.swift', 'Config.swift', 'CandidateWindow.swift', 'InputMenu.swift']],
                  str(ROOT / 'platforms/macos/Preview/InputMenuPreview.swift'),
                  str(ROOT / 'target/release/libime_ffi.a'), '-framework', 'AppKit', '-o', str(temporary / 'probe')], 45),
                ([str(temporary / 'probe'), str(temporary), str(ROOT / 'data/generated')], 10),
            ]
            try:
                for command, timeout in commands:
                    result = subprocess.run(command, cwd=ROOT, env=environment, capture_output=True, text=True, timeout=timeout)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('PASS preview-menu', result.stdout)
            finally:
                self.assertEqual([stamp(path) for path in protected], before, 'real config/dictionary changed')


if __name__ == '__main__':
    unittest.main()
