#!/usr/bin/env python3
"""把 D3（WindInput）里的私有区（PUA）字形解码成可读字根（B0 后续，报告 241）。

原理：D2（aardio/wubi-lex）与 D3 各自给出同一字的字根序列；**逐字对齐后**，
D3 的 PUA 字形与 D2 的可读字形一一对应，即可学出「PUA → 可读字根」。
只采纳"主导读法占比 ≥ 阈值且样本数 ≥ 下限"的映射，其余标 ambiguous，不猜。

用法：
  python3 tools/decode_pua.py --d2 <wubi-lex-86.txt> --d3 <windinput-chaizi.txt> \
      --out corpus/pua-map.json [--min-samples 3] [--min-share 0.9]
"""
from __future__ import annotations

import argparse
import collections
import json
import sys
from pathlib import Path

PLACEHOLDER = '\ue000'


def is_supplementary_pua(ch: str) -> bool:
    return ord(ch) >= 0xF0000


def is_bmp_pua(ch: str) -> bool:
    return 0xE000 <= ord(ch) <= 0xF8FF


def load_d2(path: Path) -> dict[str, list[str]]:
    out = {}
    for line in path.read_text(encoding='utf-8').splitlines():
        if not line.strip():
            continue
        parts = line.rstrip('\n').split('\t')
        if len(parts) >= 2:
            out[parts[0]] = list(parts[1])
    return out


def load_d3(path: Path) -> dict[str, list[str]]:
    out = {}
    for line in path.read_text(encoding='utf-8').splitlines():
        if not line.strip() or line.startswith('#'):
            continue
        parts = line.rstrip('\n').split('\t')
        if len(parts) >= 3:
            out[parts[0]] = [c for c in parts[1].split() if c != PLACEHOLDER]
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--d2', required=True)
    parser.add_argument('--d3', required=True)
    parser.add_argument('--out', required=True)
    parser.add_argument('--min-samples', type=int, default=3)
    parser.add_argument('--min-share', type=float, default=0.9)
    args = parser.parse_args()

    d2 = load_d2(Path(args.d2))
    d3 = load_d3(Path(args.d3))

    observations: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    aligned = mismatched = 0
    for char, glyphs2 in d2.items():
        glyphs3 = d3.get(char)
        if not glyphs3:
            continue
        if len(glyphs2) != len(glyphs3):
            mismatched += 1
            continue
        aligned += 1
        for a, b in zip(glyphs2, glyphs3):
            pua, readable = None, None
            if is_bmp_pua(b) and not is_supplementary_pua(a) and not is_bmp_pua(a):
                pua, readable = b, a
            elif is_bmp_pua(a) and not is_supplementary_pua(b) and not is_bmp_pua(b):
                pua, readable = a, b
            if pua and readable:
                observations[pua][readable] += 1

    mapping = {}
    ambiguous = []
    for pua, counter in sorted(observations.items(), key=lambda kv: -sum(kv[1].values())):
        total = sum(counter.values())
        readable, hits = counter.most_common(1)[0]
        share = hits / total
        if total >= args.min_samples and share >= args.min_share:
            mapping[pua] = {'readable': readable, 'samples': total, 'share': round(share, 3)}
        else:
            ambiguous.append({'pua': pua, 'samples': total, 'top': counter.most_common(3)})

    out = {
        'alignedChars': aligned,
        'mismatchedChars': mismatched,
        'puaTotal': len(observations),
        'confident': len(mapping),
        'ambiguous': len(ambiguous),
        'observations': sum(sum(c.values()) for c in observations.values()),
        'minSamples': args.min_samples,
        'minShare': args.min_share,
        'map': {pua: info for pua, info in mapping.items()},
        'ambiguousSamples': ambiguous[:20],
    }
    Path(args.out).write_text(json.dumps(out, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'对齐 {aligned} 字（长度不一致 {mismatched}），PUA {len(observations)} 个：'
          f'可确认 {len(mapping)}，含糊 {len(ambiguous)}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
