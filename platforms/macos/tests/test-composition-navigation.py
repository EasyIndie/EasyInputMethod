"""Run actual Swift/FFI event classification; no desktop interaction."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


@unittest.skipUnless(sys.platform == "darwin", "requires macOS NSEvent")
class CompositionNavigationTests(unittest.TestCase):
    def test_real_swift_event_classifier_with_private_config(self):
        with tempfile.TemporaryDirectory(prefix="lampyris-event-boundary-") as folder:
            temporary = Path(folder)
            environment = {**os.environ, "CARGO_NET_OFFLINE": "true",
                           "CLANG_MODULE_CACHE_PATH": str(temporary / "module-cache"),
                           "SWIFT_MODULECACHE_PATH": str(temporary / "module-cache")}
            shutil.copyfile(ROOT / "platforms/macos/tests/composition-navigation.swift", temporary / "main.swift")
            commands = [
                (["cargo", "build", "--release", "-p", "ime-ffi"], 60),
                (["swiftc", "-warnings-as-errors", "-I", str(ROOT / "crates/ime-ffi/include"),
                  str(temporary / "main.swift"),
                  *[str(ROOT / "platforms/macos/Sources" / name) for name in
                    ["ImeSession.swift", "Config.swift", "CandidateWindow.swift"]],
                  str(ROOT / "target/release/libime_ffi.a"), "-framework", "AppKit",
                  "-o", str(temporary / "probe")], 45),
                ([str(temporary / "probe"), str(temporary)], 10),
            ]
            for command, timeout in commands:
                result = subprocess.run(command, cwd=ROOT, env=environment, capture_output=True,
                                        text=True, timeout=timeout)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("PASS composition-navigation", result.stdout)


if __name__ == "__main__":
    unittest.main()
