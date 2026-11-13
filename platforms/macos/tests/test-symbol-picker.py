"""U3-5 符号 / emoji 目录、面板与前缀状态（离屏，不显示窗口）。"""
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
class SymbolPickerTests(unittest.TestCase):
    def test_catalog_search_and_picker(self):
        with tempfile.TemporaryDirectory(prefix="lampyris-symbol-picker-") as folder:
            root = Path(folder)
            app = root / "Probe.app"
            binary = app / "Contents/MacOS/Probe"
            resources = app / "Contents/Resources"
            binary.parent.mkdir(parents=True)
            resources.mkdir(parents=True)
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
                "CFBundleIdentifier": "cn.jokerhub.lampyris.symbolprobe",
                "CFBundleExecutable": "Probe", "CFBundlePackageType": "APPL",
            }))
            shutil.copyfile(ROOT / "data/symbols.tsv", resources / "symbols.tsv")
            shutil.copyfile(ROOT / "data/generated/emoji.tsv", resources / "emoji.tsv")
            shutil.copyfile(ROOT / "platforms/macos/tests/symbol-picker.swift", root / "main.swift")
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
                [str(binary)],
            ]
            for command in commands:
                result = subprocess.run(command, cwd=ROOT, env=environment,
                                        capture_output=True, text=True, timeout=240)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertNotIn("Unable to simultaneously satisfy constraints", result.stderr)
            self.assertIn("PASS symbol-picker", result.stdout)


if __name__ == "__main__":
    unittest.main()
