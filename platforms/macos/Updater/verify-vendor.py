#!/usr/bin/env python3
"""Check the pinned upstream source, license and mirrored regression hashes offline."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parent
metadata = json.loads((root / 'Vendor/PROVENANCE.json').read_text())
for name, expected in metadata['files'].items():
    if hashlib.sha256((root / name).read_bytes()).hexdigest() != expected:
        raise SystemExit('更新库来源摘要不一致：' + name)
source_name = 'Vendor/OrzAppUpdaterCore/UpdateCheck.swift'
REDIRECT_HOSTS_PATCH = """    /// GitHub Releases 会把下载重定向到资产主机；只允许这些主机，且必须仍是 https。
    static let allowedRedirectHosts: Set<String> = [
        "github.com", "objects.githubusercontent.com",
        "release-assets.githubusercontent.com", "raw.githubusercontent.com",
    ]
"""
REDIRECT_GUARD_PATCH = """        let host = request.url?.host?.lowercased()
        guard let next = request.url, UpdateCheckConfiguration.secureURL(next),
              host == origin.host?.lowercased()
                || (host.map(Self.allowedRedirectHosts.contains) ?? false),
              (next.port ?? 443) == (origin.port ?? 443)"""
REDIRECT_GUARD_UPSTREAM = """        guard let next = request.url, UpdateCheckConfiguration.secureURL(next),
              next.host?.lowercased() == origin.host?.lowercased(),
              (next.port ?? 443) == (origin.port ?? 443)"""
source = (root / source_name).read_text()
for local, upstream in [
    ('public struct UpdateRelease: Equatable, Sendable {', 'public struct UpdateRelease: Equatable {'),
    ('public struct UpdateCheckConfiguration: Sendable {', 'public struct UpdateCheckConfiguration {'),
    (REDIRECT_HOSTS_PATCH, ''),
    (REDIRECT_GUARD_PATCH, REDIRECT_GUARD_UPSTREAM),
]:
    if source.count(local) != 1:
        raise SystemExit('更新库本地补丁范围不符')
    source = source.replace(local, upstream)
if hashlib.sha256(source.encode()).hexdigest() != metadata['upstream_files'][source_name]:
    raise SystemExit('更新库除登记补丁外偏离固定上游')
print('更新库来源/许可/镜像测试摘要一致')
