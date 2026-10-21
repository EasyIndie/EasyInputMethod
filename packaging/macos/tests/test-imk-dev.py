import importlib.util
import json
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('dev', ROOT / 'scripts/macos-imk-dev.py')
dev = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dev)


class DevelopmentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.home = Path(self.temp.name).resolve()
        (self.home / 'Library/Application Support').mkdir(parents=True)
        (self.home / 'Library/Input Methods').mkdir()
        self.root = dev.owned_root(self.home, True)
        self.identity = dev.IDENTITY + self.root.name.removeprefix('lampyris-imk-')

    def tearDown(self):
        self.temp.cleanup()

    def test_identity_persists_and_real_data_is_not_created(self):
        self.assertEqual(dev.owned_root(self.home, True), self.root)
        self.assertFalse((self.home / 'Library/Application Support/Lampyris').exists())
        self.assertEqual(self.root.stat().st_mode & 0o777, 0o700)
        (self.root / 'owner').write_text('wrong')
        with self.assertRaises(ValueError):
            dev.owned_root(self.home)

    def test_symlinks_and_wide_permissions_refused(self):
        marker = self.root / 'owner'
        marker.chmod(0o644)
        with self.assertRaises(ValueError):
            dev.owned_root(self.home)
        marker.chmod(0o600)
        data = self.root / 'config.toml'
        data.symlink_to(marker)
        with self.assertRaises(ValueError):
            dev.owned_root(self.home)

    def test_multiple_roots_refused(self):
        (self.root.parent / 'lampyris-imk-another').mkdir()
        with self.assertRaises(ValueError):
            dev.owned_root(self.home, True)

    def test_install_preserves_data_and_old_package_without_source_mutation(self):
        source = self.home / 'candidate.app'
        target = self.home / ('Library/Input Methods/LampyrisIMKTest-' + self.root.name.removeprefix('lampyris-imk-') + '.app')
        for app, content in [(source, b'new'), (target, b'old')]:
            (app / 'Contents/MacOS').mkdir(parents=True)
            (app / 'Contents/MacOS/LampyrisIMKTest').write_bytes(content)
        data = self.root / 'user-dictionary.tsv'
        data.write_bytes(b'preserved')
        data.chmod(0o600)
        info = {'CFBundleIdentifier': self.identity}
        state = {'current': 'ABC', 'enabled': ['ABC', self.identity + '.default']}
        def copy(*args):
            import shutil
            self.assertEqual(args[:2], ('/usr/bin/ditto', source))
            shutil.copytree(args[1], args[2])
        with patch.object(dev, 'verify_app', return_value=info), patch.object(dev, 'state', return_value=state), patch.object(dev, 'idle'), patch.object(dev, 'run', side_effect=copy):
            dev.install(source, self.root, self.home, 'helper')
        evidence = json.loads(next(self.root.glob('replacement-*/installation.json')).read_text())
        self.assertTrue(evidence['source_state_unchanged'])
        self.assertEqual(Path(evidence['backup']).joinpath('Contents/MacOS/LampyrisIMKTest').read_bytes(), b'old')
        self.assertEqual((target / 'Contents/MacOS/LampyrisIMKTest').read_bytes(), b'new')
        self.assertEqual(data.read_bytes(), b'preserved')
        self.assertFalse(evidence['native_input_verified'])

    def test_failed_final_verification_restores_previous_package(self):
        source = self.home / 'candidate.app'
        target = self.home / ('Library/Input Methods/LampyrisIMKTest-' + self.root.name.removeprefix('lampyris-imk-') + '.app')
        for app, content in [(source, b'new'), (target, b'old')]:
            (app / 'Contents/MacOS').mkdir(parents=True)
            (app / 'Contents/MacOS/LampyrisIMKTest').write_bytes(content)
        info = {'CFBundleIdentifier': self.identity}
        calls = []
        def verify(app, root):
            calls.append(app)
            if len(calls) == 4:
                raise ValueError('injected final verification failure')
            return info
        def copy(*args):
            import shutil
            shutil.copytree(args[1], args[2])
        with patch.object(dev, 'verify_app', side_effect=verify), patch.object(dev, 'state', return_value={'current': 'ABC', 'enabled': ['ABC']}), patch.object(dev, 'idle'), patch.object(dev, 'run', side_effect=copy):
            with self.assertRaises(ValueError):
                dev.install(source, self.root, self.home, 'helper')
        self.assertEqual((target / 'Contents/MacOS/LampyrisIMKTest').read_bytes(), b'old')
        self.assertEqual(next(self.root.glob('replacement-*/rejected.app/Contents/MacOS/LampyrisIMKTest')).read_bytes(), b'new')

    def test_registration_declaration_changes_refused_before_stop(self):
        target = self.home / ('Library/Input Methods/LampyrisIMKTest-' + self.root.name.removeprefix('lampyris-imk-') + '.app')
        target.mkdir()
        with patch.object(dev, 'verify_app', side_effect=[{'CFBundleIdentifier': self.identity, 'CFBundleName': 'new'}, {'CFBundleIdentifier': self.identity, 'CFBundleName': 'old'}]), patch.object(dev, 'state', return_value={'current': 'ABC', 'enabled': ['ABC']}), patch.object(dev, 'idle') as idle:
            with self.assertRaises(ValueError):
                dev.install(self.home / 'candidate.app', self.root, self.home, 'helper', True)
            idle.assert_not_called()

    def test_concurrent_installer_is_rejected_before_mutation(self):
        with (self.root / 'owner').open() as marker:
            dev.fcntl.flock(marker, dev.fcntl.LOCK_EX | dev.fcntl.LOCK_NB)
            with patch.object(dev, 'replace_package') as replace:
                with self.assertRaises(BlockingIOError):
                    dev.install(self.home / 'candidate.app', self.root, self.home, 'helper')
                replace.assert_not_called()

    def test_current_development_source_blocks_before_copy_or_stop(self):
        with patch.object(dev, 'verify_app', return_value={'CFBundleIdentifier': self.identity}), patch.object(dev, 'state', return_value={'current': self.identity + '.default', 'enabled': []}), patch.object(dev, 'run') as run, patch.object(dev, 'idle') as idle:
            with self.assertRaises(ValueError):
                dev.install(self.home / 'candidate.app', self.root, self.home, 'helper', True)
            run.assert_not_called()
            idle.assert_not_called()

    def test_wrong_process_path_is_never_signalled(self):
        with patch.object(dev, 'holders', return_value=[123]), patch.object(dev, 'run', return_value='/other/LampyrisIMKTest'), patch.object(dev.os, 'kill') as kill:
            with self.assertRaises(ValueError):
                dev.idle(self.home / 'target.app', True)
            kill.assert_not_called()


if __name__ == '__main__':
    unittest.main()
