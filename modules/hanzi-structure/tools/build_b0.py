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

SCHEMA_VERSION = 5  # v5：引入 IDS（D19）填占位字根并给结构参考（报告 245）

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
# 笔画键 ↔ 名称 ↔ 规范字形（成字字根取码用；这是"取码笔顺"，不是笔顺教学数据）
STROKE_KEY = {'g': '横', 'h': '竖', 't': '撇', 'y': '捺', 'n': '折'}
STROKE_GLYPH = {'g': '一', 'h': '丨', 't': '丿', 'y': '丶', 'n': '乙'}
STROKE_NAME = {'g': '横', 'h': '竖', 't': '撇', 'y': '捺', 'n': '折'}
RECOGNITION_KEYS = set(RECOGNITION)


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
    """D2（wubi-lex）：字根**连写**在第二列，逐字符取；容忍 BOM。"""
    out: dict[str, list[str]] = {}
    for line in path.read_text(encoding='utf-8').splitlines():
        line = line.lstrip('\ufeff').rstrip('\r')
        if not line.strip():
            continue
        parts = line.split('\t')
        if len(parts) >= 2:
            out[parts[0]] = [g for g in parts[1] if not g.isspace()]
    return out


def load_d3(path: Path) -> dict[str, list[str]]:
    """D3（WindInput）：第二列是**空格分隔**的字根，必须 split()；U+E000 是空位占位。"""
    out: dict[str, list[str]] = {}
    for line in path.read_text(encoding='utf-8').splitlines():
        line = line.lstrip('\ufeff').rstrip('\r')
        if not line.strip() or line.startswith('#'):
            continue
        parts = line.split('\t')
        if len(parts) >= 2:
            glyphs = [g for g in parts[1].split() if g != '\ue000']
            if glyphs:
                out[parts[0]] = glyphs
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


def decode(glyphs: list[str], pua_map: dict[str, str],
           drop_tail_pua: bool = False) -> tuple[list[str | None], int]:
    """把一组字形解码成可读字形；解不出的 BMP 私有区字形变成占位组件 None。

    补充区私有码位（D2 用它表示识别码字形）直接丢弃；BMP 私有区字形（D2/D3 的字根）
    先查映射，查不到就记一个占位（v3）：位置仍在，键位可由码位推断，但字形不进入产物。
    """
    out: list[str | None] = []
    unknown = 0
    last = len(glyphs) - 1
    for index, g in enumerate(glyphs):
        if drop_tail_pua and index == last and is_pua(g):
            continue  # 末位私有区字形 = 识别码槽，不是字根
        if ord(g) >= 0xF0000:
            out.append(None)  # 其余私有区字形是"无法渲染的字根"，保留占位
            unknown += 1
            continue
        if 0xE000 <= ord(g) <= 0xF8FF:
            readable = pua_map.get(g)
            if readable:
                out.append(readable)
            else:
                out.append(None)  # 占位：不许把 PUA 写进产物
                unknown += 1
        else:
            out.append(g)
    return out, unknown


IDS_OPS = set('⿰⿱⿲⿳⿴⿵⿶⿷⿸⿹⿺⿻')


def load_ids(path: Path) -> dict[str, str]:
    """读 IDS 分解（D19，MIT）：字 -> 主 IDS 序列（取第一条以结构算子开头的）。"""
    out: dict[str, str] = {}
    for line in path.read_text(encoding='utf-8').splitlines():
        parts = line.split('\t')
        if len(parts) < 2:
            continue
        for seq in parts[1].split(';'):
            seq = seq.split('(')[0].strip()
            if seq and seq[0] in IDS_OPS:
                out[parts[0]] = seq
                break
    return out


def ids_leaves(seq: str) -> list[str]:
    """IDS 的叶子（分量）序列；结构算子本身不是分量。"""
    return [c for c in seq if c not in IDS_OPS]


def ids_structure(seq: str) -> str | None:
    """IDS 根算子 → 三分类结构（左右/上下/杂合）。注意这是 IDS 口径，不是五笔口径。"""
    if not seq:
        return None
    root = seq[0]
    if root in '⿰⿲':
        return '左右'
    if root in '⿱⿳':
        return '上下'
    if root in '⿴⿵⿶⿷⿸⿹⿺⿻':
        return '杂合'
    return None


