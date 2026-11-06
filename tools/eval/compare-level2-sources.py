#!/usr/bin/env python3
"""二级简码「选谁」的来源对照（研究用，不产出发布数据）。

问题：一个 2 字母编码下往往有多个字，二级简码只能选一个。用哪套频度选？
  来源 A：现有全码权重（WindInput，D3）——与码表同源，最保守；
  来源 B：通用字频（jieba 单字频，D10）——与码表不同源，理论上更贴近真实使用。

做法：两种来源各生成一份「核心表 + 每对 2 码一行」的临时表，跑同一批样本，
比较 jianma2（二级简码）的命中率/首选率/按键数，并列出两种来源选中不同字的码位。

用法：python3 tools/eval/compare-level2-sources.py [--samples tools/eval/samples.tsv]
输出：终端对比表 + 写入 /tmp/lampyris-level2-sources.json
"""
import argparse
import json
import subprocess
import sys
import tempfile
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / 'data/generated/wubi86-core.tsv'
PINYIN = ROOT / 'data/generated/pinyin-chars.tsv'


def load_core():
    """返回 [(code, text, weight)]，跳过注释行。"""
    rows = []
    for line in CORE.read_text(encoding='utf-8').splitlines():
        if not line or line.startswith('#'):
            continue
        parts = line.split('\t')
        if len(parts) < 3:
            continue
        code, text, weight = parts[0], parts[1], parts[2]
        rows.append((code, text, int(weight)))
    return rows


def load_char_frequency():
    """jieba 单字频：同一字可能出现在多个音节下，取最大值。"""
    freq = {}
    for line in PINYIN.read_text(encoding='utf-8').splitlines():
        if not line or line.startswith('#'):
            continue
        parts = line.split('\t')
        if len(parts) < 3 or len(parts[1]) != 1:
            continue
        weight = int(parts[2])
        if weight > freq.get(parts[1], 0):
            freq[parts[1]] = weight
    return freq


def build_groups(rows):
    """2 字母编码 → 该编码下的候选字（只看全码字，避免词组混入）。"""
    groups = defaultdict(list)
    for code, text, weight in rows:
        if len(code) == 4 and len(text) == 1:
            groups[code[:2]].append((text, weight))
    return groups


def pick(groups, char_freq, source):
    picks = {}
    for pair, items in groups.items():
        if source == 'core':
            best = max(items, key=lambda item: (item[1], -ord(item[0])))
        else:
            best = max(items, key=lambda item: (char_freq.get(item[0], 0), item[1]))
        picks[pair] = best[0]
    return picks


def write_table(rows, picks, path):
    """核心表 + 每对 2 码一行（权重沿用被选中字的来源分数，仅用于排序）。"""
    core_weight = {t: w for c, t, w in rows if len(c) == 4}
    lines = ['# code\ttext\tweight']
    lines += [f'{c}\t{t}\t{w}' for c, t, w in rows]
    for pair, text in sorted(picks.items()):
        lines.append(f'{pair}\t{text}\t{core_weight.get(text, 1)}')
    path.write_text('\n'.join(lines) + '\n', encoding='utf-8')


def evaluate(table, samples):
    out = Path(tempfile.mkdtemp(prefix='lampyris-eval-')) / 'result.json'
    cmd = ['cargo', 'run', '-q', '-p', 'ime-cli', '--bin', 'ime-eval', '--',
           '--samples', str(samples), '--table', str(table), '--json', str(out)]
    subprocess.run(cmd, cwd=ROOT, check=True)
    return json.loads(out.read_text(encoding='utf-8'))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--samples', default=str(ROOT / 'tools/eval/samples.tsv'))
    args = parser.parse_args()
    samples = Path(args.samples)

    rows = load_core()
    char_freq = load_char_frequency()
    groups = build_groups(rows)
    picks_core = pick(groups, char_freq, 'core')
    picks_freq = pick(groups, char_freq, 'freq')

    differing = sorted(pair for pair in picks_core if picks_core[pair] != picks_freq[pair])

    tmp = Path(tempfile.mkdtemp(prefix='lampyris-level2-'))
    table_core = tmp / 'core.tsv'
    table_freq = tmp / 'freq.tsv'
    write_table(rows, picks_core, table_core)
    write_table(rows, picks_freq, table_freq)

    base = evaluate(CORE, samples)
    res_core = evaluate(table_core, samples)
    res_freq = evaluate(table_freq, samples)

    def rate(result, category):
        """ime-eval 的 categories/overall 是计数，不是百分比。"""
        block = result['overall'] if category == 'ALL' else result['categories'][category]
        samples = block['samples'] or 1
        return {
            'hit': block['hits'] / samples * 100,
            'firstChoice': block['firstChoice'] / samples * 100,
            'meanPosition': block['meanPosition'],
            'meanKeystrokes': block['meanKeystrokes'],
        }

    def variant(name, result):
        return {'name': name, 'jianma2': rate(result, 'jianma2'), 'ALL': rate(result, 'ALL')}

    summary = {
        'pairs': len(picks_core),
        'differing_pairs': len(differing),
        'differing_examples': [
            {'pair': p, 'core_pick': picks_core[p], 'freq_pick': picks_freq[p]}
            for p in differing[:20]
        ],
        'variants': [variant('base（无二级简码）', base),
                     variant('A：全码权重选字', res_core),
                     variant('B：通用字频选字', res_freq)],
    }
    out = Path('/tmp/lampyris-level2-sources.json')
    out.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')

    print(f'2 码码位：{summary["pairs"]}，两种来源选字不同：{summary["differing_pairs"]}')
    print(f'{"变体":22} {"jianma2 hit%":>13} {"first%":>8} {"avgPos":>7} {"keys":>6}   {"ALL first%":>11} {"ALL keys":>9}')
    for variant in summary['variants']:
        j, a = variant['jianma2'], variant['ALL']
        print(f'{variant["name"]:22} {j["hit"]:13.1f} {j["firstChoice"]:8.1f} '
              f'{j["meanPosition"]:7.2f} {j["meanKeystrokes"]:6.2f}   {a["firstChoice"]:11.1f} {a["meanKeystrokes"]:9.2f}')
    print()
    print('选字不同的前 12 个码位（core → freq）：')
    for item in summary['differing_examples'][:12]:
        print(f'  {item["pair"]}  {item["core_pick"]} → {item["freq_pick"]}')
    print(f'\n明细：{out}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
