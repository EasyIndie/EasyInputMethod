"""Native offscreen candidate UI contracts, never showing a window."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


@unittest.skipUnless(sys.platform == "darwin", "requires AppKit")
class CandidatePresentationTests(unittest.TestCase):
    def test_native_view_and_real_ffi_paging(self):
        with tempfile.TemporaryDirectory(prefix="lampyris-candidate-ui-") as folder:
            temporary = Path(folder)
            output = ROOT / "platforms/macos/build/mvp-ui01-review"
            output.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / "platforms/macos/tests/candidate-presentation.swift", temporary / "main.swift")
            environment = {**os.environ, "CARGO_NET_OFFLINE": "true",
                           "CLANG_MODULE_CACHE_PATH": str(temporary / "module-cache")}
            commands = [
                (["cargo", "build", "--release", "-p", "ime-ffi"], 60),
                (["swiftc", "-warnings-as-errors", "-I", str(ROOT / "crates/ime-ffi/include"),
                  str(temporary / "main.swift"),
                  *[str(ROOT / "platforms/macos/Sources" / name) for name in
                    ["ImeSession.swift", "Config.swift", "CandidateWindow.swift"]],
                  str(ROOT / "target/release/libime_ffi.a"), "-framework", "AppKit",
                  "-o", str(temporary / "probe")], 45),
                ([str(temporary / "probe"), str(temporary), str(output)], 10),
            ]
            for command, timeout in commands:
                result = subprocess.run(command, cwd=ROOT, env=environment,
                                        capture_output=True, text=True, timeout=timeout)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("PASS candidate-presentation", result.stdout)


if __name__ == "__main__":
    unittest.main()
