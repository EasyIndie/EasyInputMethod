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


class InputSourceReadback(unittest.TestCase):
    """`enable` 返回 0 不代表源真的启用（macOS 13，报告201/207），安装脚本必须回读。"""

    def run_check(self, helper_text):
        with tempfile.TemporaryDirectory() as directory:
            helper = pathlib.Path(directory) / 'LampyrisTIS'
            helper.write_text(helper_text)
            helper.chmod(0o755)
            return subprocess.run(
                [str(ROOT / 'platforms/macos/tools/input-source-enabled.sh'),
                 str(helper), 'cn.jokerhub.inputmethod.Lampyris'],
                capture_output=True, text=True, check=False)

    def test_reports_enabled_when_listed(self):
        result = self.run_check(
            '#!/bin/sh\necho "enabled cn.jokerhub.inputmethod.Lampyris,'
            'cn.jokerhub.inputmethod.Lampyris.default"\n')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_reports_missing_when_list_is_empty(self):
        result = self.run_check('#!/bin/sh\necho "enabled "\n')
        self.assertEqual(result.returncode, 1)

    def test_requires_exact_identifier(self):
        # 只有模式源、没有父源时不算注册成功。
        result = self.run_check(
            '#!/bin/sh\necho "enabled cn.jokerhub.inputmethod.Lampyris.default"\n')
        self.assertEqual(result.returncode, 1)

    def test_fails_when_helper_prints_nothing(self):
        result = self.run_check('#!/bin/sh\nexit 1\n')
        self.assertEqual(result.returncode, 1)


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



class InstallerBranches(unittest.TestCase):
    """报告263 的三条安装器分支：自动重启旧宿主、打开键盘设置、同版本强制覆盖。

    全部在临时 HOME 里跑，系统命令（codesign/xcrun/spctl/pgrep/open）换成记录调用的桩，
    不碰真实的输入法目录、宿主进程或系统设置。"""

    STUB = """#!/bin/sh
echo "$(basename "$0") $*" >> "$STUB_LOG"
case "$(basename "$0")" in
  codesign) case "$*" in *-dv*) echo "Authority=Developer ID Application: Test (TEST)" >&2; echo "flags=0x10000(runtime)" >&2;; esac ;;
  pgrep)
    case "$*" in
      *install-backup-*) [ -n "${FAKE_STALE_PID:-}" ] && echo "$FAKE_STALE_PID" ;;
      "-x Lampyris") [ -n "${FAKE_HOST_RUNNING:-}" ] && echo 424242 ;;
    esac
    [ -n "${FAKE_STALE_PID:-}" ] && case "$*" in *install-backup-*) exit 0;; esac
    [ -n "${FAKE_HOST_RUNNING:-}" ] && [ "$*" = "-x Lampyris" ] && exit 0
    exit 1 ;;
esac
exit 0
"""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.work = pathlib.Path(self.tmp.name)
        self.home = self.work / 'home'
        self.home.mkdir()
        self.bin = self.work / 'bin'
        self.bin.mkdir()
        self.log = self.work / 'calls.log'
        for name in ('codesign', 'xcrun', 'spctl', 'pgrep', 'open'):
            path = self.bin / name
            path.write_text(self.STUB)
            path.chmod(0o755)
        self.app = self.make_app(self.work / 'pkg', helper_lists_source=True)

    def tearDown(self):
        self.tmp.cleanup()

    def make_app(self, folder, helper_lists_source):
        app = folder / 'Lampyris.app'
        (app / 'Contents/MacOS').mkdir(parents=True)
        shutil.copy(ROOT / 'platforms/macos/Info.plist', app / 'Contents/Info.plist')
        executable = app / 'Contents/MacOS/Lampyris'
        executable.write_text('#!/bin/sh\nexit 0\n')
        executable.chmod(0o755)
        helper = app / 'Contents/Helpers/LampyrisTIS'
        helper.parent.mkdir(parents=True)
        listed = 'cn.jokerhub.inputmethod.Lampyris,cn.jokerhub.inputmethod.Lampyris.default' if helper_lists_source else ''
        helper.write_text(f'#!/bin/sh\n[ "$1" = status ] && echo "enabled {listed}"\nexit 0\n')
        helper.chmod(0o755)
        return app

    def install(self, app=None, **env):
        environment = {
            'PATH': f'{self.bin}:/usr/bin:/bin:/usr/sbin:/sbin', 'HOME': str(self.home),
            'STUB_LOG': str(self.log), **env,
        }
        result = subprocess.run(
            [str(ROOT / 'platforms/macos/install.sh'), '--app', str(app or self.app)],
            capture_output=True, text=True, check=False, env=environment, stdin=subprocess.DEVNULL)
        installed = self.home / 'Library/Input Methods/Lampyris.app'
        self.assertTrue(str(installed).startswith(self.tmp.name), '安装目标必须在临时 HOME 里')
        return result

    def calls(self):
        return self.log.read_text() if self.log.exists() else ''

    def backups(self):
        root = self.home / 'Library/Application Support/Lampyris/updates'
        return sorted(p.name for p in root.glob('install-backup-*')) if root.exists() else []

    def test_same_version_is_skipped_unless_forced(self):
        first = self.install()
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertIn('已注册到输入源', first.stdout)
        again = self.install()
        self.assertEqual(again.returncode, 0, again.stderr)
        self.assertIn('已安装相同版本', again.stdout)
        self.assertEqual(self.backups(), [])
        forced = self.install(LAMPYRIS_FORCE_INSTALL='1')
        self.assertEqual(forced.returncode, 0, forced.stderr)
        self.assertIn('旧版本已备份', forced.stdout)
        self.assertEqual(len(self.backups()), 1)

    def test_running_host_blocks_overwrite(self):
        self.assertEqual(self.install().returncode, 0)
        blocked = self.install(LAMPYRIS_FORCE_INSTALL='1', FAKE_HOST_RUNNING='1')
        self.assertNotEqual(blocked.returncode, 0)
        self.assertIn('宿主仍在运行', blocked.stderr)

    def test_stale_host_restart_only_when_asked(self):
        quiet = self.install(FAKE_STALE_PID='999999')
        self.assertEqual(quiet.returncode, 0, quiet.stderr)
        self.assertIn('LAMPYRIS_RESTART_HOST=1', quiet.stderr)
        self.assertNotIn('已重启宿主', quiet.stdout)
        self.assertNotIn('open ' + str(self.home), self.calls())
        restarted = self.install(LAMPYRIS_FORCE_INSTALL='1', FAKE_STALE_PID='999999', LAMPYRIS_RESTART_HOST='1')
        self.assertEqual(restarted.returncode, 0, restarted.stderr)
        self.assertIn('已重启宿主（新包）', restarted.stdout)
        self.assertIn('open ' + str(self.home / 'Library/Input Methods/Lampyris.app'), self.calls())

    def test_keyboard_settings_open_only_when_asked(self):
        app = self.make_app(self.work / 'unlisted', helper_lists_source=False)
        quiet = self.install(app=app)
        self.assertEqual(quiet.returncode, 0, quiet.stderr)
        self.assertIn('系统没有接受自动注册', quiet.stderr)
        self.assertNotIn('x-apple.systempreferences', self.calls())
        opened = self.install(app=app, LAMPYRIS_FORCE_INSTALL='1', LAMPYRIS_OPEN_SETTINGS='1')
        self.assertEqual(opened.returncode, 0, opened.stderr)
        self.assertIn('x-apple.systempreferences:com.apple.Keyboard-Settings.extension', self.calls())

if __name__ == '__main__':
    unittest.main()
