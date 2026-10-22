#!/usr/bin/env python3
"""离线回归：沙盒内 config 只经 ime-config 落到容器，不写真实 Application Support。"""
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[3]
PROBE_ID = 'cn.jokerhub.inputmethod.Lampyris.sandboxprobe'
PROBE = ROOT / 'platforms/macos/tests/sandbox-config-probe.swift'
ENTITLEMENTS = ROOT / 'platforms/macos/Lampyris-sandbox.entitlements'


def build_probe(folder: Path) -> Path:
    app = folder / 'Probe.app'
    macos = app / 'Contents/MacOS'
    macos.mkdir(parents=True)
    binary = macos / 'Probe'
    subprocess.run([
        'swiftc', '-O', '-warnings-as-errors', '-parse-as-library',
        '-module-cache-path', str(folder / 'cache'),
        '-I', str(ROOT / 'crates/ime-ffi/include'),
        str(PROBE), str(ROOT / 'target/release/libime_ffi.a'),
        '-framework', 'AppKit', '-o', str(binary)], check=True)
    info = {
        'CFBundleIdentifier': PROBE_ID,
        'CFBundleExecutable': 'Probe',
        'CFBundlePackageType': 'APPL',
        'CFBundleVersion': '1',
        'CFBundleShortVersionString': '0.0.1',
        'LSMinimumSystemVersion': '13.0',
        'LSBackgroundOnly': True,
    }
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    subprocess.run(['codesign', '--force', '--sign', '-', '--entitlements', str(ENTITLEMENTS), str(app)],
                   check=True, capture_output=True)
    return app


@unittest.skipUnless(os.uname().sysname == 'Darwin', 'requires macOS sandbox')
class SandboxConfigTests(unittest.TestCase):
    def test_sandbox_writes_config_inside_container_only(self):
        container = Path.home() / 'Library/Containers' / PROBE_ID
        shutil.rmtree(container, ignore_errors=True)
        with tempfile.TemporaryDirectory(prefix='lampyris-sandbox-') as folder:
            app = build_probe(Path(folder))
            subprocess.run(['open', '-W', '-g', str(app)], check=True, timeout=30)
            result_path = container / 'Data/tmp/sandbox-probe.json'
            for _ in range(50):
                if result_path.exists():
                    break
                time.sleep(0.1)
            self.assertTrue(result_path.exists(), 'probe did not write its result inside the container')
            result = json.loads(result_path.read_text())
            self.assertIn('/Library/Containers/', result['home'])
            self.assertIn('/Library/Containers/', result['config_path'])
            self.assertTrue(result['config_path'].endswith('/Library/Application Support/Lampyris/config.toml'))
            self.assertEqual(result['set'], 0, result)
            self.assertEqual(result['read'], '7')
            self.assertTrue(Path(result['config_path']).is_file())
            self.assertNotEqual(Path(result['config_path']),
                                Path.home() / 'Library/Application Support/Lampyris/config.toml')
        shutil.rmtree(container, ignore_errors=True)


class SandboxDeclarationTests(unittest.TestCase):
    def test_connection_name_and_entitlements_match_bundle(self):
        info = plistlib.loads((ROOT / 'platforms/macos/Info.plist').read_bytes())
        identifier = info['CFBundleIdentifier']
        self.assertEqual(info['InputMethodConnectionName'], identifier + '_Connection')
        self.assertEqual(info['InputMethodServerControllerClass'], 'LampyrisInputController')
        self.assertIn('tsInputModeListKey', info)
        self.assertIn(identifier + '.default', info['tsInputModeListKey'])
        entitlements = plistlib.loads(ENTITLEMENTS.read_bytes())
        self.assertTrue(entitlements.get('com.apple.security.app-sandbox'))
        self.assertEqual(
            entitlements.get('com.apple.security.temporary-exception.mach-register.global-name'),
            identifier + '_Connection')
        self.assertNotIn('com.apple.security.network.client', entitlements)
        source = (ROOT / 'platforms/macos/build.sh').read_text()
        self.assertIn('--sandbox', source)
        self.assertIn('Lampyris-sandbox.entitlements', source)


if __name__ == '__main__':
    unittest.main()