def fill_placeholders(components: list, keys: list[str], seq: str,
                      keymap: dict[str, str]) -> tuple[list, int]:
    """用 IDS 叶子填占位字根：只在"位数相同 + 已知位一致 + 键位对得上"时才填。

    返回 (新组件, 填入数量)。宁可不填，也不猜（ADR-309）。
    """
    leaves = ids_leaves(seq)
    if not leaves or len(leaves) != len(components):
        return components, 0
    for leaf, current, key in zip(leaves, components, keys):
        if leaf in IDS_OPS or not leaf.strip():
            return components, 0
        if 0xE000 <= ord(leaf) <= 0xF8FF or ord(leaf) >= 0xF0000:
            return components, 0
        if current is not None:
            if current == leaf:
                continue
            if keymap.get(current) == keymap.get(leaf) and keymap.get(leaf) is not None:
                continue
            return components, 0
        if leaf in keymap and keymap[leaf] != key:
            return components, 0
    filled = sum(1 for current, leaf in zip(components, leaves) if current is None)
    return list(leaves), filled


def recognition_slot_pua(d2: dict[str, list[str]], codes: dict[str, str]) -> set[str]:
    """学出"只出现在末位"的私有区字形——它们是识别码字形，不是一个字根。

    判据：D2 序列与全码等长时，某私有区字形从未出现在非末位。这是数据自身的规律，
    不引入外部来源（报告 244）。
    """
    last: set[str] = set()
    elsewhere: set[str] = set()
    for char, glyphs in d2.items():
        code = codes.get(char)
        if not code or len(glyphs) != len(code) or len(code) < 3:
            continue
        for index, glyph in enumerate(glyphs):
            if not is_pua(glyph):
                continue
            (last if index == len(glyphs) - 1 else elsewhere).add(glyph)
    return last - elsewhere


def is_pua(glyph: str) -> bool:
    return 0xE000 <= ord(glyph) <= 0xF8FF or ord(glyph) >= 0xF0000


