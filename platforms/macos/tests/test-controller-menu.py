"""Real IMK controller dispatch in an unregistered app, with private data only."""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


@unittest.skipUnless(sys.platform == "darwin", "requires InputMethodKit")
class ControllerMenuTests(unittest.TestCase):
    def test_real_imk_dispatch_and_reactivation(self):
        with tempfile.TemporaryDirectory(prefix="lampyris-controller-menu-") as folder:
            root = Path(folder)
            app = root / "Probe.app"
            binary = app / "Contents/MacOS/Probe"
            binary.parent.mkdir(parents=True)
            resources = app / "Contents/Resources"
            resources.mkdir()
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
                "CFBundleIdentifier": "cn.jokerhub.lampyris.controllerprobe",
                "CFBundleExecutable": "Probe", "CFBundlePackageType": "APPL",
            }))
            for name in ["wubi86-core.tsv", "pinyin-chars.tsv", "pinyin-core.tsv", "variant-s2t.tsv"]:
                shutil.copyfile(ROOT / "data/generated" / name, resources / name)
            shutil.copyfile(ROOT / "platforms/macos/tests/controller-menu.swift", root / "main.swift")
            environment = {**os.environ, "CARGO_NET_OFFLINE": "true",
                           "CLANG_MODULE_CACHE_PATH": str(root / "cache")}
            commands = [
                ["cargo", "build", "--release", "-p", "ime-ffi"],
                ["clang", "-fmodules", "-fmodules-cache-path=" + str(root / "cache"),
                 "-Wall", "-Wextra", "-Werror", "-c",
                 str(ROOT / "platforms/macos/tests/IMKMenuServiceProbe.m"),
                 "-o", str(root / "service-probe.o")],
                ["swiftc", "-warnings-as-errors", "-I", str(ROOT / "crates/ime-ffi/include"),
                 "-import-objc-header", str(ROOT / "platforms/macos/tests/IMKMenuServiceProbe.h"),
                 str(root / "main.swift"),
                 *[str(p) for p in sorted((ROOT / "platforms/macos/Sources").glob("*.swift"))
                   if p.name != "main.swift"], str(ROOT / "target/release/libime_ffi.a"),
                 str(root / "service-probe.o"),
                 "-framework", "AppKit", "-framework", "InputMethodKit", "-o", str(binary)],
                [str(binary), str(root)],
            ]
            for command in commands:
                result = subprocess.run(command, cwd=ROOT, env=environment,
                                        capture_output=True, text=True, timeout=90)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("PASS controller-menu", result.stdout)


if __name__ == "__main__":
    unittest.main()
