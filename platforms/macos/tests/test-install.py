#!/usr/bin/env python3
"""Reject bundles whose extraction lost executable permissions; uninstall keeps or purges user data."""
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[3]


class InstallerPermissions(unittest.TestCase):
    def reject(self, app):
        result = subprocess.run(
            [str(ROOT / 'platforms/macos/install.sh'), '--app', str(app), '--dry-run'],
            capture_output=True, text=True, check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('执行权限', result.stderr)

    def test_zip_extraction_losing_permissions(self):
        with tempfile.TemporaryDirectory() as directory:
            work = pathlib.Path(directory)
            archive = work / 'candidate.zip'
            with zipfile.ZipFile(archive, 'w') as package:
                entry = zipfile.ZipInfo('Lampyris.app/Contents/MacOS/Lampyris')
                entry.create_system = 3
                entry.external_attr = 0o100755 << 16
                package.writestr(entry, '#!/bin/sh\nexit 0\n')
                package.write(ROOT / 'platforms/macos/Info.plist', 'Lampyris.app/Contents/Info.plist')
            with zipfile.ZipFile(archive) as package:
                package.extractall(work)
            self.reject(work / 'Lampyris.app')

    def test_executable_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            app = pathlib.Path(directory) / 'Lampyris.app'
            executable = app / 'Contents/MacOS/Lampyris'
            executable.parent.mkdir(parents=True)
            shutil.copy(ROOT / 'platforms/macos/Info.plist', app / 'Contents/Info.plist')
            executable.symlink_to('/bin/sh')
            self.reject(app)


class UninstallerFreshStart(unittest.TestCase):
    """`--purge-data` 把配置与词库移出活动目录，让下一次安装从 Schema 默认值开始。"""

    def fixture(self, work):
        home = work / 'home'
        bundle = home / 'Library/Input Methods/Lampyris.app'
        (bundle / 'Contents/MacOS').mkdir(parents=True)
        shutil.copy(ROOT / 'platforms/macos/Info.plist', bundle / 'Contents/Info.plist')
        (bundle / 'Contents/MacOS/Lampyris').write_text('#!/bin/sh\nexit 0\n')
        support = home / 'Library/Application Support/Lampyris'
        support.mkdir(parents=True)
        (support / 'config.toml').write_text('mode = "wubi"\n')
        (support / 'user-dictionary.tsv').write_text('# lampyris-user-dictionary v1\n')
        # 宿主检查用桩，避免测试依赖当前登录是否开着输入法。
        stub = work / 'bin'
        stub.mkdir()
        (stub / 'pgrep').write_text('#!/bin/sh\nexit 1\n')
        (stub / 'pgrep').chmod(0o755)
        return home, bundle, support, stub

    def run_uninstall(self, home, stub, *args):
        environment = {**os.environ, 'HOME': str(home), 'PATH': f'{stub}:{os.environ["PATH"]}'}
        return subprocess.run([str(ROOT / 'platforms/macos/uninstall.sh'), *args],
                              capture_output=True, text=True, check=False, env=environment)

    def test_dry_run_previews_purge_without_touching_files(self):
        with tempfile.TemporaryDirectory() as directory:
            work = pathlib.Path(directory)
            home, bundle, support, stub = self.fixture(work)
            result = self.run_uninstall(home, stub, '--dry-run', '--purge-data')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('config.toml', result.stdout)
            self.assertIn('默认值', result.stdout)
            self.assertTrue(bundle.exists())
            self.assertTrue((support / 'config.toml').exists())
            self.assertTrue((support / 'user-dictionary.tsv').exists())

    def test_default_keeps_user_data(self):
        with tempfile.TemporaryDirectory() as directory:
            work = pathlib.Path(directory)
            home, bundle, support, stub = self.fixture(work)
            result = self.run_uninstall(home, stub, '--input-source-removed')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(bundle.exists())
            self.assertTrue((support / 'config.toml').exists())
            self.assertTrue((support / 'user-dictionary.tsv').exists())

    def add_helper(self, bundle, exit_code=0):
        helper = bundle / 'Contents/Helpers/LampyrisTIS'
        helper.parent.mkdir(parents=True)
        helper.write_text('#!/bin/sh\nexit %d\n' % exit_code)
        helper.chmod(0o755)

    def test_uninstall_disables_source_via_helper_without_flag(self):
        with tempfile.TemporaryDirectory() as directory:
            work = pathlib.Path(directory)
            home, bundle, support, stub = self.fixture(work)
            self.add_helper(bundle)
            result = self.run_uninstall(home, stub)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(bundle.exists())
            self.assertTrue((support / 'config.toml').exists())

    def test_uninstall_still_requires_flag_when_helper_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            work = pathlib.Path(directory)
            home, bundle, support, stub = self.fixture(work)
            self.add_helper(bundle, exit_code=1)
            result = self.run_uninstall(home, stub)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('先移除输入源', result.stderr)
            self.assertTrue(bundle.exists())

    def test_purge_moves_bundle_and_data_aside(self):
        with tempfile.TemporaryDirectory() as directory:
            work = pathlib.Path(directory)
            home, bundle, support, stub = self.fixture(work)
            result = self.run_uninstall(home, stub, '--input-source-removed', '--purge-data')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(bundle.exists())
            self.assertFalse((support / 'config.toml').exists())
            self.assertFalse((support / 'user-dictionary.tsv').exists())
            backups = sorted((support / 'uninstalled').iterdir())
            self.assertTrue(any(path.name.startswith('bundle.') for path in backups))
            data = [path for path in backups if path.name.startswith('data.')]
            self.assertEqual(len(data), 1)
            self.assertTrue((data[0] / 'config.toml').exists())
            self.assertTrue((data[0] / 'user-dictionary.tsv').exists())


if __name__ == '__main__':
    unittest.main()
