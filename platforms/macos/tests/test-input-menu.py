"""Native menu action contracts; never open a menu or target the installed IMK host."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from local_acceptance_support import record_probe

ROOT = Path(__file__).resolve().parents[3]


@unittest.skipUnless(sys.platform == 'darwin', 'requires AppKit')
class InputMenuTests(unittest.TestCase):
    def test_current_state_and_mode_actions(self):
        with tempfile.TemporaryDirectory(prefix='lampyris-menu-') as folder:
            temporary = Path(folder)
            shutil.copyfile(ROOT / 'platforms/macos/tests/input-menu.swift', temporary / 'main.swift')
            environment = {**os.environ, 'CLANG_MODULE_CACHE_PATH': str(temporary / 'module-cache')}
            commands = [
                ['swiftc', '-warnings-as-errors', str(temporary / 'main.swift'),
                 str(ROOT / 'platforms/macos/tests/LocalAcceptanceEvidence.swift'),
                 str(ROOT / 'platforms/macos/Sources/InputMenu.swift'), '-framework', 'AppKit', '-o', str(temporary / 'probe')],
                [str(temporary / 'probe')],
            ]
            for command in commands:
                if command[0] == str(temporary / "probe"):
                    record_probe(temporary / "probe")
                result = subprocess.run(command, cwd=ROOT, env=environment, capture_output=True, text=True, timeout=45)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('PASS input-menu', result.stdout)


if __name__ == '__main__':
    unittest.main()
