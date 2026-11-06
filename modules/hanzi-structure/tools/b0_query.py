#!/usr/bin/env python3
"""查一个字在 B0 里的可展示解释（消费契约的参考实现，报告 241 方案 A）。

用法：python3 tools/b0_query.py 和 [--corpus corpus/B0.json]
      python3 tools/b0_query.py 和 --json      # 输出结构化结果

展示规则（见 spec/B0-schema.md §6）：
  full    → 编码 + 字根 + 键位 + 识别码依据 + 简码 + 读音
  partial → 编码 + 简码 + 读音 + 「拆解待核验」（识别码若存在标「参考」）
  unknown → 只说明缺资料
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def explain(entry: dict, as_json: bool) -> int:
    if entry is None:
        print('未收录', file=sys.stderr)
        return 1
    char = entry['char']
    quality = entry['quality']
    result = {'char': char, 'quality': quality, 'code': entry['code'], 'text': ''}

    if quality == 'unknown':
        result['text'] = f'{char}：暂无编码/拆解资料'
    elif quality == 'partial':
        parts = [f'{char} 「{entry["code"]}」'] if entry['code'] else [char]
        if entry.get('ids'):
            parts.append(f'IDS {entry["ids"]}（{entry["idsStructure"]}，参考）')
        if entry['short1']:
            parts.append(f'一级简码 {entry["short1"]}')
        if entry['short2']:
            parts.append(f'二级简码 {entry["short2"]}')
        if entry['pinyin']:
            parts.append(f'读音 {entry["pinyin"]}')
        if entry['components'] and entry['keys']:
            parts.append('字根：' + ' '.join(f'{c if c else "？"}({k})'
                                            for c, k in zip(entry['components'], entry['keys'])))
        if entry.get('ids'):
            parts.append(f'IDS {entry["ids"]}（{entry["idsStructure"]}，参考）')
        parts.append('拆解待核验（' + '；'.join(entry['notes'] or ['数据不完整']) + '）')
        if entry['recognition']:
            parts.append(f'参考识别码 {entry["recognition"]["key"]}')
        result['text'] = '｜'.join(parts)
    else:
        parts = [f'{char} 「{entry["code"]}」']
        if entry['class'] == 'key-name':
            parts.append('键名字：连打该键四次')
        elif entry['class'] == 'radical-char':
            if entry.get('strokes'):
                parts.append('成字字根（' + ''.join(entry['strokes']) + '）')
            note = entry['notes'][0] if entry['notes'] else '报户口 + 笔画'
            note = note.split('：', 1)[1] if note.startswith('成字字根：') else note
            parts.append(note)
        else:
            components = ' '.join(f'{c if c else "？"}({k})'
                                  for c, k in zip(entry['components'], entry['keys']))
            parts.append('字根：' + components)
            recognition = entry['recognition']
            if recognition:
                parts.append(recognition['because'])
            else:
                parts.append('字根已够四码，无识别码')
        if entry['short1']:
            parts.append(f'一级简码 {entry["short1"]}')
        if entry['short2']:
            parts.append(f'二级简码 {entry["short2"]}')
        if entry['pinyin']:
            parts.append(f'读音 {entry["pinyin"]}')
        result['text'] = '｜'.join(parts)

    if as_json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(result['text'])
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('char')
    parser.add_argument('--corpus', default=str(Path(__file__).resolve().parents[1] / 'corpus/B0.json'))
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args()
    entries = {e['char']: e for e in json.loads(Path(args.corpus).read_text(encoding='utf-8'))}
    return explain(entries.get(args.char), args.json)


if __name__ == '__main__':
    sys.exit(main())
