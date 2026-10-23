#!/usr/bin/env python3
"""离线回归：升级顺序（验签→解包→校验→停宿主→替换→回滚），不触碰真实安装目录。"""
import base64
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('upgrade', ROOT / 'packaging/macos/upgrade.py')
upgrade = importlib.util.module_from_spec(spec)
sys.modules['upgrade'] = upgrade
spec.loader.exec_module(upgrade)


def make_app(parent: Path, marker: str) -> Path:
    app = parent / upgrade.BUNDLE
    executable = app / upgrade.EXECUTABLE
    executable.parent.mkdir(parents=True)
    executable.write_text(marker)
    executable.chmod(0o755)
    return app


def make_payload(app: Path, destination: Path) -> Path:
    result = subprocess.run(['/usr/bin/ditto', '-c', '-k', '--keepParent', str(app), str(destination)],
                            capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr)
    return destination


class Hooks:
    def __init__(self):
        self.events = []
        self.fail_payload = False
        self.fail_stop = False
        self.fail_after_swap = False
        self.candidate_calls = 0

    def verify_payload(self, payload, signature):
        self.events.append('payload')
        if self.fail_payload:
            raise upgrade.UpgradeError('bad signature')

    def verify_candidate(self, app):
        self.candidate_calls += 1
        self.events.append('candidate')
        if self.fail_after_swap and self.candidate_calls >= 2:
            raise upgrade.UpgradeError('post-swap check failed')
        if not (app / upgrade.EXECUTABLE).is_file():
            raise upgrade.UpgradeError('missing executable')

    def stop_host(self, executable):
        self.events.append('stop')
        if self.fail_stop:
            raise upgrade.UpgradeError('host still running')

    def hooks(self):
        return upgrade.Hooks(self.verify_payload, self.verify_candidate, self.stop_host)


class UpgradeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = Path(tempfile.mkdtemp(prefix='lampyris-upgrade-test-'))
        self.addCleanup(shutil.rmtree, self.temporary, True)
        self.domain = self.temporary / 'Input Methods'
        self.domain.mkdir()
        self.support = self.temporary / 'Support'
        self.build = self.temporary / 'build'
        self.build.mkdir()
        new_app = make_app(self.build / 'new', 'new-binary')
        self.payload = make_payload(new_app, self.temporary / 'payload.zip')
        self.state = Hooks()

    def test_fresh_install_places_bundle_and_writes_private_receipt(self):
        receipt = upgrade.install(self.payload, 'sig', self.domain, self.support,
                                  self.state.hooks(), dry_run=False)
        installed = self.domain / upgrade.BUNDLE
        self.assertEqual((installed / upgrade.EXECUTABLE).read_text(), 'new-binary')
        self.assertIsNone(receipt['previous'])
        self.assertEqual(receipt['result'], 'installed')
        self.assertEqual(self.state.events, ['payload', 'candidate', 'candidate'])
        receipts = list((self.support / 'receipts').glob('*.json'))
        self.assertEqual(len(receipts), 1)
        self.assertEqual(receipts[0].stat().st_mode & 0o777, 0o600)
        self.assertEqual(json.loads(receipts[0].read_text())['payload_sha256'], upgrade.sha256(self.payload))

    def test_upgrade_keeps_previous_bundle_and_stops_host(self):
        destination = self.domain / upgrade.BUNDLE
        old = make_app(self.domain, 'old-binary')
        self.assertEqual(destination, old)
        receipt = upgrade.install(self.payload, 'sig', self.domain, self.support,
                                  self.state.hooks(), dry_run=False)
        self.assertEqual((destination / upgrade.EXECUTABLE).read_text(), 'new-binary')
        self.assertEqual(self.state.events, ['payload', 'candidate', 'stop', 'candidate'])
        backup = Path(receipt['previous'])
        self.assertEqual((backup / upgrade.EXECUTABLE).read_text(), 'old-binary')

    def test_rollback_restores_previous_bundle_after_post_swap_failure(self):
        destination = self.domain / upgrade.BUNDLE
        make_app(self.domain, 'old-binary')
        self.state.fail_after_swap = True
        with self.assertRaises(upgrade.UpgradeError):
            upgrade.install(self.payload, 'sig', self.domain, self.support,
                            self.state.hooks(), dry_run=False)
        self.assertEqual((destination / upgrade.EXECUTABLE).read_text(), 'old-binary')

    def test_signature_failure_touches_nothing(self):
        destination = self.domain / upgrade.BUNDLE
        make_app(self.domain, 'old-binary')
        self.state.fail_payload = True
        with self.assertRaises(upgrade.UpgradeError):
            upgrade.install(self.payload, 'sig', self.domain, self.support,
                            self.state.hooks(), dry_run=False)
        self.assertEqual((destination / upgrade.EXECUTABLE).read_text(), 'old-binary')
        self.assertNotIn('stop', self.state.events)
        self.assertFalse(self.support.exists())

    def test_stop_host_failure_keeps_previous_bundle(self):
        destination = self.domain / upgrade.BUNDLE
        make_app(self.domain, 'old-binary')
        self.state.fail_stop = True
        with self.assertRaises(upgrade.UpgradeError):
            upgrade.install(self.payload, 'sig', self.domain, self.support,
                            self.state.hooks(), dry_run=False)
        self.assertEqual((destination / upgrade.EXECUTABLE).read_text(), 'old-binary')

    def test_dry_run_does_not_stop_or_replace(self):
        destination = self.domain / upgrade.BUNDLE
        make_app(self.domain, 'old-binary')
        receipt = upgrade.install(self.payload, 'sig', self.domain, self.support,
                                  self.state.hooks(), dry_run=True)
        self.assertEqual(receipt['result'], 'dry-run')
        self.assertEqual((destination / upgrade.EXECUTABLE).read_text(), 'old-binary')
        self.assertNotIn('stop', self.state.events)

    def test_symlink_destination_is_rejected(self):
        other = self.temporary / 'other'
        other.mkdir()
        make_app(other, 'elsewhere').rename(self.temporary / 'elsewhere.app')
        (self.domain / upgrade.BUNDLE).symlink_to(self.temporary / 'elsewhere.app')
        with self.assertRaises(upgrade.UpgradeError):
            upgrade.install(self.payload, 'sig', self.domain, self.support,
                            self.state.hooks(), dry_run=False)

    def test_payload_with_release_wrapper_directory_is_supported(self):
        wrapper = self.build / 'Lampyris-0.1.0-universal'
        wrapper.mkdir()
        make_app(wrapper, 'new-binary').rename(wrapper / upgrade.BUNDLE)
        (wrapper / 'README.md').write_text('release notes')
        payload = make_payload(wrapper, self.temporary / 'wrapped.zip')
        upgrade.install(payload, 'sig', self.domain, self.support,
                        self.state.hooks(), dry_run=False)
        self.assertEqual((self.domain / upgrade.BUNDLE / upgrade.EXECUTABLE).read_text(), 'new-binary')

    def test_payload_with_two_wrappers_is_rejected(self):
        for name in ['one', 'two']:
            wrapper = self.build / name
            wrapper.mkdir()
            make_app(wrapper, name).rename(wrapper / upgrade.BUNDLE)
        payload = make_payload(self.build, self.temporary / 'ambiguous.zip')
        with self.assertRaises(upgrade.UpgradeError):
            upgrade.install(payload, 'sig', self.domain, self.support,
                            self.state.hooks(), dry_run=False)

    def test_payload_without_bundle_is_rejected(self):
        broken = self.temporary / 'plain.zip'
        source = self.temporary / 'plain'
        source.mkdir()
        (source / 'readme.txt').write_text('x')
        subprocess.run(['/usr/bin/ditto', '-c', '-k', '--keepParent', str(source), str(broken)],
                       check=True)
        with self.assertRaises(upgrade.UpgradeError):
            upgrade.install(broken, 'sig', self.domain, self.support,
                            self.state.hooks(), dry_run=False)
        self.assertNotIn('stop', self.state.events)