def build(char: str, code: str, glyphs: list[str], short1: dict, short2: dict,
          pinyin: dict, freq: dict, pua_map: dict[str, str] | None = None,
          d3_glyphs: list[str] | None = None, rec_slot_pua: set[str] | None = None,
          readable_keys: dict[str, str] | None = None,
          ids: dict[str, str] | None = None) -> dict:
    pua_map = pua_map or {}
    rec_slot_pua = rec_slot_pua or set()
    readable_keys = readable_keys or {}
    ids = ids or {}
    notes: list[str] = []

    def fits(components: list) -> bool:
        n = len(components)
        return n >= 2 and len(code) in (n, n + 1)

    entry = {
        'char': char,
        'code': code,
        'class': None,
        'componentsSource': None,
        'components': [],
        'keys': [],
        'strokes': None,
        'ids': ids.get(char),
        'idsStructure': ids_structure(ids.get(char, '')),
        'positionMismatch': [],
        'recognition': None,
        'short1': short1.get(char),
        'short2': short2.get(char),
        'pinyin': pinyin.get(char),
        'frequency': freq.get(char, 0),
        'quality': 'unknown',
        'notes': notes,
    }

    # 1) 键名字：四位同键
    if len(code) == 4 and len(set(code)) == 1:
        entry['class'] = 'key-name'
        entry['components'] = [char]
        entry['quality'] = 'full'
        return entry

    # 2) 成字字根：D2 首位是它自己；笔画优先由全码推导（报户口 + 首/次/末笔）
    if glyphs and glyphs[0] == char:
        entry['class'] = 'radical-char'
        entry['components'] = [char]
        key = readable_keys.get(char)
        if key and len(code) == 4 and code[:2] == key * 2 and code[2:] == 'll':
            entry['componentsSource'] = 'D1'
            notes.append(f'单笔画：连打所在键 {key.upper()} 两次，再补 LL')
            entry['quality'] = 'full'
            return entry
        if key and len(code) in (3, 4) and code[0] == key and all(c in STROKE_KEY for c in code[1:]):
            letters = code[1:]
            entry['strokes'] = [STROKE_GLYPH[c] for c in letters]
            entry['keys'] = [key, *letters]
            names = ['首笔', '次笔', '末笔'] if len(letters) == 3 else ['首笔', '次笔']
            notes.append('成字字根：报户口 ' + key.upper() + '，' +
                         '、'.join(f'{n}{STROKE_NAME[c]}笔（{g}）'
                                   for n, c, g in zip(names, letters, entry['strokes'])) +
                         '（按五笔取码规则，非笔顺教学数据）')
            entry['componentsSource'] = 'D1'
            entry['quality'] = 'full'
            return entry
        readable_strokes = ([g for g in decode(glyphs, pua_map)[0][1:]
                             if isinstance(g, str) and g in STROKES]
                            if glyphs[0] == char else [])
        if readable_strokes:
            entry['strokes'] = readable_strokes
            notes.append('成字字根：报户口 + ' +
                         '、'.join(STROKE_NAME[{'横':'g','竖':'h','撇':'t','捺':'y','折':'n'}[STROKES[g]]] + '笔（' + g + '）' for g in readable_strokes))
            entry['quality'] = 'full'
        else:
            notes.append('成字字根：笔画序列暂缺（既不在可读字根键表，也无法由全码推导）')
            entry['quality'] = 'partial'
        return entry

    # 3) 合体字
    per_position = bool(glyphs) and len(code) >= 3 and len(glyphs) == len(code)
    decoded2, unknown2 = decode(glyphs, pua_map, drop_tail_pua=per_position) if glyphs else ([], 0)
    decoded3, unknown3 = decode(d3_glyphs, pua_map) if d3_glyphs else ([], 0)

    # D2 的强信号：一个码位一个字根字形（含占位），此时按码位对齐，并用"只在末位出现的
    # 私有区字形"来判定识别码槽（报告 244）。
    if per_position:
        source, readable, unknown_glyphs = 'D2', decoded2, unknown2
    else:
        pool = []
        if decoded3:
            pool.append(('D3', decoded3, unknown3))
        if decoded2:
            pool.append(('D2', decoded2, unknown2))
        pick = (next((c for c in pool if fits(c[1]) and c[2] == 0), None)
                or next((c for c in pool if fits(c[1])), None)
                or (pool[0] if pool else None))
        source, readable, unknown_glyphs = pick if pick else (None, [], 0)

    if readable and len(code) >= 2 and len(readable) > len(code):
        dropped = len(readable) - len(code)
        readable = readable[:len(code)]
        unknown_glyphs = sum(1 for c in readable if c is None)
        notes.append(f'拆字序列长于全码，已按码位截断（多出 {dropped} 个字形丢弃）')

    if unknown_glyphs:
        notes.append(f'有 {unknown_glyphs} 个字根字形未识别（占位，键位取自码位）')

    if not readable:
        notes.append('缺可读拆字（PUA 解码失败）')
        return entry
    entry['class'] = 'compound'
    entry['componentsSource'] = source
    entry['components'] = readable
    n = len(readable)
    entry['keys'] = list(code[:n]) if n <= len(code) else []
    if any(c is None for c in readable) and entry['ids']:
        filled_components, filled = fill_placeholders(readable, entry['keys'],
                                                     entry['ids'], readable_keys)
        if filled:
            readable = filled_components
            entry['components'] = readable
            unknown_glyphs = sum(1 for c in readable if c is None)
            notes.append(f'按 IDS（D19）补齐 {filled} 个占位字根：{entry["ids"]}')
    mismatched = [i for i, (c, k) in enumerate(zip(readable, entry['keys']))
                  if isinstance(c, str) and c in readable_keys and readable_keys[c] != k]
    # 诊断用：字形键与码位不一致的位次（D14 只收常用字根，复合字形会误报，故不据此降级）
    entry['positionMismatch'] = [i + 1 for i in mismatched]
    if any(c is None for c in readable):
        notes.append('占位字根：' +
                     '、'.join(f'第 {i + 1} 个（键 {k}）'
                               for i, (c, k) in enumerate(zip(readable, entry['keys'])) if c is None))

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



