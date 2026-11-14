"""U1-4 宿主内完整使用指南：步骤、动态快捷键与翻页（离屏，不显示窗口）。"""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


@unittest.skipUnless(sys.platform == "darwin", "requires AppKit")
class OnboardingGuideTests(unittest.TestCase):
    def test_steps_and_navigation(self):
        with tempfile.TemporaryDirectory(prefix="lampyris-onboarding-") as folder:
            root = Path(folder)
            app = root / "Probe.app"
            binary = app / "Contents/MacOS/Probe"
            resources = app / "Contents/Resources"
            binary.parent.mkdir(parents=True)
            resources.mkdir(parents=True)
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
                "CFBundleIdentifier": "cn.jokerhub.lampyris.onboardingprobe",
                "CFBundleExecutable": "Probe", "CFBundlePackageType": "APPL",
            }))
            shutil.copyfile(ROOT / "platforms/macos/tests/onboarding-guide.swift", root / "main.swift")
            sources = [p for p in sorted((ROOT / "platforms/macos/Sources").glob("*.swift"))
                       if p.name != "main.swift"]
            environment = {**os.environ, "CARGO_NET_OFFLINE": "true",
                           "CLANG_MODULE_CACHE_PATH":
                               os.environ.get("LAMPYRIS_SWIFT_MODULE_CACHE") or str(root / "cache")}
            commands = [
                ["cargo", "build", "--release", "-p", "ime-ffi"],
                ["swiftc", "-warnings-as-errors", "-I", str(ROOT / "crates/ime-ffi/include"),
                 str(root / "main.swift"), *[str(p) for p in sources],
                 *[str(p) for p in sorted((ROOT / "modules/keymap/Sources").glob("*.swift"))],
                 str(ROOT / "target/release/libime_ffi.a"),
                 "-framework", "AppKit", "-framework", "InputMethodKit",
                 "-framework", "UniformTypeIdentifiers",
                 "-o", str(binary)],
                [str(binary), str(root)],
            ]
            for command in commands:
                result = subprocess.run(command, cwd=ROOT, env=environment,
                                        capture_output=True, text=True, timeout=240)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertNotIn("Unable to simultaneously satisfy constraints", result.stderr)
            self.assertIn("PASS onboarding-guide", result.stdout)


if __name__ == "__main__":
    unittest.main()