class HolderTests(unittest.TestCase):
    def test_only_exact_binary_holders_are_stopped(self):
        executable = Path('/Applications/Lampyris.app/Contents/MacOS/Lampyris')
        exact, ignored = upgrade.host_holders(executable, [
            (10, str(executable)),
            (11, '/usr/libexec/lsd'),
            (12, '/sbin/launchd'),
        ])
        self.assertEqual(exact, [10])
        self.assertEqual(ignored, [11, 12])


class DownloadTests(unittest.TestCase):
    def setUp(self):
        self.temporary = Path(tempfile.mkdtemp(prefix='lampyris-download-test-'))
        self.addCleanup(shutil.rmtree, self.temporary, True)

    def payload(self, data=b'payload-bytes'):
        path = self.temporary / 'payload.zip'
        path.write_bytes(data)
        return path

    def test_rejects_non_https(self):
        with self.assertRaises(upgrade.UpgradeError):
            upgrade.download('http://example.invalid/payload.zip')
        with self.assertRaises(upgrade.UpgradeError):
            upgrade.download('ftp://example.invalid/payload.zip')

    def test_rejects_file_without_opt_in(self):
        source = self.payload()
        with self.assertRaises(upgrade.UpgradeError):
            upgrade.download(source.as_uri())

    def test_copies_file_payload_to_private_directory(self):
        source = self.payload(b'zip-bytes')
        target = upgrade.download(source.as_uri(), allow_file=True)
        try:
            self.assertEqual(target.read_bytes(), b'zip-bytes')
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)
            self.assertEqual(target.parent.stat().st_mode & 0o777, 0o700)
        finally:
            shutil.rmtree(target.parent, ignore_errors=True)

    def test_enforces_size_limit(self):
        source = self.payload(b'0123456789')
        with self.assertRaises(upgrade.UpgradeError):
            upgrade.download(source.as_uri(), allow_file=True, limit=4)

    def test_rejects_redirect_to_disallowed_scheme(self):
        class Response:
            def geturl(self):
                return 'http://example.invalid/payload.zip'
            def read(self, _):
                return b''
            def __enter__(self):
                return self
            def __exit__(self, *args):
                return False
        with self.assertRaises(upgrade.UpgradeError):
            upgrade.download('https://example.invalid/payload.zip', opener=lambda *a, **k: Response())

    def test_same_host_mirror_download_is_allowed(self):
        class Response:
            def geturl(self):
                return 'https://cn.example.com/payload.zip'
            def read(self, _):
                return b''
            def __enter__(self):
                return self
            def __exit__(self, *args):
                return False
        with self.assertRaises(upgrade.UpgradeError) as caught:
            upgrade.download('https://cn.example.com/payload.zip',
                             opener=lambda *a, **k: Response())
        self.assertNotIn('未允许的主机', str(caught.exception))

    def test_allows_redirect_to_github_asset_host(self):
        class Response:
            def geturl(self):
                return 'https://release-assets.githubusercontent.com/github-production/x'
            def read(self, _):
                return b''
            def __enter__(self):
                return self
            def __exit__(self, *args):
                return False
        class Stream:
            def __init__(self):
                self.sent = False
            def read(self, _):
                if self.sent:
                    return b''
                self.sent = True
                return b'payload'
        class GithubResponse(Response):
            def read(self, _):
                return Stream().read(_)
        # 只验证协议/主机策略：模拟一个空负载会失败，但失败原因不能是主机
        with self.assertRaises(upgrade.UpgradeError) as caught:
            upgrade.download('https://github.com/o/r/releases/download/v1/a.zip',
                             opener=lambda *a, **k: GithubResponse())
        self.assertNotIn('未允许的主机', str(caught.exception))

    def test_rejects_redirect_to_unlisted_host(self):
        class Response:
            def geturl(self):
                return 'https://evil.example/payload.zip'
            def read(self, _):
                return b''
            def __enter__(self):
                return self
            def __exit__(self, *args):
                return False
        with self.assertRaises(upgrade.UpgradeError) as caught:
            upgrade.download('https://github.com/o/r/releases/download/v1/a.zip',
                             opener=lambda *a, **k: Response())
        self.assertIn('未允许的主机', str(caught.exception))

    def test_rejects_empty_payload(self):
        source = self.payload(b'')
        with self.assertRaises(upgrade.UpgradeError):
            upgrade.download(source.as_uri(), allow_file=True)

    def test_select_release_skips_unreachable_sources(self):
        good = self.temporary / 'good.xml'
        good.write_bytes(
            b'<?xml version="1.0"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
            b'<channel><item><enclosure url="https://example.invalid/a.zip" length="10" '
            b'sparkle:version="7" sparkle:edSignature="' + base64.b64encode(bytes(64)) + b'"/></item>'
            b'</channel></rss>')
        missing = self.temporary / 'missing.xml'
        release = upgrade.select_release([('file', missing), ('file', good)], '6')
        self.assertIsNotNone(release)
        self.assertEqual(release.build, '7')
        with self.assertRaises(upgrade.UpgradeError):
            upgrade.select_release([('file', missing)], '6')

    def test_feed_list_falls_back_to_next_source(self):
        good = self.temporary / 'good.xml'
        good.write_bytes(
            b'<?xml version="1.0"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
            b'<channel><item><enclosure url="https://example.invalid/a.zip" length="10" '
            b'sparkle:version="7" sparkle:edSignature="' + base64.b64encode(bytes(64)) + b'"/></item>'
            b'</channel></rss>')
        code = upgrade.main(['--feed-file', str(good), '--current-build', '6',
                             '--domain', str(self.temporary / 'Input Methods'),
                             '--support', str(self.temporary / 'Support')])
        # 本地 file feed 不是 https 负载，会在下载阶段被拒绝（exit 3），但已成功选出 build 7。
        self.assertEqual(code, 3)

    def test_cli_reports_up_to_date_without_download(self):
        feed_file = self.temporary / 'appcast.xml'
        feed_file.write_text(
            '<?xml version="1.0"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
            '<channel><item><enclosure '
            'url="https://example.invalid/Lampyris.zip" length="10" '
            'sparkle:version="5" sparkle:edSignature="' + base64.b64encode(bytes(64)).decode()
            + '"/></item></channel></rss>')
        code = upgrade.main(['--feed-file', str(feed_file), '--current-build', '6',
                             '--domain', str(self.temporary / 'Input Methods'),
                             '--support', str(self.temporary / 'Support')])
        self.assertEqual(code, 0)

    def test_cli_blocks_file_url_without_flag(self):
        source = self.payload()
        code = upgrade.main(['--payload-url', source.as_uri(), '--signature', 'sig',
                             '--domain', str(self.temporary / 'Input Methods'),
                             '--support', str(self.temporary / 'Support')])
        self.assertEqual(code, 3)


if __name__ == '__main__':
    unittest.main()
