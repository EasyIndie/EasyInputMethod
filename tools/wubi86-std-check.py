#!/usr/bin/env python3
"""LWS-86 一致性判定（ADR-381）。第三方实现拿数据包就能自测。

用法：
  python3 tools/wubi86-std-check.py --bundle build/wubi86-std-1.0                  # 自检（实现=标准）
  python3 tools/wubi86-std-check.py --bundle build/wubi86-std-1.0 --impl <dir> --level L2
  python3 tools/wubi86-std-check.py --bundle <dir> --report /tmp/report.json --level L3

判定的规则编号与 docs/standards/wubi86/spec-1.0.md §5 对应；测试项见 conformance-1.0.md §2。
退出码：0 通过；1 未通过；2 输入不合法。
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import sys

STROKE_ROW = {'横': 'GFD', '竖': 'HJK', '撇': 'TRE', '捺': 'YUI', '折': 'NBV'}
STRUCTURE_INDEX = {'左右': 0, '上下': 1, '杂合': 2}
LEVEL_ORDER = {'L1': 1, 'L2': 2, 'L3': 3, 'L4': 4}


def read_table(path: pathlib.Path, kinds: tuple[str, ...] = ('roots', 'chars', 'shortcodes')) -> list[list[str]]:
    out = []
    for line in path.read_text(encoding='utf-8').splitlines():
        if not line or line.startswith('#'):
            continue
        out.append(line.split('\t'))
    return out


def load_bundle(directory: pathlib.Path) -> dict:
    roots: dict[str, set[str]] = {}
    for row in read_table(directory / 'roots.tsv'):
        if len(row) >= 2:
            roots.setdefault(row[0], set()).add(row[1])
    chars: dict[str, dict] = {}
    for row in read_table(directory / 'chars.tsv'):
        if len(row) < 8:
            continue
        char, code, quality, decom, keys, recognition, shorts, scoped = row[:8]
        klass = row[8] if len(row) > 8 else ('compound' if decom else 'unknown')
        chars[char] = {
            'code': code, 'quality': quality,
            'roots': [g for g in decom.split() if g],
            'keys': keys, 'recognition': recognition,
            'shorts': shorts.split('/') if shorts else ['-', '-', '-'],
            'scoped': scoped == '1', 'class': klass,
        }
    shortcodes: dict[tuple[str, int], str] = {}
    for row in read_table(directory / 'shortcodes.tsv'):
        if len(row) >= 3:
            shortcodes[(row[0], int(row[1]))] = row[2]
    return {'roots': roots, 'chars': chars, 'shortcodes': shortcodes}


def load_impl(directory: pathlib.Path) -> dict:
    """实现数据与标准同格式；只要求被判定等级需要的字段。"""
    return load_bundle(directory)


def has_pua(text: str) -> bool:
    return any(0xE000 <= ord(ch) <= 0xF8FF or ord(ch) >= 0xF0000 for ch in text)


STROKE_KEYS = set('ghtyn')


def component_class_ok(char: str, row: dict, roots: dict[str, set[str]]) -> bool:
    """R8 键名字（四同键）/ R9 成字字根（报户口 + 笔画键）。"""
    code, glyphs = row['code'], row['roots']
    if row['class'] == 'key-name':
        return len(code) == 4 and len(set(code)) == 1 and glyphs in ([char], [])
    if row['class'] == 'radical-char-exception':
        # R9e：官方特例（如 母 XGUI）——只要求报户口键对，其余位记录在 evidence 里
        allowed = roots.get(char, set())
        return glyphs in ([char], []) and bool(code) and code[0] in allowed
    if row['class'] == 'radical-char':
        if glyphs not in ([char], []) or not code:
            return False
        allowed = roots.get(char, set())
        if code[0] not in allowed:
            return False
        rest = code[1:]
        if len(rest) == 3 and rest[1:] == 'll':      # R9a 单笔画：报户口 + 首笔 + LL
            return rest[0] in STROKE_KEYS
        return all(letter in STROKE_KEYS for letter in rest)
    return True


def check(bundle: dict, impl: dict, level: int) -> dict:
    failures: list[str] = []
    compared = 0
    missing = {'partial': 0, 'unknown': 0, 'absent': 0}
    roots = bundle['roots']

    # 标准自身合法性（R1/R3/R4/R7）
    for char, row in bundle['chars'].items():
        if row['quality'] != 'full':
            continue
        for glyph in row['roots']:
            if glyph not in roots:
                failures.append(f'{char}: 标准数据里字根 {glyph} 不在字根表（R1）')
        if row['class'] != 'compound':
            # 键名字/成字字根：码不是字根序列（R2/R3 不适用），但必须自洽见 R8/R9
            if not component_class_ok(char, row, roots):
                failures.append(f'{char}: 键名字/成字字根的码与报户口规则不符（R8/R9）')
            continue
        if row['recognition']:
            if len(row['roots']) != len(row['code']) - 1:
                failures.append(f'{char}: 根数 {len(row["roots"])} ≠ 码长-1（R3）')
        elif row['roots'] and len(row['roots']) != len(row['code']):
            failures.append(f'{char}: 根数 {len(row["roots"])} ≠ 码长（R3）')

    for char, std in bundle['chars'].items():
        if not std['scoped']:
            continue
        got = impl['chars'].get(char)
        if got is None:
            missing['absent'] += 1
            continue
        if got['quality'] != 'full':
            missing[got['quality'] if got['quality'] in ('partial', 'unknown') else 'absent'] += 1
            continue
        compared += 1
        # T5 / R5：码一致
        if got['code'] != std['code']:
            failures.append(f'{char}: 码不一致 std={std["code"]} impl={got["code"]}（R5/T5）')
            continue
        # T1 / R1：字根表内
        for glyph in got['roots']:
            if glyph not in roots:
                failures.append(f'{char}: 字根 {glyph} 不在标准字根表（R1/T1）')
                break
        if got['class'] != 'compound':
            if not component_class_ok(char, got, roots):
                failures.append(f'{char}: 键名字/成字字根与报户口规则不符（R8/R9）')
            if level >= 2 and got['roots'] != std['roots']:
                failures.append(f'{char}: 根序不一致 std={" ".join(std["roots"])} impl={" ".join(got["roots"])}（L2/T8）')
            continue
        # T2 / R2：键位
        allowed = [roots.get(g, set()) for g in got['roots']]
        for index, (glyph, keys) in enumerate(zip(got['roots'], allowed)):
            if index < len(std['code']) and std['code'][index] not in keys:
                failures.append(f'{char}: 第 {index + 1} 个根 {glyph} 的键位不在 {std["code"][index]}（R2/T2）')
                break
        # T3 / R3
        want = len(std['code']) - 1 if std['recognition'] else len(std['code'])
        if len(got['roots']) != want:
            failures.append(f'{char}: 根数 {len(got["roots"])} 应为 {want}（R3/T3）')
        # T4 / R4（L4 起要求理由字段非空）
        if std['recognition']:
            letter, stroke, structure = std['recognition'].split('|')
            derived = STROKE_ROW.get(stroke, '')[STRUCTURE_INDEX.get(structure, 0):][:1]
            if derived.lower() != letter.lower():
                failures.append(f'{char}: 识别码 {letter} 与 末笔{stroke}/结构{structure} 推出的 {derived} 不符（R4/T4）')
        if level >= 4 and std['recognition'] and not got['recognition']:
            failures.append(f'{char}: L4 要求给出识别码理由，实现缺失（T9）')
        # T8 / L2：根序逐位一致
        if level >= 2 and got['roots'] != std['roots']:
            failures.append(f'{char}: 根序不一致 std={" ".join(std["roots"])} impl={" ".join(got["roots"])}（L2/T8）')
        # T6 / L3：简码槽位
        if level >= 3:
            for slot in range(3):
                want_short = std['shorts'][slot] if slot < len(std['shorts']) else '-'
                got_short = got['shorts'][slot] if slot < len(got['shorts']) else '-'
                if want_short != got_short:
                    failures.append(f'{char}: {slot + 1} 级简码 std={want_short} impl={got_short}（R6/T6）')

    return {'passed': not failures, 'level': f'L{level}', 'compared': compared,
            'failures': failures[:200], 'failureCount': len(failures), 'missing': missing}


def verify_sha(directory: pathlib.Path) -> list[str]:
    sums = directory / 'SHA256SUMS'
    if not sums.is_file():
        return ['SHA256SUMS 缺失']
    problems = []
    for line in sums.read_text(encoding='utf-8').splitlines():
        if not line.strip():
            continue
        digest, name = line.split(None, 1)
        target = directory / name.strip()
        if not target.is_file():
            problems.append(f'{name}: 缺失')
        elif hashlib.sha256(target.read_bytes()).hexdigest() != digest:
            problems.append(f'{name}: SHA-256 不符')
    return problems


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--bundle', required=True, help='标准数据包目录')
    parser.add_argument('--impl', help='实现数据目录（默认等于 --bundle，即自检）')
    parser.add_argument('--level', default='L2', choices=sorted(LEVEL_ORDER))
    parser.add_argument('--report', help='输出 JSON 报告')
    parser.add_argument('--no-verify-sha', action='store_true')
    args = parser.parse_args()

    bundle_dir = pathlib.Path(args.bundle)
    impl_dir = pathlib.Path(args.impl) if args.impl else bundle_dir
    for directory in (bundle_dir, impl_dir):
        if not (directory / 'chars.tsv').is_file():
            print(f'缺少 chars.tsv：{directory}', file=sys.stderr)
            return 2
    if not args.no_verify_sha:
        problems = verify_sha(bundle_dir)
        if problems:
            print('数据包校验失败：' + '；'.join(problems), file=sys.stderr)
            return 2

    bundle, impl = load_bundle(bundle_dir), load_impl(impl_dir)
    for name, data in (('标准', bundle), ('实现', impl)):
        for char, row in data['chars'].items():
            if has_pua(char) or any(has_pua(g) for g in row['roots']):
                print(f'{name}数据含私有区字形：{char}', file=sys.stderr)
                return 2

    result = check(bundle, impl, LEVEL_ORDER[args.level])
    payload = {'standard': 'LWS-86', 'bundle': str(bundle_dir), 'impl': str(impl_dir), **result}
    if args.report:
        pathlib.Path(args.report).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + '\n',
                                             encoding='utf-8')
    print(json.dumps({k: payload[k] for k in ('passed', 'level', 'compared', 'failureCount', 'missing')},
                     ensure_ascii=False))
    if not result['passed']:
        for failure in result['failures'][:20]:
            print('  ✗', failure)
        return 1
    print(f'✅ {args.level} 通过：比较 {result["compared"]} 字，缺失 partial {result["missing"]["partial"]}'
          f' / unknown {result["missing"]["unknown"]} / absent {result["missing"]["absent"]}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
