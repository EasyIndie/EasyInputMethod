"""A production updater must never carry an isolated install binding (ADR-287)."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
BUILD = ROOT / 'platforms/macos/Updater/build.py'
LOCATION = ROOT / 'platforms/macos/Updater/Sources/WebsiteUpdateCheck/IsolatedUpdate.swift'
WINDOW = ROOT / 'platforms/macos/Updater/Sources/WebsiteUpdateCheck/UpdateWindow.swift'


class UpdaterIsolationTests(unittest.TestCase):
    def test_production_build_refuses_isolated_keys(self):
        text = BUILD.read_text()
        for key in ('LampyrisTestOnly', 'LampyrisIsolatedRoot', 'LampyrisIsolatedIdentity'):
            self.assertIn(key, text)
        self.assertIn("parser.error('生产更新程序不得包含隔离绑定：' + forbidden)", text)

    def test_runtime_requires_flag_identity_and_owned_root(self):
        text = LOCATION.read_text()
        self.assertIn('info["LampyrisTestOnly"] as? Bool == true else', text)
        self.assertIn('try InstallTarget.isolated(identity: identity)', text)
        self.assertIn('testBundlePrefix + uuid', text)
        self.assertIn('attributes[.type] as? FileAttributeType == .typeDirectory', text)
        self.assertIn('content == canonical.lastPathComponent', text)

    def test_window_never_falls_back_to_production_when_binding_is_invalid(self):
        text = WINDOW.read_text()
        self.assertIn('guard location != nil else', text)
        self.assertIn('guard let release, !running, let location else', text)
        self.assertIn('domain: location.domain, support: location.support', text)
        self.assertNotIn('homeDirectoryForCurrentUser', text)


if __name__ == '__main__':
    unittest.main()
