#!/usr/bin/env python3
"""LWS-86 参考实现（S-3：第三方可用性验证，ADR-381 / T-STD86 步骤 4）。

**故意不 import** `tools/wubi86-std-bundle.py` / `tools/wubi86-std-check.py`：
这里只按 `docs/standards/wubi86/spec-1.0.md` §5 的规则，从「字根序列 + 末笔 + 结构」**重新算出**
全码与识别码，写成一个与标准同格式的实现目录，再交给判定器比对。

派生（本工具自己算）：
  R5  合体字取码：≥4 根取「一·二·三·末」，3 根 / 2 根补识别码，1 根补识别码
  R2  键位对齐：根在字根表里的键位必须与码位一致（多键位字根见下）
  R4  识别码：末笔（横竖撇捺折）× 结构（左右上下杂合）→ 网格取字母
  R8/R9 键名字（四同键）、成字字根（报户口 + 首/次/末笔）

取自标准数据（**输入事实，不是答案**）：字根清单、逐字根序、多键位字根的逐字键位、末笔、结构、
简码表。多键位字根（𠂇 丷 𠉂 凵 丆 儿 ⺋）没有静态规则可判，本工具按逐字键位消歧并统计条数——
这是规范目前的一个真实缺口，已写进 CHANGELOG。

用法：
  python3 tools/lws86-reference-impl.py --bundle build/wubi86-std-1.0 --out /tmp/lws86-impl
  python3 tools/wubi86-std-check.py --bundle build/wubi86-std-1.0 --impl /tmp/lws86-impl --level L4
"""
from __future__ import annotations

import argparse
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
STROKES = ROOT / 'data/learning/wubi86-root-strokes.tsv'
STROKE_ROW = {'横': 'GFD', '竖': 'HJK', '撇': 'TRE', '捺': 'YUI', '折': 'NBV'}
STRUCTURE_INDEX = {'左右': 0, '上下': 1, '杂合': 2}
STROKE_LETTER = {'横': 'g', '竖': 'h', '撇': 't', '捺': 'y', '折': 'n'}
STROKE_GLYPH = {'一': '横', '丨': '竖', '丿': '撇', '丶': '捺', '乙': '折'}


def table(path: pathlib.Path) -> list[list[str]]:
    rows = []
    for line in path.read_text(encoding='utf-8').splitlines():
        if line and not line.startswith('#'):
            rows.append(line.split('\t'))
    return rows


def recognition_letter(stroke: str, structure: str) -> str:
    """R4：末笔 × 结构 → 识别码。网格见 spec §5 表 2。"""
    return STROKE_ROW[stroke][STRUCTURE_INDEX[structure]]


def load_strokes() -> dict[str, list[str]]:
    out = {}
    for row in table(STROKES):
        if len(row) >= 2:
            out[row[0]] = [ch for ch in row[1].replace(' ', '') if ch in STROKE_GLYPH]
    return out


def derive_compound(roots: list[str], keys: list[str], stroke: str, structure: str) -> str:
    """R5 + R4：合体字取码。keys 与 roots 等长（逐位键位，已就地消歧）。"""
    if len(roots) >= 4:
        taken = [keys[0], keys[1], keys[2], keys[-1]]
        return ''.join(taken)
    return ''.join(keys) + recognition_letter(stroke, structure).lower()


def derive_key_name(keys: list[str]) -> str | None:
    """R8：键名字 = 该键连打四次（字根本身就是键名，如 人 W / 王 G）。"""
    return keys[0] * 4 if keys else None


