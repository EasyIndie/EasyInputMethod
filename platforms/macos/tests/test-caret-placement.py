"""光标跟随几何（ADR-301）：纯函数不变量，不需要窗口或 IME 会话。"""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


@unittest.skipUnless(sys.platform == "darwin", "requires AppKit geometry")
class CaretPlacementTests(unittest.TestCase):
    def test_placement_invariants(self):
        with tempfile.TemporaryDirectory(prefix="lampyris-caret-placement-") as folder:
            temporary = Path(folder)
            shutil.copyfile(ROOT / "platforms/macos/tests/caret-placement.swift",
                            temporary / "main.swift")
            environment = {**os.environ,
                           "CLANG_MODULE_CACHE_PATH": str(temporary / "module-cache")}
            result = subprocess.run(
                ["swiftc", "-warnings-as-errors", str(temporary / "main.swift"),
                 str(ROOT / "platforms/macos/Sources/CaretPlacement.swift"),
                 "-framework", "AppKit", "-o", str(temporary / "probe")],
                cwd=ROOT, env=environment, capture_output=True, text=True, timeout=45)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            run = subprocess.run([str(temporary / "probe")], cwd=ROOT, env=environment,
                                 capture_output=True, text=True, timeout=10)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn("PASS caret-placement", run.stdout)


if __name__ == "__main__":
    unittest.main()
