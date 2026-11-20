#!/usr/bin/env python3
"""生成 LWS-86 数据包（ADR-381）。

输入全部是仓库内已登记的数据（不联网、不新增来源）：
  data/learning/wubi86-root-inventory.tsv     标准字根清单（241 条，ADR-358）
  data/generated/B0-runtime.tsv               逐字全码/根序/识别码/简码（ADR-311 v3）
  data/sources/wubi86-level{1,2,3}-codes.tsv  一/二/三级简码表（D17 家族）

输出（默认 `build/wubi86-std-<version>/`，不入库）：
  roots.tsv        字形	键位	类别
  chars.tsv        字	全码	质量	根序(字形,空格分隔)	键位	识别码	简码槽位
  shortcodes.tsv   字	等级	简码
  meta.json        版本/范围/计数/源文件 SHA-256/生成命令
  SHA256SUMS       上面所有文件的校验和

判定与等级见 docs/standards/wubi86/conformance-1.0.md。
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
VERSION = '1.0'
SCOPE = ROOT / 'data/generated/gb2312-level1.txt'
RUNTIME = ROOT / 'data/generated/B0-runtime.tsv'
ROOTS = ROOT / 'data/learning/wubi86-root-inventory.tsv'
STROKES = ROOT / 'data/learning/wubi86-root-strokes.tsv'
SHORTCODES = [(1, ROOT / 'data/sources/wubi86-level1-codes.tsv'),
              (2, ROOT / 'data/sources/wubi86-level2-codes.tsv'),
              (3, ROOT / 'data/sources/wubi86-level3-codes.tsv')]


def source_date() -> str:
    """可复现的时间戳：优先 SOURCE_DATE_EPOCH，其次 git 提交时间，最后当前时间。

    数据包要能被第三方重建并比对 SHA-256，所以默认值不能是"生成那一刻"。
    """
    epoch = os.environ.get('SOURCE_DATE_EPOCH')
    if epoch and epoch.isdigit():
        return time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(int(epoch)))
    try:
        out = subprocess.run(['git', 'log', '-1', '--format=%ct'], cwd=ROOT,
                             capture_output=True, text=True, timeout=10)
        if out.returncode == 0 and out.stdout.strip().isdigit():
            return time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(int(out.stdout.strip())))
    except (OSError, subprocess.SubprocessError):
        pass
    return time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


STROKE_LETTER = {'横': 'g', '竖': 'h', '撇': 't', '捺': 'y', '折': 'n'}
STROKE_GLYPH = {'一': '横', '丨': '竖', '丿': '撇', '丶': '捺', '乙': '折'}


def stroke_order() -> dict[str, list[str]]:
    """D18 成字字根笔顺（项目自编，CC-BY-SA-4.0）。"""
    out = {}
    for row in rows(STROKES):
        if len(row) >= 2:
            out[row[0]] = [ch for ch in row[1].replace(' ', '') if ch in STROKE_GLYPH]
    return out


def chengzi_code(char: str, key: str, strokes: list[str]) -> str | None:
    """R9 成字字根：报户口 + 首笔 + 次笔 + 末笔（R9a 单笔画：键×2 + ll）。"""
    letters = [STROKE_LETTER[STROKE_GLYPH[ch]] for ch in strokes]
    if len(letters) == 0:
        return None
    if len(letters) == 1:
        return key + letters[0] + 'll'
    if len(letters) == 2:
        return key + letters[0] + letters[1]
    return key + letters[0] + letters[1] + letters[-1]


def rows(path: pathlib.Path) -> list[list[str]]:
    out = []
    for line in path.read_text(encoding='utf-8').splitlines():
        if not line or line.startswith('#'):
            continue
        out.append(line.split('\t'))
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', default=str(ROOT / f'build/wubi86-std-{VERSION}'))
    args = parser.parse_args()
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    scope = {line.strip() for line in SCOPE.read_text(encoding='utf-8').splitlines()
             if line.strip() and not line.startswith('#')}

    # roots
    root_rows = rows(ROOTS)
    root_keys: dict[str, set[str]] = {}
    for row in root_rows:
        if len(row) >= 3 and len(row[0]) == 1:
            root_keys.setdefault(row[0], set()).add(row[1])
    stroke_data = stroke_order()
    roots_out = ['# LWS-86 标准字根表（字形\t键位\t类别）']
    for row in root_rows:
        if len(row) >= 3 and len(row[0]) == 1:
            roots_out.append('\t'.join([row[0], row[1], row[2]]))
    (out / 'roots.tsv').write_text('\n'.join(roots_out) + '\n', encoding='utf-8')

    # chars（全量学习字表；scope 标记 GB2312 一级）
    chars_out = ['# LWS-86 逐字根序（字\t全码\t质量\t根序\t键位\t识别码\t简码一/二/三\t范围内\t类别）']
    in_scope = 0
    full = partial = 0
    for row in rows(RUNTIME):
        if len(row) < 6:
            continue
        char, code, quality, roots, recognition, shorts = row[:6]
        cells = [cell for cell in roots.split() if ':' in cell]
        glyphs = ' '.join(cell.rsplit(':', 1)[0] for cell in cells)
        keys = ''.join(cell.rsplit(':', 1)[1] for cell in cells)
        scoped = '1' if char in scope else '0'
        # 类别：key-name（键名字，四同键）/ radical-char（成字字根，报户口+笔画）/ compound（合体）
        if code and len(code) == 4 and len(set(code)) == 1:
            klass = 'key-name'
        elif glyphs in (char, ''):
            # R9 推得出来且一致 → radical-char；有笔顺却推不出（如 母、方、车、止）→ 官方特例；
            # 缺笔顺数据时不冒充「推导通过」，但也不判成特例（退回旧的形状校验）。
            derived = ''
            strokes = stroke_data.get(char, [])
            if code and code[0] in root_keys.get(char, set()) and strokes:
                derived = chengzi_code(char, code[0], strokes) or ''
            if derived:
                klass = 'radical-char' if derived == code else 'radical-char-exception'
            elif code and code[0] in root_keys.get(char, set()) \
                    and all(letter in 'ghtyn' for letter in code[1:]):
                klass = 'radical-char'
            else:
                klass = 'radical-char-exception'
        else:
            klass = 'compound'
        if scoped == '1':
            in_scope += 1
            if quality == 'full':
                full += 1
            elif quality == 'partial':
                partial += 1
        chars_out.append('\t'.join([char, code, quality, glyphs, keys, recognition, shorts, scoped, klass]))
    (out / 'chars.tsv').write_text('\n'.join(chars_out) + '\n', encoding='utf-8')

    # shortcodes
    short_out = ['# LWS-86 简码表（字\t等级\t简码）']
    counts = {}
    for level, path in SHORTCODES:
        n = 0
        for row in rows(path):
            if len(row) >= 2 and len(row[1]) == 1:
                short_out.append('\t'.join([row[1], str(level), row[0]]))
                n += 1
        counts[f'level{level}'] = n
    (out / 'shortcodes.tsv').write_text('\n'.join(short_out) + '\n', encoding='utf-8')

    meta = {
        'standard': 'LWS-86',
        'version': VERSION,
        'title': '萤火虫五笔86 拆字标准 / Lampyris Wubi86 Standard',
        'scheme': 'wubi86',
        'scope': {'gb2312Level1': len(scope), 'inScope': in_scope,
                  'full': full, 'partial': partial,
                  'fullPercent': round(100.0 * full / max(in_scope, 1), 1)},
        'entries': len(chars_out) - 1,
        'roots': len(roots_out) - 1,
        'shortcodes': counts,
        'sources': {str(p.relative_to(ROOT)): sha256(p)
                    for p in [SCOPE, RUNTIME, ROOTS] + [p for _, p in SHORTCODES]},
        'generatedAt': source_date(),
        'generator': 'tools/wubi86-std-bundle.py',
        'license': {'spec': 'CC-BY-SA-4.0', 'data': 'CC-BY-SA-4.0', 'code': 'GPL-3.0-or-later'},
    }
    (out / 'meta.json').write_text(json.dumps(meta, ensure_ascii=False, indent=2) + '\n',
                                   encoding='utf-8')

    lines = []
    for name in ('roots.tsv', 'chars.tsv', 'shortcodes.tsv', 'meta.json'):
        lines.append(f'{sha256(out / name)}  {name}')
    (out / 'SHA256SUMS').write_text('\n'.join(lines) + '\n', encoding='utf-8')

    try:
        shown = out.relative_to(ROOT)
    except ValueError:
        shown = out
    print(f'写入 {shown}：chars={meta["entries"]} roots={meta["roots"]} '
          f'shortcodes={counts} 范围内 {in_scope} 字 full {full}（{meta["scope"]["fullPercent"]}%）')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
