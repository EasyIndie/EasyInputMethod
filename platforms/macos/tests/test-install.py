#!/usr/bin/env python3
"""Reject bundles whose extraction lost executable permissions."""
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


if __name__ == '__main__':
    unittest.main()
