#!/usr/bin/env python3
"""离线回归：发布 appcast 生成与 Ed25519 签名（ADR-265）。"""
import base64
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('release_appcast', ROOT / 'packaging/macos/release-appcast.py')
release_appcast = importlib.util.module_from_spec(spec)
sys.modules['release_appcast'] = release_appcast
spec.loader.exec_module(release_appcast)

feed_spec = importlib.util.spec_from_file_location('feed', ROOT / 'packaging/macos/feed.py')
feed = importlib.util.module_from_spec(feed_spec)
sys.modules['feed'] = feed
feed_spec.loader.exec_module(feed)


def openssl_supports_ed25519() -> bool:
    binary = shutil.which('openssl')
    if not binary:
        return False
    with tempfile.TemporaryDirectory() as folder:
        key = Path(folder) / 'key.pem'
        result = subprocess.run([binary, 'genpkey', '-algorithm', 'ED25519', '-out', str(key)],
                                capture_output=True)
        if result.returncode != 0:
            return False
        payload = Path(folder) / 'payload.bin'
        payload.write_bytes(b'probe')
        sig = Path(folder) / 'sig.bin'
        signed = subprocess.run([binary, 'pkeyutl', '-sign', '-rawin', '-inkey', str(key),
                                 '-in', str(payload), '-out', str(sig)], capture_output=True)
        return signed.returncode == 0 and sig.stat().st_size == 64


SUPPORTED = openssl_supports_ed25519()


@unittest.skipUnless(SUPPORTED, 'requires OpenSSL with Ed25519 (rawin)')
class ReleaseAppcastTests(unittest.TestCase):
    def setUp(self):
        self.folder = Path(tempfile.mkdtemp(prefix='lampyris-appcast-test-'))
        self.addCleanup(shutil.rmtree, self.folder, True)
        self.key = self.folder / 'key.pem'
        subprocess.run([shutil.which('openssl'), 'genpkey', '-algorithm', 'ED25519',
                        '-out', str(self.key)], check=True, capture_output=True)
        self.zip = self.folder / 'Lampyris.zip'
        self.zip.write_bytes(b'PK\x03\x04 fixture payload' * 10)
        self.url = 'https://github.com/EasyIndie/EasyInputMethod/releases/download/v9/Lampyris.zip'

    def run_tool(self, *extra):
        out = self.folder / 'appcast.xml'
        code = release_appcast.main([
            '--zip', str(self.zip), '--build', '9', '--short-version', '0.1.0',
            '--url', self.url, '--private-key', str(self.key), '--out', str(out), *extra])
        return code, out

    def test_generates_parseable_signed_appcast(self):
        code, out = self.run_tool()
        self.assertEqual(code, 0)
        releases = feed.parse_appcast(out.read_bytes())
        self.assertEqual(len(releases), 1)
        release = releases[0]
        self.assertEqual(release.build, '9')
        self.assertEqual(release.length, self.zip.stat().st_size)
        self.assertEqual(len(base64.b64decode(release.signature)), 64)
        # 选版本逻辑：当前 8 时能看到 9。
        self.assertIsNotNone(feed.newest_release(releases, '8'))
        self.assertIsNone(feed.newest_release(releases, '9'))

    def test_signature_verifies_with_openssl(self):
        code, out = self.run_tool()
        self.assertEqual(code, 0)
        release = feed.parse_appcast(out.read_bytes())[0]
        public = self.folder / 'public.pem'
        sig = self.folder / 'sig.bin'
        subprocess.run([shutil.which('openssl'), 'pkey', '-in', str(self.key), '-pubout',
                        '-out', str(public)], check=True, capture_output=True)
        sig.write_bytes(base64.b64decode(release.signature))
        result = subprocess.run([shutil.which('openssl'), 'pkeyutl', '-verify', '-rawin',
                                 '-pubin', '-inkey', str(public), '-in', str(self.zip),
                                 '-sigfile', str(sig)], capture_output=True)
        self.assertEqual(result.returncode, 0)

    def test_rejects_insecure_url(self):
        for url in ['http://example.invalid/a.zip', 'https://u:p@example.invalid/a.zip',
                    'https://example.invalid/a.zip#x']:
            with self.assertRaises(SystemExit):
                release_appcast.main(['--zip', str(self.zip), '--build', '9',
                                      '--short-version', '0.1.0', '--url', url,
                                      '--private-key', str(self.key),
                                      '--out', str(self.folder / 'x.xml')])

    def test_rejects_missing_or_empty_zip(self):
        empty = self.folder / 'empty.zip'
        empty.write_bytes(b'')
        for path in [empty, self.folder / 'missing.zip']:
            with self.assertRaises(SystemExit):
                release_appcast.main(['--zip', str(path), '--build', '9',
                                      '--short-version', '0.1.0', '--url', self.url,
                                      '--private-key', str(self.key),
                                      '--out', str(self.folder / 'x.xml')])

    def test_rejects_bad_build_and_missing_key(self):
        for build, key in [('abc', self.key), ('9', self.folder / 'missing.pem')]:
            with self.assertRaises(SystemExit):
                release_appcast.main(['--zip', str(self.zip), '--build', build,
                                      '--short-version', '0.1.0', '--url', self.url,
                                      '--private-key', str(key),
                                      '--out', str(self.folder / 'x.xml')])


if __name__ == '__main__':
    unittest.main()
