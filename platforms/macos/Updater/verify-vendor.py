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
source = (root / source_name).read_text()
for local, upstream in [
    ('public struct UpdateRelease: Equatable, Sendable {', 'public struct UpdateRelease: Equatable {'),
    ('public struct UpdateCheckConfiguration: Sendable {', 'public struct UpdateCheckConfiguration {'),
]:
    if source.count(local) != 1:
        raise SystemExit('更新库本地并发补丁范围不符')
    source = source.replace(local, upstream)
if hashlib.sha256(source.encode()).hexdigest() != metadata['upstream_files'][source_name]:
    raise SystemExit('更新库除登记补丁外偏离固定上游')
print('更新库来源/许可/镜像测试摘要一致')
