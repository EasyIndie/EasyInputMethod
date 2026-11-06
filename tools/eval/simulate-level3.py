#!/usr/bin/env python3
"""三级简码收益评估（报告 239，研究用，不产出发布数据）。

背景：官方三级简码是**表**（约 4,400 字），不是"任何四码字都能 3 码上屏"的规则。
本脚本用"高频前 N 个四码字"模拟这张表，量化两件事：
  1. 若能 3 码 + 空格上屏，按键数能省多少（`jianma3` 类别）；
  2. 代价：与既有 3 码全码字（如 式=aad）撞码的数量，以及新表体积。

用法：python3 tools/eval/simulate-level3.py [--limit 4400] [--samples tools/eval/samples.tsv]
"""
import argparse
import collections
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / 'data/generated/wubi86-core.tsv'
CHAR_FREQ = ROOT / 'data/generated/pinyin-chars.tsv'


def load_core():
    rows = []
    for line in CORE.read_text(encoding='utf-8').splitlines():
        if not line or line.startswith('#'):
            continue
        parts = line.split('\t')
        if len(parts) >= 3:
            rows.append((parts[0], parts[1], int(parts[2])))
    return rows


def char_frequency():
    freq = {}
    for line in CHAR_FREQ.read_text(encoding='utf-8').splitlines():
        if not line or line.startswith('#'):
            continue
        parts = line.split('\t')
        if len(parts) == 3 and len(parts[1]) == 1:
            freq[parts[1]] = max(freq.get(parts[1], 0), int(parts[2]))
    return freq


def evaluate(table: Path, samples: Path):
    out = Path(tempfile.mkdtemp(prefix='lampyris-l3-')) / 'result.json'
    subprocess.run(['cargo', 'run', '-q', '-p', 'ime-cli', '--bin', 'ime-eval', '--',
                    '--samples', str(samples), '--table', str(table), '--json', str(out)],
                   cwd=ROOT, check=True)
    return json.loads(out.read_text(encoding='utf-8'))


def rate(result, category):
    block = result['overall'] if category == 'ALL' else result['categories'].get(category)
    if not block:
        return None
    n = block['samples'] or 1
    return {
        'hit': block['hits'] / n * 100,
        'first': block['firstChoice'] / n * 100,
        'pos': block['meanPosition'],
        'keys': block['meanKeystrokes'],
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--limit', type=int, default=4400, help='模拟的三级简码字数（官方约 4400）')
    parser.add_argument('--samples', default=str(ROOT / 'tools/eval/samples.tsv'))
    args = parser.parse_args()

    rows = load_core()
    freq = char_frequency()
    full = {}
    for code, text, weight in rows:
        if len(code) == 4 and len(text) == 1:
            if text not in full or weight > full[text][1]:
                full[text] = (code, weight)
    existing_three = {code for code, text, _ in rows if len(code) == 3}
    by_code = collections.defaultdict(int)
    for code, text, _ in rows:
        if len(text) == 1:
            by_code[code] += 1

    # 模拟"三级简码表"：按字频降序取前 limit 个四码字
    candidates = sorted(full.items(), key=lambda kv: (-freq.get(kv[0], 0), kv[0]))[: args.limit]
    simulated = []
    collisions = 0
    save_one_key = 0
    for char, (code, weight) in candidates:
        prefix = code[:3]
        if prefix in existing_three:
            collisions += 1
        if by_code.get(code, 0) > 1:  # 四码重码：当前要 4 码 + 选字，简码可省 1 键
            save_one_key += 1
        simulated.append((prefix, char, weight))

    tmp = Path(tempfile.mkdtemp(prefix='lampyris-l3-table-'))
    table = tmp / 'with-level3.tsv'
    lines = ['# code\ttext\tweight'] + [f'{c}\t{t}\t{w}' for c, t, w in rows]
    lines += [f'{c}\t{t}\t{w}' for c, t, w in simulated]
    table.write_text('\n'.join(lines) + '\n', encoding='utf-8')

    base = evaluate(CORE, Path(args.samples))
    after = evaluate(table, Path(args.samples))

    summary = {
        'limit': args.limit,
        'simulated_rows': len(simulated),
        'collisions_with_full_three_code_chars': collisions,
        'chars_that_actually_save_a_key': save_one_key,
        'size_delta_kb': round((table.stat().st_size - CORE.stat().st_size) / 1024, 1),
        'categories': {},
    }
    for category in ('jianma3', 'single', 'jianma2', 'prefix2', 'word2', 'ALL'):
        before, now = rate(base, category), rate(after, category)
        if before and now:
            summary['categories'][category] = {'before': before, 'after': now}

    out = Path('/tmp/lampyris-level3-eval.json')
    out.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')

    print(f'模拟三级简码：{len(simulated)} 条（limit={args.limit}）')
    print(f'  与既有 3 码全码字撞码：{collisions}')
    print(f'  其中真正能省 1 键的（四码重码字）：{save_one_key}（{save_one_key / len(simulated) * 100:.1f}%）')
    print(f'  表体积增加：{summary["size_delta_kb"]} KB')
    print()
    print(f'{"类别":10} {"命中%":>7} {"首选%":>7} {"位次":>6} {"按键":>6}   →   {"命中%":>7} {"首选%":>7} {"位次":>6} {"按键":>6}')
    for category, values in summary['categories'].items():
        b, a = values['before'], values['after']
        print(f'{category:10} {b["hit"]:7.1f} {b["first"]:7.1f} {b["pos"]:6.2f} {b["keys"]:6.2f}   →   '
              f'{a["hit"]:7.1f} {a["first"]:7.1f} {a["pos"]:6.2f} {a["keys"]:6.2f}')
    print(f'\n明细：{out}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
