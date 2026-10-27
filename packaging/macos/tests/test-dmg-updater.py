#!/usr/bin/env python3
"""DMG ships the updater and the installer places it (ADR-295).

The DMG is only built at release time, so the packaging contract is asserted
statically: the DMG builder must refuse to run without an updater payload, the
release workflow must pass one, and the installer must look for the same bundle
identity and paths that the updater build produces (ADR-294/295).
"""
import os
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
UPDATER_ID = 'cn.jokerhub.Lampyris.WebsiteUpdateCheck'
UPDATER_NAME = 'LampyrisUpdateCheck.app'


def fake_app(path, identifier, version='0.0.1', build='1', executable='Lampyris'):
    contents = path / 'Contents'
    (contents / 'MacOS').mkdir(parents=True)
    binary = contents / 'MacOS' / executable
    binary.write_text('#!/bin/sh\nexit 0\n')
    binary.chmod(0o755)
    info = {'CFBundleIdentifier': identifier, 'CFBundleExecutable': executable,
            'CFBundleShortVersionString': version, 'CFBundleVersion': build,
            'CFBundlePackageType': 'APPL'}
    (contents / 'Info.plist').write_bytes(plistlib.dumps(info))


class DmgBuilderContract(unittest.TestCase):
    def run_builder(self, *args):
        return subprocess.run(['bash', str(ROOT / 'packaging/macos/make-dmg.sh'), *args],
                              capture_output=True, text=True, check=False, timeout=120)

    def test_updater_is_mandatory(self):
        with tempfile.TemporaryDirectory() as directory:
            work = pathlib.Path(directory)
            app, installer, uninstaller = work / 'Lampyris.app', work / '安装.app', work / '卸载.app'
            fake_app(app, 'cn.jokerhub.inputmethod.Lampyris')
            fake_app(installer, 'cn.jokerhub.Lampyris.Installer')
            fake_app(uninstaller, 'cn.jokerhub.Lampyris.Uninstaller')
            result = self.run_builder('--app', str(app), '--installer', str(installer),
                                      '--uninstaller', str(uninstaller), '--out', str(work / 'x.dmg'))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('更新程序', result.stderr)
            self.assertFalse((work / 'x.dmg').exists())

    def test_rejects_updater_with_foreign_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            work = pathlib.Path(directory)
            app, installer, uninstaller = work / 'Lampyris.app', work / '安装.app', work / '卸载.app'
            fake_app(app, 'cn.jokerhub.inputmethod.Lampyris')
            fake_app(installer, 'cn.jokerhub.Lampyris.Installer')
            fake_app(uninstaller, 'cn.jokerhub.Lampyris.Uninstaller')
            updater = work / UPDATER_NAME
            fake_app(updater, 'com.example.somethingElse')
            result = self.run_builder('--app', str(app), '--installer', str(installer),
                                      '--uninstaller', str(uninstaller),
                                      '--updater', str(updater), '--out', str(work / 'x.dmg'))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('标识不符', result.stderr)

    def test_builder_and_workflow_stage_the_updater(self):
        builder = (ROOT / 'packaging/macos/make-dmg.sh').read_text()
        self.assertIn('--updater)', builder)
        self.assertIn(f'ditto "$UPDATER" "$STAGE/{UPDATER_NAME}"', builder)
        self.assertIn(UPDATER_ID, builder)
        workflow = (ROOT / '.github/workflows/release.yml').read_text()
        self.assertIn('--updater platforms/macos/build/website-updater/LampyrisUpdateCheck.app', workflow)

    def test_installer_reads_the_updater_payload(self):
        installer = (ROOT / 'platforms/macos/Installer/Sources/LampyrisInstaller/main.swift').read_text()
        self.assertIn(f'"{UPDATER_ID}"', installer)
        self.assertIn(f'"{UPDATER_NAME}"', installer)
        self.assertIn('"Lampyris Update.app"', installer)
        self.assertIn('Contents/MacOS/LampyrisUpdateCheck', installer)
        # Payload must sit next to the installer in the DMG, like Lampyris.app.
        self.assertIn('bundleDirectory.appendingPathComponent(updaterBundleName)', installer)
        # Verification is delegated to the shared core, which owns the single check list (ADR-295).
        self.assertIn('import LampyrisInstallCore', installer)
        self.assertIn('DefaultInstallEnvironment.make(target: .updater)', installer)
        core = (ROOT / 'platforms/macos/InstallCore/Sources/LampyrisInstallCore/'
                'DefaultInstallEnvironment.swift').read_text()
        for check in ('stapler', 'spctl', 'Authority=Developer ID Application:', 'runtime'):
            self.assertIn(check, core)

    def test_dmg_readme_mentions_where_the_updater_lands(self):
        text = (ROOT / 'packaging/macos/make-dmg.sh').read_text()
        self.assertIn('~/Applications/LampyrisUpdateCheck.app', text)


