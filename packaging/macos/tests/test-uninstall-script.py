#!/usr/bin/env python3
"""Offline regression for platforms/macos/uninstall.sh using a fake HOME (报告192).

Covers: dry-run makes no changes, real removal moves the bundle into uninstalled/bundle.*,
--purge-data moves config/dictionary aside, refusals for symlinks and wrong identifiers,
and the no-op path when nothing is installed. Nothing here touches the real install.
"""
import os
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "platforms/macos/uninstall.sh"
IDENTIFIER = "cn.jokerhub.inputmethod.Lampyris"


class UninstallScriptTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        self.domain = self.home / "Library/Input Methods"
        self.support = self.home / "Library/Application Support/Lampyris"
        self.backup = self.support / "uninstalled"
        self.domain.mkdir(parents=True)
        self.support.mkdir(parents=True)
        self.app = self.domain / "Lampyris.app"
        self.make_app(self.app, IDENTIFIER)
        # 本机可能正跑着真实宿主；给测试一个"没有宿主"的 PATH，保持用例独立于桌面状态。
        self.shim = self.home / "bin"
        self.shim.mkdir()
        pgrep = self.shim / "pgrep"
        pgrep.write_text("#!/bin/sh\nexit 1\n")
        pgrep.chmod(0o755)

    def tearDown(self):
        self.tmp.cleanup()

    def make_app(self, path, identifier):
        contents = path / "Contents"
        contents.mkdir(parents=True)
        (contents / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": identifier}))

    def run_script(self, *args):
        env = dict(os.environ, HOME=str(self.home), PATH=f"{self.shim}:{os.environ['PATH']}")
        return subprocess.run(["bash", str(SCRIPT), *args], capture_output=True, text=True, env=env)

    def test_dry_run_reports_plan_without_changes(self):
        (self.support / "config.toml").write_text("mode = \"mixed\"\n")
        result = self.run_script("--dry-run", "--purge-data")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("bundle.XXXXXX", result.stdout)
        self.assertIn("data.XXXXXX", result.stdout)
        self.assertTrue(self.app.is_dir())
        self.assertTrue((self.support / "config.toml").exists())

    def test_removal_keeps_user_data(self):
        (self.support / "config.toml").write_text("mode = \"mixed\"\n")
        dictionary = self.support / "user-dictionary.tsv"
        dictionary.write_text("wubi\tyysg\t文本\t1\n")
        result = self.run_script("--input-source-removed")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.app.exists())
        self.assertTrue(dictionary.exists())
        moved = list(self.backup.glob("bundle.*/Lampyris.app"))
        self.assertEqual(len(moved), 1)
        self.assertIn("配置与词库保留", result.stdout)

    def test_purge_moves_user_data_aside(self):
        config = self.support / "config.toml"
        config.write_text("mode = \"mixed\"\n")
        dictionary = self.support / "user-dictionary.tsv"
        dictionary.write_text("wubi\tyysg\t文本\t1\n")
        result = self.run_script("--input-source-removed", "--purge-data")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(config.exists())
        self.assertFalse(dictionary.exists())
        self.assertEqual(len(list(self.backup.glob("data.*/config.toml"))), 1)
        self.assertEqual(len(list(self.backup.glob("data.*/user-dictionary.tsv"))), 1)

    def test_wrong_identifier_is_refused(self):
        self.app.rename(self.domain / "Other.app")
        self.make_app(self.domain / "Lampyris.app", "com.example.other")
        result = self.run_script("--input-source-removed")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("标识不符", result.stderr)
        self.assertTrue((self.domain / "Lampyris.app").exists())

    def test_symlinked_bundle_is_refused(self):
        real = self.home / "elsewhere.app"
        self.app.rename(real)
        self.app.symlink_to(real)
        result = self.run_script("--input-source-removed")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("符号链接", result.stderr)

    def test_absent_app_is_noop(self):
        import shutil

        shutil.rmtree(self.app)
        result = self.run_script("--input-source-removed")
        self.assertEqual(result.returncode, 0)
        self.assertIn("没有萤火虫", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
