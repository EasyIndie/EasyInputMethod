"""Native offscreen candidate UI contracts, never showing a window."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from local_acceptance_support import output_directory, record_probe

ROOT = Path(__file__).resolve().parents[3]
KEYMAP_SOURCES = ["KeyboardMapView.swift", "KeymapPanelView.swift", "KeyRootLayout.swift"]


@unittest.skipUnless(sys.platform == "darwin", "requires AppKit")
class WubiLearningTests(unittest.TestCase):
    def test_real_ffi_teaching_model(self):
        with tempfile.TemporaryDirectory(prefix="lampyris-learning-ui-") as folder:
            temporary = Path(folder)
            output = output_directory(ROOT / "platforms/macos/build/mvp-full-ui-review")
            output.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / "platforms/macos/tests/wubi-learning.swift", temporary / "main.swift")
            # 学习区结构化提示（ADR-311）：放到可执行文件同级的 Resources，走 B0 路径；
            # 同时保留"资源缺失 → D14 兜底"的用例（后续单独跑）。
            resources = temporary / "Resources"
            resources.mkdir()
            shutil.copyfile(ROOT / "data/generated/B0-runtime.tsv", resources / "B0-runtime.tsv")
            # 键位字根分布（modules/keymap 生成物）：与 bundle 内同名资源一致
            shutil.copyfile(ROOT / "modules/keymap/data/key-roots-wubi86.tsv",
                            resources / "key-roots-wubi86.tsv")
            environment = {**os.environ, "CARGO_NET_OFFLINE": "true",
                           "CLANG_MODULE_CACHE_PATH": str(temporary / "module-cache")}
            commands = [
                (["cargo", "build", "--release", "-p", "ime-ffi"], 60),
                (["swiftc", "-warnings-as-errors", "-I", str(ROOT / "crates/ime-ffi/include"),
                  str(temporary / "main.swift"),
                  str(ROOT / "platforms/macos/tests/LocalAcceptanceEvidence.swift"),
                  *[str(ROOT / ("modules/keymap/Sources" if name.startswith("Keyboard") or name.startswith("KeymapPanel") or name == "KeyRootLayout.swift" else "platforms/macos/Sources") / name) for name in
                    ["ImeSession.swift", "Config.swift", "CandidateWindow.swift", "CaretPlacement.swift",
                     "LearningHints.swift", "Practice.swift", "PracticeWindow.swift", "PracticeAnswerView.swift", "PracticeRootRowView.swift", "PracticeExplanationView.swift", *KEYMAP_SOURCES]],
                  str(ROOT / "target/release/libime_ffi.a"), "-framework", "AppKit",
                  "-o", str(temporary / "probe")], 180),
                ([str(temporary / "probe"), str(temporary), str(output)], 30),
            ]
            for command, timeout in commands:
                if command[0] == str(temporary / "probe"):
                    record_probe(temporary / "probe")
                result = subprocess.run(command, cwd=ROOT, env=environment,
                                        capture_output=True, text=True, timeout=timeout)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertNotIn("Unable to simultaneously satisfy constraints", result.stderr)
            self.assertIn("PASS wubi-learning", result.stdout)


if __name__ == "__main__":
    unittest.main()
