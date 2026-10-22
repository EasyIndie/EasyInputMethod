#!/usr/bin/env python3
"""Appcast 解析与版本选择（ADR-262）。

与独立更新程序（Swift）保持同一套规则，避免两个渠道对同一 feed 得出不同结论：
- 只接受 https 下载地址（无 user/password/fragment）；
- feed ≤ 1MiB、拒绝 DOCTYPE/ENTITY、深度 ≤ 16；
- 恰好一个 rss/channel、每个 item 恰好一个 enclosure；
- enclosure 必须带 sparkle:version（点分数字，≤8 段）、url、sparkle:edSignature（Base64，64 字节）、length（正整数）；
- item 数 ≤ 1000；
- 只选择 build 大于当前 build 的最高项。

解析结果为不可信元数据：真正的安全边界是下载后的 Ed25519 验签（ADR-256）。
"""
from __future__ import annotations

import base64
from dataclasses import dataclass
import urllib.parse
import xml.etree.ElementTree as ElementTree

MAX_FEED_BYTES = 1_048_576
MAX_ITEMS = 1000
MAX_DEPTH = 16


class FeedError(ValueError):
    """feed 结构/字段不合法；调用方应停止升级而不是猜测。"""


@dataclass(frozen=True)
class Build:
    parts: tuple

    @classmethod
    def parse(cls, value: str) -> 'Build':
        fields = value.split('.')
        if not fields or len(fields) > 8 or len(value.encode()) > 128:
            raise FeedError('build 格式非法：' + value)
        if any(not field or not field.isdigit() for field in fields):
            raise FeedError('build 格式非法：' + value)
        numbers = [int(field) for field in fields]
        while len(numbers) > 1 and numbers[-1] == 0:
            numbers.pop()
        return cls(tuple(numbers))

    def __lt__(self, other: 'Build') -> bool:
        count = max(len(self.parts), len(other.parts))
        for index in range(count):
            left = self.parts[index] if index < len(self.parts) else 0
            right = other.parts[index] if index < len(other.parts) else 0
            if left != right:
                return left < right
        return False


@dataclass(frozen=True)
class Release:
    build: str
    download_url: str
    signature: str
    length: int

    @property
    def parsed_build(self) -> Build:
        return Build.parse(self.build)


def _local(tag: str) -> str:
    return tag.rsplit('}', 1)[-1]


def _attribute(attributes: dict, name: str) -> str | None:
    for key, value in attributes.items():
        if _local(key) == name:
            return value
    return None


def _secure_url(value: str, allow_file: bool = False) -> bool:
    parsed = urllib.parse.urlparse(value)
    if allow_file and parsed.scheme.lower() == 'file':
        return parsed.hostname in (None, '', 'localhost')
    return (parsed.scheme.lower() == 'https' and bool(parsed.hostname)
            and parsed.username is None and parsed.password is None
            and not parsed.fragment)


def _check_depth(element: ElementTree.Element, depth: int = 1) -> None:
    if depth > MAX_DEPTH:
        raise FeedError('feed 嵌套过深')
    for child in element:
        _check_depth(child, depth + 1)


def parse_appcast(data: bytes, *, allow_file: bool = False) -> list[Release]:
    if len(data) > MAX_FEED_BYTES:
        raise FeedError('feed 超过大小上限')
    text = data.decode('utf-8', 'strict')
    upper = text.upper()
    if '<!DOCTYPE' in upper or '<!ENTITY' in upper:
        raise FeedError('feed 不得包含 DTD/实体声明')
    try:
        root = ElementTree.fromstring(text)
    except ElementTree.ParseError as error:
        raise FeedError('feed 不是合法 XML：' + str(error)) from error
    _check_depth(root)
    if _local(root.tag) != 'rss':
        raise FeedError('feed 根元素必须是 rss')
    channels = [child for child in root if _local(child.tag) == 'channel']
    if len(channels) != 1:
        raise FeedError('feed 必须恰好有一个 channel')
    channel = channels[0]
    items = [child for child in channel if _local(child.tag) == 'item']
    if len(items) > MAX_ITEMS:
        raise FeedError('feed item 超过上限')
    releases = []
    for item in items:
        enclosures = [child for child in item if _local(child.tag) == 'enclosure']
        if len(enclosures) != 1:
            raise FeedError('每个 item 必须恰好有一个 enclosure')
        enclosure = enclosures[0]
        build = _attribute(enclosure.attrib, 'version')
        url = _attribute(enclosure.attrib, 'url')
        signature = _attribute(enclosure.attrib, 'edSignature')
        length = _attribute(enclosure.attrib, 'length')
        if not build or not url or not signature or length is None:
            raise FeedError('enclosure 缺少 build/url/签名/长度')
        Build.parse(build)
        if not _secure_url(url, allow_file):
            raise FeedError('下载地址必须是 https')
        try:
            raw_signature = base64.b64decode(signature, validate=True)
        except ValueError as error:
            raise FeedError('签名不是合法 Base64') from error
        if len(raw_signature) != 64:
            raise FeedError('签名长度必须是 64 字节')
        if not length.isdigit() or int(length) <= 0:
            raise FeedError('length 必须是正整数')
        releases.append(Release(build=build, download_url=url, signature=signature, length=int(length)))
    return releases


def newest_release(releases: list[Release], current_build: str) -> Release | None:
    current = Build.parse(current_build)
    newest: Release | None = None
    for release in releases:
        if not current < release.parsed_build:
            continue
        if newest is not None and not newest.parsed_build < release.parsed_build:
            continue
        newest = release
    return newest