class ZipAndReleasePayloadContract(unittest.TestCase):
    """ADR-295: the ZIP payload carries the updater too, and self-update consumes it."""

    def test_package_staging_requires_a_signed_updater(self):
        prepare = (ROOT / 'packaging/macos/prepare.sh').read_text()
        self.assertIn('LampyrisUpdateCheck.app', prepare)
        self.assertIn('签名候选缺少更新程序', prepare)
        self.assertIn('stapler validate "${UPDATER}"', prepare)
        self.assertIn('updater_build=', prepare)

    def test_acceptance_workflow_builds_and_notarizes_the_updater(self):
        workflow = (ROOT / '.github/workflows/macos-acceptance.yml').read_text()
        self.assertIn('python3 platforms/macos/Updater/build.py', workflow)
        # 与主应用共用同一次公证提交（ADR-295 去掉了「每轮多一次往返」的成本）。
        self.assertIn('ci-sign.sh --also platforms/macos/build/website-updater/LampyrisUpdateCheck.app',
                      workflow)
        self.assertNotIn('ci-sign.sh --app platforms/macos/build/website-updater', workflow)
        signer = (ROOT / 'packaging/macos/ci-sign.sh').read_text()
        self.assertIn('--also', signer)
        self.assertIn('notarytool submit "${WORK}/notarization.zip"', signer)
        for target in ('ditto "${APP}" "${NOTARIZE}', 'stapler staple "${notarized}"'):
            self.assertIn(target, signer)

    def test_cli_installer_installs_the_bundled_updater(self):
        text = (ROOT / 'platforms/macos/install.sh').read_text()
        self.assertIn('install_updater', text)
        self.assertIn('${SCRIPT_DIR}/../LampyrisUpdateCheck.app', text)
        self.assertIn(UPDATER_ID, text)
        self.assertIn('Lampyris Update.app', text)
        self.assertIn('install-backup-', text)

    def test_shared_core_tests_run_in_ci(self):
        makefile = (ROOT / 'Makefile').read_text()
        self.assertIn('macos-installcore-tests', makefile)
        self.assertIn('$(MAKE) macos-installcore-tests', makefile)
        self.assertIn('--package-path platforms/macos/InstallCore', makefile)
        for name in ('.github/workflows/ci.yml', '.github/workflows/macos-nightly.yml'):
            workflow = (ROOT / name).read_text()
            self.assertIn('macos-updater-tests', workflow, name)

    def test_updater_replaces_itself_from_the_payload(self):
        core = (ROOT / 'platforms/macos/InstallCore/Sources/LampyrisInstallCore/'
                'UpdateInstaller.swift').read_text()
        self.assertIn('installSelfUpdate', core)
        self.assertIn('public static let updater', core)
        self.assertIn('updaterBundle', core)
        window = (ROOT / 'platforms/macos/Updater/Sources/WebsiteUpdateCheck/UpdateWindow.swift').read_text()
        self.assertIn('SelfUpdate(', window)
        location = (ROOT / 'platforms/macos/Updater/Sources/WebsiteUpdateCheck/IsolatedUpdate.swift').read_text()
        self.assertIn('applications: nil', location)
        # 安装器与更新器共用同一实现（ADR-295 收敛）
        installer = (ROOT / 'platforms/macos/Installer/Sources/LampyrisInstaller/main.swift').read_text()
        self.assertIn('import LampyrisInstallCore', installer)
        self.assertIn('UpdateInstaller.replaceBundle', installer)
        self.assertNotIn('SecStaticCodeCreateWithPath', installer)


class ZipHelperContract(unittest.TestCase):
    def test_installer_readback_helper_ships_with_the_zip(self):
        prepare = (ROOT / 'packaging/macos/prepare.sh').read_text()
        self.assertIn('platforms/macos/tools/input-source-enabled.sh', prepare)
        self.assertIn('${STAGE}/scripts/tools/', prepare)

    def test_cli_installer_allows_backup_upgrade(self):
        text = (ROOT / 'platforms/macos/install.sh').read_text()
        self.assertNotIn('已有不同版本，请先切换输入源并卸载备份', text)
        self.assertIn('install-backup-', text)
        self.assertIn('已回滚', text)


class ShellUninstallRemovesUpdater(unittest.TestCase):
    """Shell uninstaller must clean the updater by bundle id, keeping the old name working."""

    def run_uninstall(self, home, *args):
        stub = home / 'bin'
        stub.mkdir(exist_ok=True)
        (stub / 'pgrep').write_text('#!/bin/sh\nexit 1\n')
        (stub / 'pgrep').chmod(0o755)
        (stub / 'pkill').write_text('#!/bin/sh\nexit 0\n')
        (stub / 'pkill').chmod(0o755)
        environment = {**os.environ, 'HOME': str(home), 'PATH': f'{stub}:{os.environ["PATH"]}'}
        return subprocess.run(['bash', str(ROOT / 'platforms/macos/uninstall.sh'), *args],
                              capture_output=True, text=True, check=False, env=environment)

    def fixture(self, work, updater_name):
        home = work / 'home'
        bundle = home / 'Library/Input Methods/Lampyris.app'
        fake_app(bundle, 'cn.jokerhub.inputmethod.Lampyris')
        updater = home / 'Applications' / updater_name
        fake_app(updater, UPDATER_ID, executable='LampyrisUpdateCheck')
        return home, bundle, updater

    def test_moves_official_and_legacy_updater_into_backup(self):
        for name in (UPDATER_NAME, 'Lampyris Update.app'):
            with tempfile.TemporaryDirectory() as directory:
                work = pathlib.Path(directory)
                home, bundle, updater = self.fixture(work, name)
                result = self.run_uninstall(home, '--input-source-removed')
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertFalse(bundle.exists())
                self.assertFalse(updater.exists(), name)
                backups = list((home / 'Library/Application Support/Lampyris/uninstalled').glob('bundle.*/*'))
                names = {path.name for path in backups}
                self.assertIn('Lampyris.app', names)
                self.assertIn(name, names)

    def test_ignores_other_apps_in_applications(self):
        with tempfile.TemporaryDirectory() as directory:
            work = pathlib.Path(directory)
            home, _, _ = self.fixture(work, UPDATER_NAME)
            unrelated = home / 'Applications' / 'Unrelated.app'
            fake_app(unrelated, 'com.example.unrelated')
            result = self.run_uninstall(home, '--input-source-removed')
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue(unrelated.exists())


if __name__ == '__main__':
    unittest.main()
