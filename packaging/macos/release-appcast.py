#!/usr/bin/env python3
"""生成 Ed25519 签名的 Sparkle 兼容 appcast（ADR-265）。

只做离线文件操作：读 ZIP、签名、写 XML；不联网、不上传、不安装。上传由发布流程负责。

用法：
    python3 packaging/macos/release-appcast.py \
        --zip Lampyris-0.1.0-universal.zip \
        --build 7 --short-version 0.1.0 \
        --url https://github.com/EasyIndie/EasyInputMethod/releases/download/v0.1.0/Lampyris-0.1.0-universal.zip \
        --private-key lampyris-update-private.pem \
        --out appcast.xml

输出 JSON 摘要（length/sha256/签名），供 CI 记录；私钥内容绝不打印。
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
from xml.sax.saxutils import quoteattr


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b''):
            digest.update(chunk)
    return digest.hexdigest()


def secure_url(value: str) -> bool:
    parsed = urllib.parse.urlparse(value)
    return (parsed.scheme == 'https' and bool(parsed.hostname)
            and parsed.username is None and parsed.password is None
            and not parsed.fragment)


def openssl_path(explicit: str | None) -> str:
    candidate = explicit or os.environ.get('OPENSSL_BIN') or shutil.which('openssl')
    if not candidate:
        raise SystemExit('BLOCKED：找不到 openssl（需要 Ed25519 支持）')
    return candidate


def sign(zip_path: Path, private_key: Path, openssl: str) -> bytes:
    with tempfile.TemporaryDirectory(prefix='lampyris-sign-') as folder:
        signature = Path(folder) / 'payload.sig'
        try:
            subprocess.run([openssl, 'pkeyutl', '-sign', '-rawin', '-inkey', str(private_key),
                            '-in', str(zip_path), '-out', str(signature)], check=True,
                           capture_output=True)
        except subprocess.CalledProcessError as error:
            raise SystemExit('BLOCKED：签名失败（私钥或 OpenSSL 不支持 Ed25519）') from error
        raw = signature.read_bytes()
    if len(raw) != 64:
        raise SystemExit('BLOCKED：Ed25519 签名长度异常')
    return raw


def verify(zip_path: Path, signature: bytes, private_key: Path, openssl: str) -> None:
    with tempfile.TemporaryDirectory(prefix='lampyris-verify-') as folder:
        public = Path(folder) / 'public.pem'
        sig = Path(folder) / 'payload.sig'
        subprocess.run([openssl, 'pkey', '-in', str(private_key), '-pubout', '-out', str(public)],
                       check=True, capture_output=True)
        sig.write_bytes(signature)
        result = subprocess.run([openssl, 'pkeyutl', '-verify', '-rawin', '-pubin',
                                 '-inkey', str(public), '-in', str(zip_path), '-sigfile', str(sig)],
                                capture_output=True)
    if result.returncode != 0:
        raise SystemExit('BLOCKED：自检验签失败')


def appcast(build: str, url: str, signature: str, length: int) -> str:
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">\n'
        '  <channel>\n'
        '    <title>Lampyris</title>\n'
        '    <item>\n'
        f'      <enclosure url={quoteattr(url)} length="{length}" '
        f'sparkle:version={quoteattr(build)} sparkle:edSignature={quoteattr(signature)} '
        'type="application/octet-stream"/>\n'
        '    </item>\n'
        '  </channel>\n'
        '</rss>\n'
    )


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--zip', type=Path, required=True)
    parser.add_argument('--build', required=True, help='CFBundleVersion / sparkle:version')
    parser.add_argument('--short-version', required=True)
    parser.add_argument('--url', required=True, help='ZIP 的 https 下载地址')
    parser.add_argument('--private-key', type=Path, required=True)
    parser.add_argument('--out', type=Path, default=Path('appcast.xml'))
    parser.add_argument('--openssl', help='OpenSSL 可执行文件（默认 $OPENSSL_BIN 或 PATH）')
    args = parser.parse_args(argv)

    if not args.zip.is_file() or args.zip.stat().st_size == 0:
        raise SystemExit('BLOCKED：ZIP 不存在或为空')
    if not args.private_key.is_file():
        raise SystemExit('BLOCKED：私钥文件不存在')
    if not secure_url(args.url):
        raise SystemExit('BLOCKED：下载地址必须是 https（不得含凭据/fragment）')
    if not args.build.isdigit():
        raise SystemExit('BLOCKED：build 必须是纯数字')
    openssl = openssl_path(args.openssl)

    signature = sign(args.zip, args.private_key, openssl)
    verify(args.zip, signature, args.private_key, openssl)
    encoded = base64.b64encode(signature).decode()
    length = args.zip.stat().st_size
    xml = appcast(args.build, args.url, encoded, length)
    args.out.write_text(xml)
    args.out.chmod(0o644)
    print(json.dumps({
        'build': args.build,
        'short_version': args.short_version,
        'length': length,
        'sha256': sha256(args.zip),
        'signature': encoded,
        'appcast': str(args.out),
    }, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == '__main__':
    sys.exit(main())
