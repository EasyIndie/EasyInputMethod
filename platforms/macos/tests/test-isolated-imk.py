"""Validate owned build resources and distinct test bundle identity offline."""
import importlib.util
from pathlib import Path
import plistlib
import shutil
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("isolated", Path(__file__).with_name("isolated-imk.py"))
isolated = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(isolated)


class IsolatedIMKTests(unittest.TestCase):
    def setUp(self):
        self.root = isolated.create()
        self.addCleanup(lambda: shutil.rmtree(self.root) if self.root.exists() else None)

    def test_owner_private_and_unique(self):
        isolated.require_owned(self.root)
        second = isolated.create()
        self.addCleanup(shutil.rmtree, second)
        self.assertNotEqual(self.root, second)
        self.assertEqual((self.root / "owner").read_text(), self.root.name)
        self.assertEqual((self.root / "owner").stat().st_mode & 0o777, 0o600)

    def test_wrong_marker_and_public_permissions_rejected(self):
        marker = self.root / "owner"
        marker.write_text("wrong")
        with self.assertRaises(ValueError):
            isolated.require_owned(self.root)
        marker.write_text(self.root.name)
        marker.chmod(0o644)
        with self.assertRaises(ValueError):
            isolated.require_owned(self.root)

    def test_marker_symlink_and_root_symlink_rejected(self):
        marker = self.root / "owner"
        marker.rename(self.root / "original")
        marker.symlink_to(self.root / "original")
        with self.assertRaises(ValueError):
            isolated.require_owned(self.root)
        marker.unlink()
        (self.root / "original").rename(marker)
        alias = self.root / "alias"
        alias.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(ValueError):
            isolated.require_owned(alias)

    def test_invalid_namespace_and_mode_drift_rejected(self):
        identity = isolated.IDENTITY + self.root.name.removeprefix("lampyris-imk-")
        mode = {identity + ".default": {"TISInputSourceID": identity + ".default"}}
        info = {"CFBundleIdentifier": identity, "InputMethodConnectionName": identity + "_Connection",
                "tsInputModeListKey": mode, "ComponentInputModeDict": {"tsInputModeListKey": mode}}
        isolated.validate_identity(info, identity)
        with self.assertRaises(ValueError):
            isolated.validate_identity(info, identity.replace(".inputmethod.", "."))
        info["InputMethodConnectionName"] = "wrong"
        with self.assertRaises(ValueError):
            isolated.validate_identity(info, identity)
        info["InputMethodConnectionName"] = identity + "_Connection"
        info["ComponentInputModeDict"] = {"tsInputModeListKey": {}}
        with self.assertRaises(ValueError):
            isolated.validate_identity(info, identity)

    def test_bundle_rewrites_both_input_mode_lists(self):
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory)
            (repository / "platforms/macos/Resources").mkdir(parents=True)
            (repository / "data/generated").mkdir(parents=True)
            (repository / "assets/icons").mkdir(parents=True)
            old = "cn.jokerhub.inputmethod.Lampyris"
            modes = {old + ".default": {"TISInputSourceID": old + ".default"}}
            info = {"CFBundleIdentifier": old, "tsInputModeListKey": modes,
                    "tsInputMethodIconFileKey": "LampyrisTemplate.png",
                    "ComponentInputModeDict": {"tsInputModeListKey": modes}}
            (repository / "Cargo.toml").write_text('[workspace.package]\nversion = "2.3.4-rc.2+fixture"\n')
            (repository / "packaging").mkdir()
            (repository / "packaging/build-number").write_text("42\n")
            (repository / "platforms/macos/Info.plist").write_bytes(plistlib.dumps(info))
            for name in ("wubi86-core.tsv", "pinyin-chars.tsv", "pinyin-core.tsv", "variant-s2t.tsv"):
                (repository / "data/generated" / name).write_bytes(b"fixture")
            (repository / "assets/icons/yinghuo-official-app.icns").write_bytes(b"fixture")
            with patch.object(isolated, "ROOT", repository):
                app = isolated.bundle(self.root)
            actual = plistlib.loads((app / "Contents/Info.plist").read_bytes())
            self.assertEqual(actual["CFBundleShortVersionString"], "2.3.4")
            self.assertEqual(actual["CFBundleVersion"], "42")
            self.assertEqual(actual["LampyrisSemanticVersion"], "2.3.4-rc.2+fixture")
            identity = actual["CFBundleIdentifier"]
            self.assertTrue(identity.startswith(isolated.IDENTITY))
            self.assertIn(".inputmethod.", identity)
            self.assertNotEqual(identity, old)
            self.assertNotIn(old + ".default", actual["tsInputModeListKey"])
            self.assertNotIn(old + ".default", actual["ComponentInputModeDict"]["tsInputModeListKey"])
            self.assertIn(identity + ".default", actual["tsInputModeListKey"])
            self.assertIn(identity + ".default", actual["ComponentInputModeDict"]["tsInputModeListKey"])
            self.assertEqual(actual["InputMethodConnectionName"], identity + "_Connection")
            self.assertEqual(actual["CFBundleDisplayName"], "萤火虫 开发版")
            self.assertEqual(actual["tsInputMethodIconFileKey"], "LampyrisDevTemplate.png")
            for language, label in (("en", "Lampyris Dev"), ("zh-Hans", "萤火虫 开发版")):
                names = (app / "Contents/Resources" / (language + ".lproj") / "InfoPlist.strings").read_text()
                self.assertIn('"' + identity + '.default" = "' + label + '";', names)
                self.assertNotIn(old + '.default', names)
            self.assertFalse((app / "Contents/Resources/wubi86-core.tsv").is_symlink())
            binding = app / "Contents/Resources/IMKTestRoot"
            self.assertEqual(binding.read_text(), str(self.root.resolve()))
            self.assertEqual(binding.stat().st_mode & 0o777, 0o600)

    def test_build_arches_requests(self):
        self.assertEqual(isolated.build_arches("universal"), ["arm64", "x86_64"])
        for arch in ("arm64", "x86_64"):
            self.assertEqual(isolated.build_arches(arch), [arch])
        for value in ("native", ""):
            self.assertEqual(isolated.build_arches(value), [isolated.host_arch()])
        for value in ("armv7", "i386", "Universal", "universal ", "../x86_64"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                isolated.build_arches(value)


if __name__ == "__main__":
    unittest.main()
