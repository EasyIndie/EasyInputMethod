"""Measure current teaching inputs and arithmetic scenarios, not a future pack benchmark."""
import argparse
import hashlib
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--project-root', type=Path, required=True)
parser.add_argument('--app', type=Path)
args = parser.parse_args()
files = []
for name in ['data/generated/wubi86-learning-codes.bin', 'data/learning/wubi86-roots.tsv']:
    raw = (args.project_root / name).read_bytes()
    files.append({'path': name, 'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()})
count = (args.project_root / 'data/generated/wubi86-learning-codes.bin').stat().st_size // 8
result = {'scope': 'Current inputs; not the size or coverage of a new structure library',
          'files': files, 'target_characters': count,
          'scenario_not_benchmark': [{'bytes_per_character': size, 'character_bytes': count * size,
                                      'MiB': round(count * size / 1048576, 3)} for size in [64, 128, 256, 512]],
          'scenario_excludes': ['shared root/rule pools', 'headers/indexes', 'reader/render code',
                                'geometry/fonts', 'signing/alignment', 'replaced old data', 'compression'],
          'current_input_total_bytes': sum(item['bytes'] for item in files)}
if args.app:
    paths = [p for p in args.app.rglob('*') if p.is_file() and not p.is_symlink()]
    result['installed_app_baseline'] = {'source_commit': (args.app / 'Contents/Resources/SOURCE-COMMIT').read_text().strip(),
                                       'file_content_bytes': sum(p.stat().st_size for p in paths),
                                       'scope': 'Sum of regular file lengths, not allocated disk blocks or installer download size'}
print(json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2))
