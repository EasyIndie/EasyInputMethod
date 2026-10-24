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
        self.assertIn('if not isolated:', text)

    def test_isolated_build_requires_all_three_flags(self):
        text = BUILD.read_text()
        for flag in ('--isolated-root', '--isolated-identity', '--test-build'):
            self.assertIn("'" + flag + "'", text)
        self.assertIn('parser.error(\'隔离构建必须同时给出 --isolated-root、--isolated-identity 与 --test-build\')', text)
        self.assertIn("parser.error('测试构建号必须是高于当前生产构建的正整数')", text)
        self.assertIn("parser.error('隔离根必须位于设备私有临时目录或 LampyrisIMKDev 开发根内')", text)
        self.assertIn("marker.read_text() != root.name", text)

    def test_runtime_requires_flag_identity_and_owned_root(self):
        text = LOCATION.read_text()
        self.assertIn('info["LampyrisTestOnly"] as? Bool == true else', text)
        self.assertIn('try InstallTarget.isolated(identity: identity)', text)
        self.assertIn('testBundlePrefix + uuid', text)
        self.assertIn('attributes[.type] as? FileAttributeType == .typeDirectory', text)
        self.assertIn('content == canonical.lastPathComponent', text)

    def test_headless_drill_entry_is_test_only(self):
        text = (ROOT / 'platforms/macos/Updater/Sources/WebsiteUpdateCheck/WebsiteUpdateCheck.swift').read_text()
        self.assertIn('--drill-run', text)
        self.assertIn('location.isolated else', text)
        self.assertIn('drill 只允许隔离测试构建运行；未发送请求。', text)
        self.assertIn('temp_after_cancel=', text)
        self.assertIn('temp_after_install=', text)
        self.assertIn('result=rejected', text)

    def test_window_never_falls_back_to_production_when_binding_is_invalid(self):
        text = WINDOW.read_text()
        self.assertIn('guard location != nil else', text)
        self.assertIn('guard let release, !running, let location else', text)
        self.assertIn('domain: location.domain, support: location.support', text)
        self.assertNotIn('homeDirectoryForCurrentUser', text)


if __name__ == '__main__':
    unittest.main()
