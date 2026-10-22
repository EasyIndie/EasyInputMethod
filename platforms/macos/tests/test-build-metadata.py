"""Test SDK identity derivation, CLT fallback, and early target rejection."""
import importlib.util
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))
spec = importlib.util.spec_from_file_location("metadata", ROOT / "tools/macos-build-metadata.py")
metadata = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metadata)


class BuildMetadataTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.sdk = self.root / "sdk"
        system = self.sdk / "System/Library/CoreServices"
        system.mkdir(parents=True)
        (self.sdk / "SDKSettings.plist").write_bytes(plistlib.dumps({"Version": "14.4", "CanonicalName": "macosx14.4"}))
        (system / "SystemVersion.plist").write_bytes(plistlib.dumps({"ProductBuildVersion": "fixture-sdk"}))

    def test_version_comes_from_workspace_and_independent_build(self):
        from release_version import identity
        (self.root / "packaging").mkdir()
        (self.root / "Cargo.toml").write_text('[workspace.package]\nversion = "2.3.4-rc.2+fixture"\n')
        (self.root / "packaging/build-number").write_text("42\n")
        self.assertEqual(identity(self.root), {"version": "2.3.4-rc.2+fixture", "apple": "2.3.4", "build": "42"})
        for version in ("01.2.3", "1.2", "1.2.3-01", "1.2.3-"):
            (self.root / "Cargo.toml").write_text(f'[workspace.package]\nversion = "{version}"\n')
            with self.assertRaises(ValueError):
                identity(self.root)
        (self.root / "Cargo.toml").write_text('[workspace.package]\nversion = "2.3.4"\n')
        for build in ("0", "01", "1.2.3", "10000", "-1"):
            (self.root / "packaging/build-number").write_text(build)
            with self.assertRaises(ValueError):
                identity(self.root)

    def test_sdk_is_actual_and_clt_does_not_invent_xcode(self):
        result = metadata.metadata(self.sdk, self.root / "CommandLineTools", "fixture-host")
        self.assertEqual(result["DTSDKName"], "macosx14.4")
        self.assertEqual(result["DTSDKBuild"], "fixture-sdk")
        self.assertEqual(result["BuildMachineOSBuild"], "fixture-host")
        self.assertNotIn("DTXcode", result)

    def test_actual_xcode_version(self):
        contents = self.root / "Xcode.app/Contents"
        contents.mkdir(parents=True)
        (contents / "version.plist").write_bytes(plistlib.dumps({"CFBundleShortVersionString": "15.3", "ProductBuildVersion": "fixture-xcode"}))
        result = metadata.metadata(self.sdk, contents / "Developer", "fixture-host")
        self.assertEqual(result["DTXcode"], "1530")
        self.assertEqual(result["DTXcodeBuild"], "fixture-xcode")

    def test_contract_removes_old_machine_data_but_keeps_product_identity(self):
        original = {"DTXcode": "2700", "CFBundleVersion": "0.1.0", "InputMethodConnectionName": "owned"}
        self.assertEqual(metadata.contract(original), {"CFBundleVersion": "0.1.0", "InputMethodConnectionName": "owned"})

    def test_missing_intel_target_stops_before_build_or_cleanup(self):
        platform = self.root / "platforms/macos"
        platform.mkdir(parents=True)
        script = platform / "build.sh"
        shutil.copy(ROOT / "platforms/macos/build.sh", script)
        marker = platform / "build/tmp/existing"
        marker.parent.mkdir(parents=True)
        marker.write_bytes(b"previous build")
        commands = self.root / "commands"
        commands.mkdir()
        rustup = commands / "rustup"
        rustup.write_text('#!/bin/bash\nprintf "aarch64-apple-darwin\\n"\n')
        rustup.chmod(0o700)
        calls = self.root / "calls"
        for name in ("cargo", "swiftc", "rm"):
            command = commands / name
            command.write_text('#!/bin/bash\nprintf "%s\\n" "$0" >> "$BUILD_CALLS"\nexit 99\n')
            command.chmod(0o700)
        env = dict(os.environ, PATH=str(commands) + ":" + os.environ["PATH"], BUILD_CALLS=str(calls))
        result = subprocess.run(["/bin/bash", str(script), "--universal"], env=env,
                                capture_output=True, text=True, check=False, timeout=5)
        self.assertEqual(result.returncode, 1)
        self.assertIn("rustup target add x86_64-apple-darwin", result.stderr)
        self.assertFalse(calls.exists())
        self.assertEqual(marker.read_bytes(), b"previous build")


if __name__ == "__main__":
    unittest.main()
