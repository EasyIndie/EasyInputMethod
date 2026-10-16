"""Native offscreen tools UI contracts, never showing a window."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from local_acceptance_support import output_directory, record_probe

ROOT = Path(__file__).resolve().parents[3]


@unittest.skipUnless(sys.platform == "darwin", "requires AppKit")
class ToolsPresentationTests(unittest.TestCase):
    def test_native_forms_and_information_states(self):
        with tempfile.TemporaryDirectory(prefix="lampyris-tools-ui-") as folder:
            temporary = Path(folder)
            output = output_directory(ROOT / "platforms/macos/build/mvp-ui03-review")
            output.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / "platforms/macos/tests/tools-presentation.swift", temporary / "main.swift")
            environment = {**os.environ, "CARGO_NET_OFFLINE": "true",
                           "CLANG_MODULE_CACHE_PATH": str(temporary / "module-cache")}
            commands = [
                (["cargo", "build", "--release", "-p", "ime-ffi"], 60),
                (["swiftc", "-warnings-as-errors", "-I", str(ROOT / "crates/ime-ffi/include"),
                  str(temporary / "main.swift"),
                  str(ROOT / "platforms/macos/tests/LocalAcceptanceEvidence.swift"),
                  *[str(ROOT / "platforms/macos/Sources" / name) for name in
                    ["ImeSession.swift", "Config.swift", "CandidateWindow.swift", "Settings.swift", "Feedback.swift", "InfoWindow.swift",
                     "UserDictionary.swift", "Lookup.swift"]],
                  str(ROOT / "target/release/libime_ffi.a"), "-framework", "AppKit",
                  "-o", str(temporary / "probe")], 45),
                ([str(temporary / "probe"), str(temporary), str(output)], 10),
            ]
            for command, timeout in commands:
                if command[0] == str(temporary / "probe"):
                    record_probe(temporary / "probe")
                result = subprocess.run(command, cwd=ROOT, env=environment,
                                        capture_output=True, text=True, timeout=timeout)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertNotIn("Unable to simultaneously satisfy constraints", result.stderr)
            self.assertIn("PASS tools-presentation", result.stdout)


if __name__ == "__main__":
    unittest.main()