def render_explanation(entry: dict) -> str:
    """把一条 B0 记录渲染成运行时讲解文本（ADR-311：宿主只展示，不拼句子）。

    与 `tools/b0_query.py` 的规则保持一致：full 完整讲、partial 必带「拆解待核验」、unknown 只说缺资料。
    """
    quality = entry['quality']
    if quality == 'unknown':
        return '暂无编码/拆解资料'
    parts = []
    if entry['code']:
        parts.append(entry['code'])
    if quality == 'partial':
        if any(c is None for c in entry['components']) and entry['keys']:
            parts.append('字根：' + ' '.join(f'{c if c else "？"}({k})'
                                            for c, k in zip(entry['components'], entry['keys'])))
        reasons = []
        if any(c is None for c in entry['components']):
            reasons.append('部分字根字形未识别')
        if entry['code'] and len(entry['components']) not in (len(entry['code']), len(entry['code']) - 1):
            reasons.append('字根数与码长不符')
        if not reasons:
            reasons.append((entry['notes'][0] if entry['notes'] else '数据不完整')[:24])
        parts.append('拆解待核验（' + '；'.join(reasons) + '）')
        if entry['recognition']:
            parts.append('参考识别码 ' + entry['recognition']['key'])
        return '｜'.join(parts)
    if entry['class'] == 'key-name':
        parts.append('键名字：连打该键四次')
    elif entry['class'] == 'radical-char':
        if entry.get('strokes'):
            parts.append('成字字根（' + ''.join(entry['strokes']) + '）')
        note = entry['notes'][0] if entry['notes'] else ''
        parts.append(note.split('：', 1)[1] if '：' in note else '报户口 + 笔画')
    else:
        parts.append('字根：' + ' '.join(f'{c if c else "？"}({k})'
                                        for c, k in zip(entry['components'], entry['keys'])))
        record = entry['recognition']
        if record:
            parts.append(f'识别码 {record["key"]}（末笔{record["stroke"]}+{record["structure"]}）')
        else:
            parts.append('字根已够四码，无识别码')
    if entry['short1']:
        parts.append('一级简码 ' + entry['short1'])
    if entry['short2']:
        parts.append('二级简码 ' + entry['short2'])
    return '｜'.join(parts)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--codes', required=True)
    parser.add_argument('--radicals', required=True)
    parser.add_argument('--d3', help='D3 拆字（可选，配合 --pua-map 提高覆盖率）')
    parser.add_argument('--pua-map', help='PUA→可读字根映射（tools/decode_pua.py 生成）')
    parser.add_argument('--short1', required=True)
    parser.add_argument('--short2', required=True)
    parser.add_argument('--pinyin', required=True)
    parser.add_argument('--readable-keys', help='D14 可读字根键表（成字字根笔画推导用，可选）')
    parser.add_argument('--ids', help='IDS 分解（D19，MIT；填占位字根与结构参考，可选）')
    parser.add_argument('--limit', type=int, default=1000)
    parser.add_argument('--runtime-out', help='教学运行时资源（TSV，ADR-311）：字\t全码\t质量\t讲解')
    parser.add_argument('--out-dir', required=True)
    args = parser.parse_args()

    paths = {name: Path(getattr(args, name)) for name in ('codes', 'radicals', 'short1', 'short2', 'pinyin')}
    if args.d3:
        paths['d3'] = Path(args.d3)
    if args.readable_keys:
        paths['readable_keys'] = Path(args.readable_keys)
    if args.ids:
        paths['ids'] = Path(args.ids)
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
    d3 = load_d3(Path(args.d3)) if args.d3 else {}
    readable_keys: dict[str, str] = {}
    if args.readable_keys:
        for parts in read_rows(Path(args.readable_keys)):
            for glyph in parts[1]:
                readable_keys.setdefault(glyph, parts[0])
    rec_slot_pua = recognition_slot_pua(radicals, codes) if args.d3 else set()
    ids = load_ids(Path(args.ids)) if args.ids else {}

    ranked = sorted(freq.items(), key=lambda kv: (-kv[1], kv[0]))[: args.limit]
    entries = []
    for char, _weight in ranked:
        code = codes.get(char)
        if not code:
            entries.append({'char': char, 'code': None, 'class': None, 'components': [],
                            'keys': [], 'strokes': None, 'recognition': None, 'short1': short1.get(char), 'short2': short2.get(char),
                            'pinyin': pinyin.get(char), 'frequency': freq.get(char, 0),
                            'quality': 'unknown', 'notes': ['缺全码']})
            continue
        glyphs = radicals.get(char)
        if not glyphs:
            entries.append({'char': char, 'code': code, 'class': None, 'componentsSource': None,
                            'components': [], 'keys': [], 'strokes': None,
                            'ids': ids.get(char), 'idsStructure': ids_structure(ids.get(char, '')),
                            'positionMismatch': [], 'recognition': None,
                            'short1': short1.get(char), 'short2': short2.get(char),
                            'pinyin': pinyin.get(char), 'frequency': freq.get(char, 0),
                            'quality': 'unknown', 'notes': ['缺拆字数据']})
            continue
        entries.append(build(char, code, glyphs, short1, short2, pinyin, freq,
                             pua_map=pua_map, d3_glyphs=d3.get(char),
                             rec_slot_pua=rec_slot_pua, readable_keys=readable_keys,
                             ids=ids))

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
        'placeholderEntries': sum(1 for e in entries if any(c is None for c in e.get('components') or [])),
        'placeholderComponents': sum(1 for e in entries for c in (e.get('components') or []) if c is None),
        'recognitionSlotPua': len(rec_slot_pua),
        'withStrokes': sum(1 for e in entries if e.get('strokes')),
        'withIds': sum(1 for e in entries if e.get('ids')),
        'idsFilled': sum(1 for e in entries if any('按 IDS' in n for n in e['notes'])),
        'positionMismatchEntries': sum(1 for e in entries if e.get('positionMismatch')),
        'inputs': {name: {'path': str(path), 'sha256': sha256(path)} for name, path in paths.items()},
        'generator': 'modules/hanzi-structure/tools/build_b0.py',
        'command': ' '.join(['python3', 'tools/build_b0.py'] + sys.argv[1:]),
    }

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / 'B0.json').write_text(json.dumps(entries, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    (out_dir / 'B0-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    if args.runtime_out:
        # ADR-311（v2）：结构化紧凑 TSV —— 学习区要画"字根格子 + 键位"，预渲染文本不够用。
        # 列：字 \t 全码 \t 质量 \t 字根(形:键 …) \t 识别码(字母|末笔|结构) \t 简码(一/二)
        rows = ['# ADR-311 学习区运行时资源 v2：字\t全码\t质量\t字根(形:键)\t识别码(字母|末笔|结构)\t简码(一/二)']
        for entry in entries:
            # 位次不符（D2 序列尾部不可靠）时，从第一个不符位次起截断：
            # 宁可少显示，也不把"丶"标成 T 这种错误键位教给用户（报告 255）。
            components, keys = entry['components'], entry['keys']
            mismatch = entry.get('positionMismatch') or []
            quality = entry['quality']
            if mismatch:
                cut = max(0, min(len(components), mismatch[0] - 1))
                components, keys = components[:cut], keys[:cut]
                # 截断后不再是"完整解释"：运行时按 partial 降级，宿主会显示「拆解待核验」。
                quality = 'partial'
            roots = ' '.join(f'{(c or "？")}:{k}' for c, k in zip(components, keys))
            rec = entry['recognition']
            recognition = f'{rec["key"].upper()}|{rec["stroke"]}|{rec["structure"]}' if rec else ''
            shorts = '/'.join(x for x in (entry['short1'], entry['short2']) if x)
            rows.append('\t'.join([entry['char'], entry['code'] or '', quality,
                                    roots, recognition, shorts]))
        payload = '\n'.join(rows) + '\n'
        Path(args.runtime_out).write_text(payload, encoding='utf-8')
        size = len(payload.encode('utf-8'))
        print(f'写入 {args.runtime_out}（{len(entries)} 条，{size} 字节，约 {size / max(len(entries), 1):.1f} B/字）')
        report['runtime'] = {'path': args.runtime_out, 'bytes': size, 'version': 2,
                             'bytesPerEntry': round(size / max(len(entries), 1), 1)}

    print(f'写入 {out_dir}/B0.json（{len(entries)} 条）')
    print(json.dumps(report['quality'], ensure_ascii=False), '识别码可解释:', report['withRecognition'])
    return 0


if __name__ == '__main__':
    sys.exit(main())
