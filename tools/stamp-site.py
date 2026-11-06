#!/usr/bin/env python3
"""把站点里的版本占位符替换成**已发布**版本的版本号、构建号与体积（报告 251）。

站点源文件 `site/index.html` 不再硬编码版本：只写 `{{VERSION}}`、`{{BUILD}}`、`{{SIZE_MB}}`，
由发布流水线（或人工）用真实 Release 数据盖章后部署。这样"忘了改版本行就 dispatch Pages"
的坑（2026-11-06 实际发生过一次，报告 250）不可能再出现。
"""
from __future__ import annotations

import argparse
import re
import shutil
import sys
from pathlib import Path

PLACEHOLDERS = ('{{VERSION}}', '{{BUILD}}', '{{SIZE_MB}}')
PLACEHOLDER_RE = re.compile(r'\{\{[A-Z0-9_]+\}\}')


def stamp(html: str, version: str, build: str, size_mb: str) -> str:
    """替换占位符；版本/构建号格式非法或替换后仍有占位符时抛 ValueError。"""
    parts = version.split('.')
    if len(parts) != 3 or not all(part.isdigit() for part in parts):
        raise ValueError(f'版本号必须是 X.Y.Z：{version!r}')
    if not build.isdigit() or int(build) < 1:
        raise ValueError(f'构建号必须是正整数：{build!r}')
    if not size_mb.replace('.', '', 1).isdigit():
        raise ValueError(f'体积必须是数字（MB）：{size_mb!r}')
    out = html.replace('{{VERSION}}', version).replace('{{BUILD}}', build).replace('{{SIZE_MB}}', size_mb)
    left = PLACEHOLDER_RE.findall(out)
    if left:
        raise ValueError('仍有未替换的占位符：' + ', '.join(left))
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--version', required=True)
    parser.add_argument('--build', required=True)
    parser.add_argument('--size-mb', required=True)
    parser.add_argument('--src', default='site')
    parser.add_argument('--out', required=True)
    args = parser.parse_args()

    src, out = Path(args.src), Path(args.out)
    index = src / 'index.html'
    if not index.is_file():
        print(f'缺少站点首页：{index}', file=sys.stderr)
        return 2
    if out.exists():
        shutil.rmtree(out)
    shutil.copytree(src, out)
    try:
        stamped = stamp(index.read_text(encoding='utf-8'), args.version, args.build, args.size_mb)
    except ValueError as error:
        print(f'盖章失败：{error}', file=sys.stderr)
        return 1
    (out / 'index.html').write_text(stamped, encoding='utf-8')
    print(f'已盖章：v{args.version} · 构建 {args.build} · 约 {args.size_mb} MB → {out}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
