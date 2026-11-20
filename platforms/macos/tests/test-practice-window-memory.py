"""Exercise 练习窗口 lifecycle: closing the practice window must release its views (P1-M2)."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from local_acceptance_support import record_probe

ROOT = Path(__file__).resolve().parents[3]
KEYMAP_SOURCES = ["KeyboardMapView.swift", "KeymapPanelView.swift", "KeyRootLayout.swift"]
SOURCES = [
    "ImeSession.swift", "Config.swift", "CandidateWindow.swift", "InHostTextInput.swift",
    "WindowPlacement.swift", "CaretPlacement.swift", "LearningHints.swift", "Practice.swift",
    "PracticeWindow.swift", "PassageBank.swift", "PassageWindow.swift", "PracticeAnswerView.swift",
    "PracticeExplanationView.swift", "RootNotes.swift", *KEYMAP_SOURCES,
]


@unittest.skipUnless(sys.platform == "darwin", "requires AppKit")
class PracticeWindowMemoryTests(unittest.TestCase):
    def test_closing_the_practice_window_releases_its_views(self):
        with tempfile.TemporaryDirectory(prefix="lampyris-practice-memory-") as folder:
            temporary = Path(folder)
            work = temporary / "work"
            resources = temporary / "Resources"
            work.mkdir()
            resources.mkdir()
            shutil.copyfile(ROOT / "platforms/macos/tests/practice-window-memory.swift",
                            temporary / "main.swift")
            # 练习窗口构造要读的资源与 bundle 内同名（题库、B0 学习区、键位图）。
            for relative in ["data/generated/B0-runtime.tsv", "modules/keymap/data/key-roots-wubi86.tsv",
                             "data/generated/wubi86-core.tsv", "data/sources/wubi86-level3-codes.tsv"]:
                shutil.copyfile(ROOT / relative, resources / Path(relative).name)
            environment = {
                **os.environ,
                "CARGO_NET_OFFLINE": "true",
                "CLANG_MODULE_CACHE_PATH": (os.environ.get("LAMPYRIS_SWIFT_MODULE_CACHE")
                                            or str(temporary / "module-cache")),
            }
            sources = [str(ROOT / ("modules/keymap/Sources" if name in KEYMAP_SOURCES
                                   else "platforms/macos/Sources") / name) for name in SOURCES]
            commands = [
                (["cargo", "build", "--release", "-p", "ime-ffi"], 120),
                # -O：内存量级要贴近发布包，debug 的 ARC/临时对象会把信号淹没。
                (["swiftc", "-O", "-warnings-as-errors", "-I", str(ROOT / "crates/ime-ffi/include"),
                  str(temporary / "main.swift"), *sources,
                  str(ROOT / "target/release/libime_ffi.a"), "-framework", "AppKit",
                  "-o", str(temporary / "probe")], 180),
                ([str(temporary / "probe"), str(work)], 120),
            ]
            result = None
            for command, timeout in commands:
                if command[0] == str(temporary / "probe"):
                    record_probe(temporary / "probe")
                result = subprocess.run(command, cwd=ROOT, env=environment,
                                        capture_output=True, text=True, timeout=timeout)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("PASS practice-window-memory", result.stdout)


if __name__ == "__main__":
    unittest.main()
