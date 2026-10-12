#!/usr/bin/env python3
"""Run every offline Python regression; never run native desktop probes."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time


def main():
    root = Path(__file__).resolve().parents[3]
    files = sorted((root / 'platforms/macos/tests').glob('test-*.py')) + sorted((root / 'packaging/macos/tests').glob('test-*.py'))
    if not files:
        print('FAIL 未发现离线回归')
        return 1
    output = Path(tempfile.mkdtemp(prefix='lampyris-offline-tests-'))
    rows = []
    for index, file in enumerate(files):
        log = output / f'{index:02d}-{file.stem}.log'
        started = time.monotonic()
        status = 'FAIL'
        code = None
        with log.open('w') as stream:
            try:
                completed = subprocess.run([sys.executable, str(file)], cwd=root, env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'}, stdout=stream, stderr=subprocess.STDOUT, timeout=120)
                code = completed.returncode
                status = 'PASS' if code == 0 else 'FAIL'
            except subprocess.TimeoutExpired:
                status = 'TIMEOUT'
        log.chmod(0o600)
        counts = re.findall(r'Ran (\d+) tests?', log.read_text())
        rows.append({'file': str(file.relative_to(root)), 'status': status, 'exit': code, 'seconds': round(time.monotonic() - started, 3), 'tests': int(counts[-1]) if counts else None, 'log': str(log)})
        print(f'{status} {file.relative_to(root)}', flush=True)
    report = output / 'summary.json'
    report.write_text(json.dumps({'passed': all(row['status'] == 'PASS' for row in rows), 'files': len(rows), 'tests': sum(row['tests'] or 0 for row in rows), 'results': rows}, ensure_ascii=False, indent=2))
    report.chmod(0o600)
    print('EVIDENCE=' + str(report))
    return 0 if all(row['status'] == 'PASS' for row in rows) else 1


if __name__ == '__main__':
    raise SystemExit(main())
