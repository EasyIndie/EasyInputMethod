#!/usr/bin/env python3
"""离线回归：appcast 解析与版本选择（ADR-262），规则与独立更新程序一致。"""
import base64
import importlib.util
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('feed', ROOT / 'packaging/macos/feed.py')
feed = importlib.util.module_from_spec(spec)
sys.modules['feed'] = feed
spec.loader.exec_module(feed)

SIGNATURE = base64.b64encode(bytes(range(64))).decode()


def item(build, url='https://example.invalid/Lampyris.zip', signature=SIGNATURE, length='1234'):
    attributes = [('url', url), ('length', length)]
    if build is not None:
        attributes.insert(0, ('sparkle:version', build))
    if signature is not None:
        attributes.append(('sparkle:edSignature', signature))
    rendered = ' '.join(f'{name}="{value}"' for name, value in attributes)
    return f'<item><enclosure {rendered}/></item>'


def appcast(*items):
    body = ''.join(items)
    return (f'<?xml version="1.0" encoding="utf-8"?>'
            f'<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
            f'<channel><title>Lampyris</title>{body}</channel></rss>').encode()


class AppcastTests(unittest.TestCase):
    def test_newest_release_above_current(self):
        releases = feed.parse_appcast(appcast(item('7'), item('6'), item('8.0')))
        newest = feed.newest_release(releases, '6')
        self.assertIsNotNone(newest)
        self.assertEqual(newest.build, '8.0')
        self.assertEqual(newest.length, 1234)

    def test_no_update_when_current_is_newest(self):
        releases = feed.parse_appcast(appcast(item('6'), item('5')))
        self.assertIsNone(feed.newest_release(releases, '6'))
        self.assertIsNone(feed.newest_release(releases, '7'))

    def test_build_comparison_normalizes_trailing_zeroes(self):
        self.assertFalse(feed.Build.parse('7.0.0') < feed.Build.parse('7'))
        self.assertTrue(feed.Build.parse('7') < feed.Build.parse('7.0.1'))
        for invalid in ['', '7.', '.7', '7..1', 'a', '1.2.3.4.5.6.7.8.9', '7' * 200]:
            with self.assertRaises(feed.FeedError):
                feed.Build.parse(invalid)

    def test_rejects_dtd_and_entities(self):
        with self.assertRaises(feed.FeedError):
            feed.parse_appcast(b'<!DOCTYPE rss><rss/>')
        with self.assertRaises(feed.FeedError):
            feed.parse_appcast(b'<!ENTITY x "y"><rss/>')

    def test_rejects_oversized_feed(self):
        with self.assertRaises(feed.FeedError):
            feed.parse_appcast(b'x' * (feed.MAX_FEED_BYTES + 1))

    def test_rejects_non_https_download(self):
        for url in ['http://example.invalid/a.zip', 'ftp://example.invalid/a.zip',
                    'https://user:pass@example.invalid/a.zip', 'https://example.invalid/a.zip#x']:
            with self.assertRaises(feed.FeedError):
                feed.parse_appcast(appcast(item('7', url=url)))

    def test_rejects_missing_or_invalid_fields(self):
        with self.assertRaises(feed.FeedError):
            feed.parse_appcast(appcast(item(None)))
        with self.assertRaises(feed.FeedError):
            feed.parse_appcast(appcast(item('7', signature=None)))
        with self.assertRaises(feed.FeedError):
            feed.parse_appcast(appcast(item('7', signature='bm90LWJhc2U2NA==')))
        with self.assertRaises(feed.FeedError):
            feed.parse_appcast(appcast(item('7', length='0')))
        with self.assertRaises(feed.FeedError):
            feed.parse_appcast(appcast(item('7', length='abc')))

    def test_rejects_wrong_enclosure_count(self):
        with self.assertRaises(feed.FeedError):
            feed.parse_appcast(appcast('<item></item>'))
        with self.assertRaises(feed.FeedError):
            feed.parse_appcast(appcast('<item><enclosure url="https://example.invalid/a.zip"/>'
                                       '<enclosure url="https://example.invalid/b.zip"/></item>'))

    def test_rejects_wrong_root_or_multiple_channels(self):
        with self.assertRaises(feed.FeedError):
            feed.parse_appcast(b'<feed/>')
        with self.assertRaises(feed.FeedError):
            feed.parse_appcast(b'<rss><channel/><channel/></rss>')

    def test_rejects_too_many_items(self):
        body = '<?xml version="1.0"?><rss><channel>' + item('7') * (feed.MAX_ITEMS + 1) + '</channel></rss>'
        with self.assertRaises(feed.FeedError):
            feed.parse_appcast(body.encode())

    def test_rejects_deep_nesting(self):
        deep = '<a>' * (feed.MAX_DEPTH + 2) + '</a>' * (feed.MAX_DEPTH + 2)
        with self.assertRaises(feed.FeedError):
            feed.parse_appcast(f'<rss><channel>{deep}</channel></rss>'.encode())


if __name__ == '__main__':
    unittest.main()
