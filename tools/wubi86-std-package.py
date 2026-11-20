#!/usr/bin/env python3
"""把 LWS-86 数据包打成可复现的发布资产（S-1）。

要求与原因：
- **可复现**：同一份数据包（同一提交）两次打包必须得到同一个 SHA-256，否则第三方无法核对。
  为此条目按名称排序、时间戳固定为 1980-01-01、权限固定 0644、不写目录条目、不压缩元数据。
- **不新增来源**：内容全部来自 `build/wubi86-std-<版本>/`（由 `make wubi86-standard` 生成）。

产物：`<out>/LWS-86-<版本>.zip` 与同名 `.sha256`（格式与其它发布资产一致：`<hash>  <文件名>`）。
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import zipfile

FIXED_TIME = (1980, 1, 1, 0, 0, 0)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--bundle', default='build/wubi86-std-1.0')
    parser.add_argument('--out', default='packaging/out/release')
    args = parser.parse_args()
    bundle = pathlib.Path(args.bundle)
    meta = json.loads((bundle / 'meta.json').read_text(encoding='utf-8'))
    version = meta['version']
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    name = f'LWS-86-{version}.zip'
    target = out / name

    files = sorted(p for p in bundle.iterdir() if p.is_file())
    with zipfile.ZipFile(target, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in files:
            info = zipfile.ZipInfo(f'LWS-86-{version}/{path.name}', date_time=FIXED_TIME)
            info.external_attr = 0o644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, path.read_bytes())

    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    (out / f'{name}.sha256').write_text(f'{digest}  {name}\n', encoding='utf-8')
    print(json.dumps({'asset': str(target), 'sha256': digest, 'files': [p.name for p in files]},
                     ensure_ascii=False))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
