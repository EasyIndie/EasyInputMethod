"""Compile the real AX adapter; exercise policy with no desktop actions."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


class GuardedAXTests(unittest.TestCase):
    @unittest.skipUnless(sys.platform == 'darwin', 'macOS native adapter')
    def test_order_and_fail_closed_without_desktop(self):
        with tempfile.TemporaryDirectory(prefix='lampyris-guarded-ax-') as folder:
            root = Path(folder)
            for source, name in [('guarded-ax-tests.swift', 'test'), ('guarded-ax-main.swift', 'cli')]:
                shutil.copy2(HERE / source, root / 'main.swift')
                result = subprocess.run(['swiftc', '-warnings-as-errors', str(HERE / 'GuardedAXPress.swift'), str(root / 'main.swift'), '-o', str(root / name)], capture_output=True, text=True, timeout=60)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run([str(root / 'test')], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('PASS guarded-ax 10 scenarios', result.stdout)
            # CLI never acts on missing/unrecognized input.
            result = subprocess.run([str(root / 'cli')], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 3)
            self.assertIn('BLOCKED', result.stderr)


if __name__ == '__main__':
    unittest.main()
