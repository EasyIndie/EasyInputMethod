"""Shared install core semantics (ADR-295): replace / backup / rollback / self-update.

Compiles the core module and a headless probe with swiftc so the contract that the
DMG installer, the updater and the CLI all rely on stays verifiable offline.
"""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from local_acceptance_support import record_probe

ROOT = Path(__file__).resolve().parents[3]
CORE = ROOT / 'platforms/macos/InstallCore/Sources/LampyrisInstallCore'


@unittest.skipUnless(sys.platform == 'darwin', 'requires swiftc')
class InstallCoreTests(unittest.TestCase):
    def test_replace_backup_rollback_and_self_update(self):
        with tempfile.TemporaryDirectory(prefix='lampyris-install-core-') as folder:
            work = Path(folder)
            environment = {**os.environ, 'CLANG_MODULE_CACHE_PATH': str(work / 'module-cache')}
            module = work / 'LampyrisInstallCore.swiftmodule'
            library = work / 'libLampyrisInstallCore.dylib'
            build_module = [
                'swiftc', '-emit-module', '-emit-library', '-module-name', 'LampyrisInstallCore',
                *map(str, sorted(CORE.glob('*.swift'))),
                '-emit-module-path', str(module), '-o', str(library),
            ]
            result = subprocess.run(build_module, cwd=ROOT, env=environment,
                                    capture_output=True, text=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            compile_probe = [
                'swiftc', '-warnings-as-errors', '-I', str(work),
                str(ROOT / 'platforms/macos/tests/install-core.swift'),
                '-L', str(work), '-lLampyrisInstallCore', '-o', str(work / 'probe'),
            ]
            result = subprocess.run(compile_probe, cwd=ROOT, env=environment,
                                    capture_output=True, text=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            record_probe(work / 'probe')
            result = subprocess.run([str(work / 'probe')], cwd=ROOT,
                                    env={**environment, 'DYLD_LIBRARY_PATH': str(work)},
                                    capture_output=True, text=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('PASS install-core', result.stdout)


if __name__ == '__main__':
    unittest.main()
