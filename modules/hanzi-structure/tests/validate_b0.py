#!/usr/bin/env python3
"""独立复核 B0 产物：不信任生成器，按输入文件重算并逐条比对。

用法：
  python3 tests/validate_b0.py --corpus corpus/B0.json --report corpus/B0-report.json \
    --codes <...> --radicals <...> --short1 <...> --short2 <...> --pinyin <...>
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

SCHEMA_VERSION = 2  # v2：componentsSource / keys（报告 241）
FIELDS = {'char', 'code', 'class', 'componentsSource', 'components', 'keys', 'recognition',
          'short1', 'short2', 'pinyin', 'frequency', 'quality', 'notes'}
CLASSES = {'key-name', 'radical-char', 'compound', None}
QUALITIES = {'full', 'partial', 'unknown'}
RECOGNITION = {
    'g': ('横', '左右'), 'f': ('横', '上下'), 'd': ('横', '杂合'),
    'h': ('竖', '左右'), 'j': ('竖', '上下'), 'k': ('竖', '杂合'),
    't': ('撇', '左右'), 'r': ('撇', '上下'), 'e': ('撇', '杂合'),
    'y': ('捺', '左右'), 'u': ('捺', '上下'), 'i': ('捺', '杂合'),
    'n': ('折', '左右'), 'b': ('折', '上下'), 'v': ('折', '杂合'),
}


def rows(path: Path, minimum: int = 2):
    for line in path.read_text(encoding='utf-8').splitlines():
        if not line or line.startswith('#'):
            continue
        parts = line.split('\t')
        if len(parts) >= minimum:
            yield parts


def main() -> int:
    parser = argparse.ArgumentParser()
    for flag in ('corpus', 'report', 'codes', 'radicals', 'short1', 'short2', 'pinyin'):
        parser.add_argument(f'--{flag}', required=True)
    args = parser.parse_args()

    entries = json.loads(Path(args.corpus).read_text(encoding='utf-8'))
    report = json.loads(Path(args.report).read_text(encoding='utf-8'))
    problems: list[str] = []

    if not isinstance(entries, list) or not entries:
        print('❌ B0.json 不是非空数组')
        return 1
    if report.get('schemaVersion') != SCHEMA_VERSION:
        problems.append(f"报告 schemaVersion 应为 {SCHEMA_VERSION}，实际 {report.get('schemaVersion')}")
    if report.get('entries') != len(entries):
        problems.append(f'报告条目数 {report.get("entries")} 与数据 {len(entries)} 不符')

    codes: dict[str, str] = {}
    for parts in rows(Path(args.codes)):
        code, text = parts[0], parts[1]
        if len(text) == 1 and len(code) > len(codes.get(text, '')):
            codes[text] = code
    short1 = {}
    for parts in rows(Path(args.short1)):
        if len(parts[0]) == 1 and len(parts[1]) == 1:
            short1[parts[1]] = parts[0]
    short2 = {}
    for parts in rows(Path(args.short2)):
        if len(parts[0]) == 2 and len(parts[1]) == 1:
            short2[parts[1]] = parts[0]
    radicals: dict[str, list[str]] = {}
    for line in Path(args.radicals).read_text(encoding='utf-8').splitlines():
        if not line.strip():
            continue
        parts = line.rstrip('\n').split('\t')
        if len(parts) >= 2:
            radicals[parts[0]] = list(parts[1])

    seen: set[str] = set()
    for entry in entries:
        char = entry.get('char', '?')
        if set(entry) != FIELDS:
            problems.append(f'{char}: 字段集合不符 {sorted(set(entry) ^ FIELDS)}')
            continue
        if char in seen:
            problems.append(f'{char}: 重复条目')
        seen.add(char)
        if entry['class'] not in CLASSES:
            problems.append(f'{char}: class 非法 {entry["class"]}')
        if entry['quality'] not in QUALITIES:
            problems.append(f'{char}: quality 非法 {entry["quality"]}')
        if entry['code'] and codes.get(char) != entry['code']:
            problems.append(f'{char}: 全码与输入表不一致 {entry["code"]} != {codes.get(char)}')
        if entry['short1'] != short1.get(char):
            problems.append(f'{char}: 一级简码不一致')
        if entry['short2'] != short2.get(char):
            problems.append(f'{char}: 二级简码不一致')
        text = json.dumps(entry, ensure_ascii=False)
        # 两种 PUA 都要拦：BMP（U+E000–U+F8FF）与补充区（≥U+F0000）
        pua = [ch for ch in text if 0xE000 <= ord(ch) <= 0xF8FF or ord(ch) >= 0xF0000]
        if pua:
            problems.append(f'{char}: 产物含私有区字形 {[hex(ord(c)) for c in pua][:3]}（ADR-189 不允许）')
        if entry['class'] == 'compound' and len(entry['keys']) != len(entry['components']):
            problems.append(f'{char}: keys 与 components 数量不一致')
        if entry['quality'] != 'full' and not entry['notes']:
            problems.append(f'{char}: 非 full 等级必须写 notes')
        recognition = entry['recognition']
        if recognition:
            key = recognition.get('key')
            if key not in RECOGNITION:
                problems.append(f'{char}: 识别码字母非法 {key}')
            elif (recognition.get('stroke'), recognition.get('structure')) != RECOGNITION[key]:
                problems.append(f'{char}: 识别码的末笔/结构与字母不符')
            if not entry['code'] or entry['code'][-1] != key:
                problems.append(f'{char}: 识别码不是全码末位')

    if problems:
        for problem in problems[:20]:
            print('❌', problem)
        print(f'共 {len(problems)} 处问题')
        return 1
    print(f'✅ B0 校验通过：{len(entries)} 条，字段/等级/简码/全码/识别码一致，无私有区字形')
    return 0


if __name__ == '__main__':
    sys.exit(main())
