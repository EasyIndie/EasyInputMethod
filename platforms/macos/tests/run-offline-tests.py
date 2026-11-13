#!/usr/bin/env python3
"""Run every offline Python regression; never run native desktop probes."""
import json
import os
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time


def failure_excerpt(log):
    text = log.read_text(errors='replace')
    if len(text) <= 16000:
        return text
    return text[:4000] + '\n[诊断中段省略；完整内容保留在私有日志]\n' + text[-12000:]


def main():
    # 报告200：macOS 13 自带的 python3 是 3.9，而 validate-release/release_version 用 tomllib（3.11+）。
    if sys.version_info < (3, 11):
        print('FAIL 离线回归需要 Python ≥3.11（tomllib）；本机 python3 是 %d.%d，请用 python3.11+ 运行' % sys.version_info[:2])
        return 1
    root = Path(__file__).resolve().parents[3]
    files = sorted((root / 'platforms/macos/tests').glob('test-*.py')) + sorted((root / 'packaging/macos/tests').glob('test-*.py'))
    if not files:
        print('FAIL 未发现离线回归')
        return 1
    output = Path(tempfile.mkdtemp(prefix='lampyris-offline-tests-'))
    # 报告230：这 56 个文件互不共享状态（各自用临时目录/假 HOME），串行跑纯属浪费——
    # 改成并行后总时长由最慢的一个文件决定。JOBS=1 可退回串行做归因。
    try:
        # 共享 Swift/Clang 模块缓存后各文件不再各自重建 SDK 模块，并发可回到 6（报告 267）。
        jobs = int(os.environ.get('JOBS', '0')) or min(6, os.cpu_count() or 6)
    except ValueError:
        jobs = 0
    if jobs <= 0:
        jobs = min(6, os.cpu_count() or 6)
    # 所有测试共用一份模块缓存（clang 模块缓存自带文件锁，可并发读写）；放在 build 下，不入库。
    cache = root / 'platforms/macos/build/swift-module-cache'
    cache.mkdir(parents=True, exist_ok=True)
    os.environ.setdefault('LAMPYRIS_SWIFT_MODULE_CACHE', str(cache))
    jobs = max(1, min(jobs, len(files)))

    def run_one(index, file):
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
        return {'file': str(file.relative_to(root)), 'status': status, 'exit': code, 'seconds': round(time.monotonic() - started, 3), 'tests': int(counts[-1]) if counts else None, 'log': str(log)}

    started_all = time.monotonic()
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        futures = [(index, pool.submit(run_one, index, file)) for index, file in enumerate(files)]
        rows = []
        for index, future in futures:
            row = future.result()
            rows.append(row)
            print(f"{row['status']} {row['file']}", flush=True)
            if row['status'] != 'PASS':
                print('失败诊断：' + failure_excerpt(Path(row['log'])), flush=True)
    elapsed = round(time.monotonic() - started_all, 1)
    report = output / 'summary.json'
    report.write_text(json.dumps({'passed': all(row['status'] == 'PASS' for row in rows), 'files': len(rows), 'tests': sum(row['tests'] or 0 for row in rows), 'jobs': jobs, 'seconds': elapsed, 'serial_seconds': round(sum(row['seconds'] for row in rows), 1), 'results': rows}, ensure_ascii=False, indent=2), encoding='utf-8')
    report.chmod(0o600)
    print(f'离线回归 {len(rows)} 文件 / {sum(row["tests"] or 0 for row in rows)} 例，{jobs} 并发，{elapsed}s（串行需 {round(sum(row["seconds"] for row in rows), 1)}s）')
    print('EVIDENCE=' + str(report))
    return 0 if all(row['status'] == 'PASS' for row in rows) else 1


if __name__ == '__main__':
    raise SystemExit(main())
