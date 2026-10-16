"""Audit shipped teaching coverage using registered, frozen dictionary weights only."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMPLETE = {'compound', 'key_name', 'stroke', 'chengzi'}


def rows(path):
    for line in path.read_text().splitlines():
        if line and not line.startswith('#'):
            yield line.split('\t')


def audit(root):
    paths = {name: root / relative for name, relative in {
        'codes': 'data/generated/wubi86-single.tsv',
        'teaching': 'data/learning/wubi86-roots.tsv',
        'characters': 'data/generated/pinyin-chars.tsv',
        'words': 'data/generated/pinyin-core.tsv',
    }.items()}
    codes, weights, teaching, words = {}, {}, {}, {}
    for code, text, weight in rows(paths['codes']):
        codes[text] = code
        weights[text] = max(weights.get(text, 0), int(weight))
    for _, text, weight in rows(paths['characters']):
        weights[text] = max(weights.get(text, 0), int(weight))
    for text, _, category, *_ in rows(paths['teaching']):
        teaching[text] = category
    for _, text, weight in rows(paths['words']):
        words[text] = max(words.get(text, 0), int(weight))

    def status(text):
        return teaching.get(text, 'code_only' if text in codes else 'no_full_code')

    priority = sorted(weights, key=lambda text: (-weights[text], text))
    bands = {}
    for size in [100, 500, 1000, 3500]:
        chosen = priority[:size]
        categories = Counter(status(text) for text in chosen)
        complete = sum(value for key, value in categories.items() if key in COMPLETE)
        bands[str(size)] = {'characters': len(chosen), 'complete': complete,
                            'percent': round(100 * complete / len(chosen), 2),
                            'categories': dict(sorted(categories.items()))}
    word_bands = {}
    for size in [100, 500]:
        chosen = sorted(words, key=lambda text: (-words[text], text))[:size]
        complete = sum(all(status(char) in COMPLETE for char in word) for word in chosen)
        word_bands[str(size)] = {'words': len(chosen), 'all_characters_explained': complete}
    gaps = [{'text': text, 'weight': weights[text], 'code': codes.get(text), 'status': status(text)}
            for text in priority[:3500] if status(text) not in COMPLETE]
    return {
        'method': 'Shipped D10-derived maximum single-character weight; ties by Unicode. This is a reproducible priority proxy, not measured typing usage.',
        'input_sha256': {key: hashlib.sha256(path.read_bytes()).hexdigest() for key, path in paths.items()},
        'full_code_characters': len(codes), 'teaching_records': len(teaching),
        'fully_explained': sum(category in COMPLETE for category in teaching.values()),
        'categories': dict(sorted(Counter(teaching.values()).items())),
        'character_priority_bands': bands, 'word_priority_bands': word_bands,
        'priority_gaps': gaps,
    }


def main():
    parser = argparse.ArgumentParser(description='审计既有五笔教学覆盖；不联网、不修改教学数据。')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    text = json.dumps(audit(ROOT), ensure_ascii=False, indent=2, sort_keys=True) + '\n'
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text)
    else:
        print(text, end='')


if __name__ == '__main__':
    main()
