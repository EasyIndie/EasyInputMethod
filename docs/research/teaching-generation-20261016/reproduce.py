"""Reproduce research observations; never import data or modify product artifacts."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path

COMPLETE = {'key_name', 'stroke', 'chengzi', 'compound'}
TEMPLATES = {
    'key_name': '键名字：{roots}；对应{keys}，按该键四次。',
    'stroke': '单笔画：取码单元{roots}，键序列{keys}。',
    'chengzi': '成字字根：报户口后取所需笔画；取码单元{roots}，键序列{keys}。',
    'compound': '合体字：取码单元{roots}，键序列{keys}。',
}


def pua(character):
    value = ord(character)
    return (0xE000 <= value <= 0xF8FF or 0xF0000 <= value <= 0xFFFFD
            or 0x100000 <= value <= 0x10FFFD)


def read(path, expected=None):
    data = path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if expected and digest != expected:
        raise ValueError('research input hash mismatch: ' + path.name)
    encoding = 'utf-16' if data.startswith((b'\xff\xfe', b'\xfe\xff')) else 'utf-8-sig'
    return data.decode(encoding), digest


def observe(project, external):
    d2, d2_sha = read(project / 'data/sources/wubi-lex-86.txt',
                      'da8a20e6af3446348d5d68a89ac71d5e3b9b17b00446d8204ac1e9529626697f')
    d3, d3_sha = read(external / 'd3-current.txt',
                      '7c64e5846f2ed96a26da24abffaaa2d139a5efc7a0d6de336d13269b70095ac6')
    d98, d98_sha = read(external / '98-full.txt',
                        '1d63352c5f6498af0890494af551d698cdca77c7dfc8f9b04178df87defb27f6')
    d06, d06_sha = read(external / '06-split.txt',
                        '5dc4d31db9d2aa671a80e078cc9b1532b17aa649be798c091b96f854765603d4')
    teaching, teaching_sha = read(project / 'data/learning/wubi86-roots.tsv')
    rows2 = [line.split('\t') for line in d2.splitlines() if len(line.split('\t')) == 2]
    rows3 = [line.split('\t') for line in d3.splitlines() if line and not line.startswith('#')]
    rows98 = [line.split('\t', 1) for line in d98.splitlines() if '\t' in line]
    valid98 = [(char, annotation) for char, annotation in rows98 if len(char) == 1 and not pua(char)]
    traces = []
    for line in teaching.splitlines():
        if not line or line.startswith('#'):
            continue
        fields = line.split('\t')
        char, expected, kind = fields[:3]
        if kind not in COMPLETE:
            continue
        # fields[3], the per-character prose, is deliberately not used.
        units = [dict(zip(('label', 'key'), pair.rsplit(':', 1))) for pair in fields[4].split()]
        code = ''.join(unit['key'] for unit in units)
        if kind == 'key_name':
            code *= 4
        recognition = None
        if fields[5] != '-':
            description, key = fields[5].rsplit(':', 1)
            recognition = {'fact_label': description, 'key': key}
            code += key
        if code != expected:
            raise ValueError('verified projection roundtrip failed: ' + char)
        explanation = TEMPLATES[kind].format(roots='、'.join(unit['label'] for unit in units),
                                             keys=' '.join(unit['key'].upper() for unit in units))
        if recognition:
            explanation += '补识别码：' + recognition['fact_label'] + ' → ' + recognition['key'].upper() + '。'
        traces.append({'character': char, 'research_rule_family': kind, 'selected_units': units,
                       'recognition': recognition, 'full_code': code, 'short_explanation': explanation})
    summary = {
        'input_sha256': {'D2': d2_sha, 'D3': d3_sha, 'candidate98': d98_sha,
                         'candidate06': d06_sha, 'verified_teaching': teaching_sha},
        'D2': {'rows': len(rows2), 'pua_rows': sum(any(pua(c) for c in roots) for _, roots in rows2),
               'unique_pua': len({c for _, roots in rows2 for c in roots if pua(c)}),
               'unit_counts': dict(sorted(Counter(len(roots) for _, roots in rows2).items()))},
        'D3': {'rows': len(rows3), 'pua_rows': sum(any(pua(c) for c in row[1]) for row in rows3),
               'unique_pua': len({c for row in rows3 for c in row[1] if pua(c)}),
               'unit_counts': dict(sorted(Counter(len(row[1].split()) for row in rows3).items()))},
        'candidate98': {'physical_lines': len(d98.splitlines()), 'encoding': 'UTF-16 with BOM',
                        'non_pua_character_rows': len(valid98), 'unique_non_pua_characters': len({c for c, _ in valid98}),
                        'characters_with_multiple_rows': sum(n > 1 for n in Counter(c for c, _ in valid98).values()),
                        'pua_annotation_rows': sum(any(pua(c) for c in a) for _, a in valid98)},
        'candidate06': {'physical_lines': len(d06.splitlines()),
                        'two_column_rows': sum(len(line.split('\t')) == 2 for line in d06.splitlines())},
        'projection': {'records': len(traces), 'matching_codes': len(traces),
                       'per_character_prose_used': False, 'shared_templates': len(TEMPLATES),
                       'families': dict(Counter(t['research_rule_family'] for t in traces)),
                       'recognition_keys': sorted({t['recognition']['key'] for t in traces if t['recognition']})},
        'limitations': ['Only projects already verified selected-unit facts, not newly discovered decompositions.',
                        'Roundtrip does not establish independent semantic correctness or full stroke geometry.',
                        'External inputs are research candidates, not approved product data.'],
    }
    return summary, traces


def main():
    parser = argparse.ArgumentParser(description='重现实测统计及受限模板投影；不联网、不改产品数据。')
    parser.add_argument('--project-root', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--external-dir', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args()
    summary, traces = observe(args.project_root, args.external_dir)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for filename, data in [('observations.json', summary), ('trace-projection.json', traces)]:
        (args.output_dir / filename).write_text(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + '\n')
    print('PASS research reproduction; no product files changed')


if __name__ == '__main__':
    main()
