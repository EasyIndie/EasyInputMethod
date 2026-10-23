#!/usr/bin/env python3
"""离线回归：更新公钥入库、可审计，且构建/工作流不依赖隐藏变量（ADR-266）。"""
import base64
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[3]
KEY = ROOT / 'packaging/macos/update-public-key.txt'
BUILD = ROOT / 'platforms/macos/Updater/build.py'
WORKFLOWS = [ROOT / '.github/workflows/release.yml',
             ROOT / '.github/workflows/update-signing-check.yml']


class UpdatePublicKeyTests(unittest.TestCase):
    def test_key_is_valid_ed25519_public_key(self):
        raw = base64.b64decode(KEY.read_text().strip(), validate=True)
        self.assertEqual(len(raw), 32)

    def test_readme_records_key_and_fingerprint(self):
        import hashlib
        raw = base64.b64decode(KEY.read_text().strip(), validate=True)
        readme = (ROOT / 'README.md').read_text()
        self.assertIn(KEY.read_text().strip(), readme)
        self.assertIn(hashlib.sha256(raw).hexdigest(), readme)

    def test_release_requires_signed_tag(self):
        text = (ROOT / '.github/workflows/release.yml').read_text()
        self.assertIn('packaging/git-allowed-signers', text)
        self.assertIn('git tag -v', text)

    def test_build_script_defaults_to_committed_key(self):
        source = BUILD.read_text()
        self.assertIn('update-public-key.txt', source)
        self.assertIn('PINNED_PUBLIC_KEY.read_text()', source)
        self.assertIn('32 字节', source)

    def test_workflows_do_not_hide_the_public_key(self):
        for workflow in WORKFLOWS:
            text = workflow.read_text()
            self.assertNotIn('LAMPYRIS_UPDATE_PUBLIC_KEY', text,
                             f'{workflow.name} 仍从变量/Secret 读取公钥')
            self.assertIn('python3 platforms/macos/Updater/build.py', text)
            self.assertNotIn('--public-key', text)

    def test_private_key_is_not_committed(self):
        # 只匹配「BEGIN … PRIVATE KEY + 实际 Base64 主体」，避免把检查该标记的脚本当成密钥。
        marker = re.compile('BEGIN [A-Z ]*PRIVATE KEY-----[ \\t]*\\n[A-Za-z0-9+/=\\s]{40,}')
        tracked = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).split(b'\0')
        for raw in tracked:
            if not raw:
                continue
            path = ROOT / raw.decode()
            if path == Path(__file__).resolve() or path.stat().st_size > 4096:
                continue
            try:
                text = path.read_text(errors='ignore')
            except OSError:
                continue
            self.assertIsNone(marker.search(text), f'私钥疑似入库：{path}')


if __name__ == '__main__':
    unittest.main()
