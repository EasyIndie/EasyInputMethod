"""Build a compact offline full-code index; reject unverified or PUA teaching rows."""
from pathlib import Path
import hashlib
import json
import re
import struct

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'data/generated/wubi86-single.tsv'
ROOTS = ROOT / 'data/learning/wubi86-roots.tsv'
OUTPUT = ROOT / 'data/generated/wubi86-learning-codes.bin'
REPORT = ROOT / 'data/generated/wubi86-learning-report.json'


def full_codes():
    result = {}
    for line in SOURCE.read_text().splitlines():
        if not line or line.startswith('#'):
            continue
        code, text, _ = line.split('\t')
        if len(text) != 1 or not re.fullmatch('[a-y]{1,4}', code) or text in result:
            raise ValueError('invalid or duplicate primary single-character entry')
        result[text] = code
    return result


def check_roots(codes):
    seen = set()
    for line in ROOTS.read_text().splitlines():
        if not line or line.startswith('#'):
            continue
        text, code, category, rule, pairs, recognition = line.split('\t')
        if text in seen or codes.get(text) != code or category not in ('key_name', 'compound', 'chengzi'):
            raise ValueError('invalid teaching identity/code/category')
        seen.add(text)
        if any(0xE000 <= ord(c) <= 0xF8FF or 0xF0000 <= ord(c) <= 0x10FFFF for c in line):
            raise ValueError('PUA/supplementary private glyph not allowed')
        units = [p.rsplit(':', 1) for p in pairs.split()]
        if not rule or not units or any(len(k) != 1 or k not in 'abcdefghijklmnopqrstuvwxy' or not root for root, k in units):
            raise ValueError('invalid readable root/key pair')
        keys = ''.join(k for _, k in units)
        if recognition != '-':
            description, key = recognition.rsplit(':', 1)
            if not description or len(key) != 1:
                raise ValueError('invalid recognition')
            keys += key
        if category == 'key_name':
            keys *= 4
        if keys != code:
            raise ValueError('teaching root keys do not reproduce full code: ' + text)
    return seen


def build():
    codes = full_codes()
    covered = check_roots(codes)
    raw = b''.join(struct.pack('<I', ord(text)) + code.encode().ljust(4, b'\0')
                   for text, code in sorted(codes.items()))
    OUTPUT.write_bytes(raw)
    digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    report = {'source_sha256': digest(SOURCE), 'roots_sha256': digest(ROOTS),
              'index_sha256': digest(OUTPUT), 'index_bytes': len(raw),
              'full_code_characters': len(codes), 'verified_explanations': len(covered),
              'unexplained_characters': len(codes) - len(covered),
              'oracle_code_columns_published': False,
              'note': 'Only verified explanations; all other characters explicitly lack decomposition.'}
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(report, ensure_ascii=False))


if __name__ == '__main__':
    build()