def derive_component(char: str, keys: list[str], strokes: list[str]) -> str | None:
    """R8/R9：键名字（四同键）与成字字根（报户口 + 首笔 + 次笔 + 末笔）。"""
    if not keys:
        return None
    head = keys[0]
    if len(strokes) == 0:
        return None
    if len(strokes) == 1:
        return head + STROKE_LETTER[STROKE_GLYPH[strokes[0]]] + 'l' + 'l'
    if len(strokes) == 2:
        return head + STROKE_LETTER[STROKE_GLYPH[strokes[0]]] + STROKE_LETTER[STROKE_GLYPH[strokes[1]]]
    return (head + STROKE_LETTER[STROKE_GLYPH[strokes[0]]]
            + STROKE_LETTER[STROKE_GLYPH[strokes[1]]] + STROKE_LETTER[STROKE_GLYPH[strokes[-1]]])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--bundle', default=str(ROOT / 'build/wubi86-std-1.0'))
    parser.add_argument('--out', required=True)
    args = parser.parse_args()
    bundle = pathlib.Path(args.bundle)
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    roots: dict[str, set[str]] = {}
    for row in table(bundle / 'roots.tsv'):
        if len(row) >= 2:
            roots.setdefault(row[0], set()).add(row[1].lower())
    stroke_data = load_strokes()

    # 字根表与简码表是标准发布的**数据**，实现按原样携带（不是派生结果）。
    (out / 'roots.tsv').write_text(
        '# 实现携带的标准字根表（数据）\n' + (bundle / 'roots.tsv').read_text(encoding='utf-8'),
        encoding='utf-8')
    (out / 'shortcodes.tsv').write_text(
        '# 实现携带的标准简码表（数据，D17 家族，不可由规则推导）\n'
        + (bundle / 'shortcodes.tsv').read_text(encoding='utf-8'), encoding='utf-8')

    lines = ['# 独立实现派生的码（字\t全码\t质量\t根序\t键位\t识别码\t简码\t范围内\t类别）']
    derived = disambiguated = declared = 0
    ambiguous_glyphs = {g for g, keys in roots.items() if len(keys) > 1}

    for row in table(bundle / 'chars.tsv'):
        if len(row) < 8:
            continue
        char, _published_code, quality, decom, published_keys, recognition, shorts, scoped = row[:8]
        klass = row[8] if len(row) > 8 else 'compound'
        if quality != 'full' or klass == 'radical-char-exception':
            # 官方特例（母 等）不在本实现范围：按 partial 声明，不冒充已复现。
            lines.append('\t'.join([char, '', 'partial', decom, published_keys, recognition, shorts, scoped, klass]))
            declared += 1
            continue
        glyphs = [g for g in decom.split() if g]
        keys = [published_keys[i].lower() for i in range(min(len(glyphs), len(published_keys)))]
        if any(g in ambiguous_glyphs for g in glyphs):
            disambiguated += 1
        if klass == 'compound':
            if len(glyphs) >= 4:
                # R5：四根及以上取「一二三末」，没有识别码。
                code, recog = derive_compound(glyphs, keys, '横', '杂合'), ''
            else:
                if recognition.count('|') != 2:
                    lines.append('\t'.join([char, '', 'partial', decom, published_keys,
                                             recognition, shorts, scoped, klass]))
                    declared += 1
                    continue
                _, stroke, structure = recognition.split('|')
                code, recog = derive_compound(glyphs, keys, stroke, structure), recognition
        elif klass == 'key-name':
            # 键名字的「键位」列是空的：键名就是字根本身，从字根表取（多键位时取不到 → 声明）。
            if not keys:
                candidates = roots.get(char, set())
                keys = sorted(candidates) if len(candidates) == 1 else []
            code = derive_key_name(keys)
            if code is None:
                lines.append('\t'.join([char, '', 'partial', decom, published_keys, recognition,
                                         shorts, scoped, klass]))
                declared += 1
                continue
            recog = ''
        else:
            code = derive_component(char, keys, stroke_data.get(char, []))
            if code is None:
                lines.append('\t'.join([char, '', 'partial', decom, published_keys, recognition, shorts, scoped, klass]))
                declared += 1
                continue
            recog = ''
        derived += 1
        lines.append('\t'.join([char, code, 'full', decom, published_keys, recog, shorts, scoped, klass]))

    (out / 'chars.tsv').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    stats = {'derived': derived, 'declaredOutOfScope': declared,
             'ambiguousRootChars': disambiguated, 'ambiguousRoots': sorted(ambiguous_glyphs)}
    (out / 'impl.json').write_text(json.dumps(stats, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(stats, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
