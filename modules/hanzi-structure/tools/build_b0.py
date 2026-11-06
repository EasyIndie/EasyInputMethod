#!/usr/bin/env python3
"""生成 B0 结构事实库（试点 1,000 高频字）。

按 ADR-189：所有输入输出都从命令行显式给出，脚本不假设主仓库路径、不向上遍历。
数据全部来自主项目**已登记**的来源（D1/D2/D5/D10/D17/D17-bis），不引入新来源。

用法：
  python3 tools/build_b0.py \
    --codes data/generated/wubi86-single.tsv \
    --radicals data/sources/wubi-lex-86.txt \
    --short1 data/sources/wubi86-level1-codes.tsv \
    --short2 data/sources/wubi86-level2-codes.tsv \
    --pinyin data/generated/pinyin-chars.tsv \
    --limit 1000 \
    --out-dir corpus
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

SCHEMA_VERSION = 2  # v2：新增 componentsSource；组件可由 D3 经 PUA 解码得到

# 识别码反查表：末笔 × 结构（顺序：左右、上下、杂合）
RECOGNITION = {
    'g': ('横', '左右'), 'f': ('横', '上下'), 'd': ('横', '杂合'),
    'h': ('竖', '左右'), 'j': ('竖', '上下'), 'k': ('竖', '杂合'),
    't': ('撇', '左右'), 'r': ('撇', '上下'), 'e': ('撇', '杂合'),
    'y': ('捺', '左右'), 'u': ('捺', '上下'), 'i': ('捺', '杂合'),
    'n': ('折', '左右'), 'b': ('折', '上下'), 'v': ('折', '杂合'),
}
# 单笔画可读字形（D2 的成字字根后续字形）
# 注意：'〇' 在 D2 里是占位字形（不是笔画），不能算进首/次/末笔
STROKES = {'一': '横', '丨': '竖', '丿': '撇', '丶': '捺', '乙': '折', '乛': '折', '亅': '竖'}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_rows(path: Path, min_fields: int = 2):
    for line in path.read_text(encoding='utf-8').splitlines():
        if not line or line.startswith('#'):
            continue
        parts = line.split('\t')
        if len(parts) >= min_fields:
            yield parts


def load_full_codes(path: Path) -> dict[str, str]:
    codes: dict[str, str] = {}
    for parts in read_rows(path):
        code, text = parts[0], parts[1]
        if len(text) == 1 and len(code) > len(codes.get(text, '')):
            codes[text] = code
    return codes


def load_radicals(path: Path) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    for line in path.read_text(encoding='utf-8').splitlines():
        if not line.strip():
            continue
        parts = line.rstrip('\n').split('\t')
        if len(parts) >= 2:
            out[parts[0]] = list(parts[1])
    return out


def load_pua_map(path: Path) -> dict[str, str]:
    data = json.loads(path.read_text(encoding='utf-8'))
    return {pua: info['readable'] for pua, info in data.get('map', {}).items()}


def load_short(path: Path, width: int) -> dict[str, str]:
    out: dict[str, str] = {}
    for parts in read_rows(path):
        code, text = parts[0], parts[1]
        if len(code) == width and len(text) == 1:
            out[text] = code
    return out


def load_pinyin_and_freq(path: Path) -> tuple[dict[str, str], dict[str, int]]:
    pinyin: dict[str, str] = {}
    freq: dict[str, int] = {}
    for parts in read_rows(path, 3):
        syllable, text, weight = parts[0], parts[1], parts[2]
        if len(text) != 1:
            continue
        try:
            value = int(weight)
        except ValueError:
            continue
        if value > freq.get(text, 0):
            freq[text] = value
            pinyin[text] = syllable
    return pinyin, freq


def decode(glyphs: list[str], pua_map: dict[str, str]) -> tuple[list[str], int]:
    """把一组字形解码成可读形式；返回 (字形, 无法解码的数量)。

    补充区私有码位（D2 用它表示识别码字形）直接丢弃；BMP 私有区字形（D3 的字根）
    先查映射，查不到就原样保留并计入"无法解码"。
    """
    out, unknown = [], 0
    for g in glyphs:
        if ord(g) >= 0xF0000:
            continue
        if 0xE000 <= ord(g) <= 0xF8FF:
            readable = pua_map.get(g)
            if readable:
                out.append(readable)
            else:
                # 解不出来就**丢弃**（ADR-189 不许产物含 PUA），并计一次未知
                unknown += 1
        else:
            out.append(g)
    return out, unknown


def build(char: str, code: str, glyphs: list[str], short1: dict, short2: dict,
          pinyin: dict, freq: dict, pua_map: dict[str, str] | None = None,
          d3_glyphs: list[str] | None = None) -> dict:
    pua_map = pua_map or {}
    notes: list[str] = []

    def candidates() -> list[tuple[str, list[str], int]]:
        out = []
        if d3_glyphs:
            decoded, unknown = decode(d3_glyphs, pua_map)
            if decoded:
                out.append(('D3', decoded, unknown))
        decoded2, unknown2 = decode(glyphs, pua_map)
        if decoded2:
            out.append(('D2', decoded2, unknown2))
        return out

    def fits(components: list[str]) -> bool:
        n = len(components)
        return n >= 2 and len(code) in (n, n + 1)

    # 选择顺序：D2 优先（报告 241：D3 的组件序列常混入识别码/笔画字形，直接采用反而更差），
    # D3 只在 D2 缺失或对不上码长时兜底。
    pool = candidates()
    pool.sort(key=lambda c: 0 if c[0] == 'D2' else 1)
    pick = (next((c for c in pool if fits(c[1]) and c[2] == 0), None)
            or next((c for c in pool if fits(c[1])), None)
            or (pool[0] if pool else None))
    source, readable, unknown_glyphs = pick if pick else (None, [], 0)

    entry = {
        'char': char,
        'code': code,
        'class': None,
        'componentsSource': source,
        'components': [],
        'keys': [],
        'recognition': None,
        'short1': short1.get(char),
        'short2': short2.get(char),
        'pinyin': pinyin.get(char),
        'frequency': freq.get(char, 0),
        'quality': 'unknown',
        'notes': notes,
    }
    if unknown_glyphs:
        notes.append(f'有 {unknown_glyphs} 个字形无法解码，组件序列可能不完整')

    # 1) 键名字：四位同键
    if len(code) == 4 and len(set(code)) == 1:
        entry['class'] = 'key-name'
        entry['components'] = [char]
        entry['quality'] = 'full'
        return entry

    # 2) 成字字根：D2 字形首位是它自己，后续是笔画
    if glyphs and glyphs[0] == char:
        entry['class'] = 'radical-char'
        entry['components'] = [char]
        strokes = [g for g in readable[1:] if g in STROKES] if readable and readable[0] == char else []
        if strokes and len(strokes) == len(readable) - 1:
            notes.append('成字字根：报户口 + ' + '、'.join(STROKES[g] + '（' + g + '）' for g in strokes))
            entry['quality'] = 'partial' if unknown_glyphs else 'full'
        else:
            notes.append('成字字根：笔画字形不完整，无法给出首/次/末笔依据')
            entry['quality'] = 'partial'
        return entry

    # 3) 合体字
    if not readable:
        notes.append('缺可读拆字（PUA 解码失败）')
        return entry
    entry['class'] = 'compound'
    entry['components'] = readable
    n = len(readable)
    # 每个字根对应全码里的同位置字母（n ≤ 4 时成立，识别码在末尾）
    entry['keys'] = list(code[:n]) if n <= len(code) else []
    if n >= 2 and len(code) == n + 1 and code[-1] in RECOGNITION:
        stroke, structure = RECOGNITION[code[-1]]
        entry['recognition'] = {
            'key': code[-1],
            'stroke': stroke,
            'structure': structure,
            'because': f'{n} 个字根不足四码：末笔{stroke} + 结构{structure} ⇒ 识别码 {code[-1]}',
        }
        entry['quality'] = 'partial' if unknown_glyphs else 'full'
    elif n >= 2 and len(code) == n:
        notes.append('字根已够四码，无识别码')
        entry['quality'] = 'partial' if unknown_glyphs else 'full'
    else:
        notes.append(f'字根数 {n} 与码长 {len(code)} 对不上，无法判定识别码')
        entry['quality'] = 'partial'
    return entry


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--codes', required=True)
    parser.add_argument('--radicals', required=True)
    parser.add_argument('--d3', help='D3 拆字（可选，配合 --pua-map 提高覆盖率）')
    parser.add_argument('--pua-map', help='PUA→可读字根映射（tools/decode_pua.py 生成）')
    parser.add_argument('--short1', required=True)
    parser.add_argument('--short2', required=True)
    parser.add_argument('--pinyin', required=True)
    parser.add_argument('--limit', type=int, default=1000)
    parser.add_argument('--out-dir', required=True)
    args = parser.parse_args()

    paths = {name: Path(getattr(args, name)) for name in ('codes', 'radicals', 'short1', 'short2', 'pinyin')}
    if args.d3:
        paths['d3'] = Path(args.d3)
    for name, path in paths.items():
        if not path.is_file():
            print(f'缺少输入文件 --{name} {path}', file=sys.stderr)
            return 2

    codes = load_full_codes(paths['codes'])
    radicals = load_radicals(paths['radicals'])
    short1 = load_short(paths['short1'], 1)
    short2 = load_short(paths['short2'], 2)
    pinyin, freq = load_pinyin_and_freq(paths['pinyin'])
    pua_map = load_pua_map(Path(args.pua_map)) if args.pua_map else {}
    d3 = load_radicals(Path(args.d3)) if args.d3 else {}

    ranked = sorted(freq.items(), key=lambda kv: (-kv[1], kv[0]))[: args.limit]
    entries = []
    for char, _weight in ranked:
        code = codes.get(char)
        if not code:
            entries.append({'char': char, 'code': None, 'class': None, 'components': [],
                            'recognition': None, 'short1': short1.get(char), 'short2': short2.get(char),
                            'pinyin': pinyin.get(char), 'frequency': freq.get(char, 0),
                            'quality': 'unknown', 'notes': ['缺全码']})
            continue
        glyphs = radicals.get(char)
        if not glyphs:
            entries.append({'char': char, 'code': code, 'class': None, 'componentsSource': None,
                            'components': [], 'keys': [], 'recognition': None,
                            'short1': short1.get(char), 'short2': short2.get(char),
                            'pinyin': pinyin.get(char), 'frequency': freq.get(char, 0),
                            'quality': 'unknown', 'notes': ['缺拆字数据']})
            continue
        entries.append(build(char, code, glyphs, short1, short2, pinyin, freq,
                             pua_map=pua_map, d3_glyphs=d3.get(char)))

    entries.sort(key=lambda e: (-e['frequency'], e['char']))
    stats: dict[str, int] = {}
    for entry in entries:
        stats[entry['quality']] = stats.get(entry['quality'], 0) + 1
        stats[f'class:{entry["class"]}'] = stats.get(f'class:{entry["class"]}', 0) + 1
        if entry['recognition']:
            stats['recognition'] = stats.get('recognition', 0) + 1
        if entry.get('componentsSource'):
            stats[f"source:{entry['componentsSource']}"] = stats.get(f"source:{entry['componentsSource']}", 0) + 1

    report = {
        'schemaVersion': SCHEMA_VERSION,
        'entries': len(entries),
        'quality': {'full': stats.get('full', 0), 'partial': stats.get('partial', 0),
                    'unknown': stats.get('unknown', 0)},
        'classes': {k.split(':', 1)[1]: v for k, v in stats.items() if k.startswith('class:')},
        'withRecognition': stats.get('recognition', 0),
        'componentsSource': {k.split(':', 1)[1]: v for k, v in stats.items() if k.startswith('source:')},
        'puaMap': str(args.pua_map) if args.pua_map else None,
        'undecodedPuaEntries': sum(1 for e in entries if any('无法解码' in n for n in e['notes'])),
        'inputs': {name: {'path': str(path), 'sha256': sha256(path)} for name, path in paths.items()},
        'generator': 'modules/hanzi-structure/tools/build_b0.py',
        'command': ' '.join(['python3', 'tools/build_b0.py'] + sys.argv[1:]),
    }

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / 'B0.json').write_text(json.dumps(entries, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    (out_dir / 'B0-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'写入 {out_dir}/B0.json（{len(entries)} 条）')
    print(json.dumps(report['quality'], ensure_ascii=False), '识别码可解释:', report['withRecognition'])
    return 0


if __name__ == '__main__':
    sys.exit(main())
