"""Private artifact output for test harnesses; never a product configuration path."""
import hashlib
import json
import os
from pathlib import Path


def output_directory(default):
    output = Path(os.environ.get('LAMPYRIS_ACCEPTANCE_OUTPUT', str(default)))
    output.mkdir(parents=True, exist_ok=True)
    return output


def record_probe(path):
    directory = os.environ.get('LAMPYRIS_ACCEPTANCE_OUTPUT')
    if directory:
        raw = Path(path).read_bytes()
        (output_directory(directory) / 'probe.json').write_text(json.dumps({
            'sha256': hashlib.sha256(raw).hexdigest(), 'bytes': len(raw),
            'scope': 'Compiled native test executable, not installed IMK binary',
            'cargo_lock_sha256': hashlib.sha256((Path(__file__).resolve().parents[3] / 'Cargo.lock').read_bytes()).hexdigest(),
        }, indent=2) + '\n')
