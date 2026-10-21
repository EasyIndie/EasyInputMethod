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
print('更新库来源/许可/镜像测试摘要一致')
