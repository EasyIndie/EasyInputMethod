"""Verify the blocked panel entry executes no external test actions."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class PanelGateTests(unittest.TestCase):
    def test_entry_blocks_before_any_external_command(self):
        script = Path(__file__).with_name("run-panel-acceptance.sh").resolve()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            log = root / "calls"
            sentinel = root / "lampyris-panel-export.tsv"
            sentinel.write_bytes(b"existing user export\x00")
            trap = '#!/bin/bash\nprintf "%s\\n" "$0" >> "$PANEL_GATE_LOG"\nexit 99\n'
            for name in ("dirname", "mktemp", "osascript", "swiftc", "cp", "rm", "pbcopy"):
                executable = root / name
                executable.write_text(trap)
                executable.chmod(0o700)
            env = dict(os.environ, PATH=str(root), PANEL_GATE_LOG=str(log))
            for args in ([], ["--force"], ["--isolated"]):
                result = subprocess.run(
                    ["/bin/bash", str(script), *args], env=env, cwd=root,
                    capture_output=True, text=True, timeout=5, check=False,
                )
                self.assertEqual(result.returncode, 3)
                self.assertIn("BLOCKED", result.stderr)
                self.assertEqual(result.stdout, "")
                self.assertFalse(log.exists())
                self.assertEqual(sentinel.read_bytes(), b"existing user export\x00")


if __name__ == "__main__":
    unittest.main()
