#!/usr/bin/env python3
"""Verify the installed isolated package still works after one machine sleep/wake cycle.

Uses the already-proven TextEdit probe as the judge: it must pass before the sleep and again
after the wake, with the input source, host process and real data digests recorded on both sides.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

HERE = Path(__file__).resolve().parent
TEXTEDIT = HERE / 'run-installed-textedit-probe.py'


def run(arguments, timeout=30):
    return subprocess.run(arguments, check=True, capture_output=True, text=True, timeout=timeout)


def state(helper, root):
    return json.loads(run([str(helper), 'state', str(root)]).stdout)


def host_pids():
    result = subprocess.run(['pgrep', '-f', 'LampyrisIMKTest-.*MacOS/LampyrisIMKTest'],
                            capture_output=True, text=True)
    return [line for line in result.stdout.split() if line]


def stamp(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None


def probe_commit(root, helper):
    result = subprocess.run([sys.executable, str(TEXTEDIT), str(root), str(helper), '--scenario', 'normal'],
                            capture_output=True, text=True, timeout=180)
    evidence = None
    for line in result.stdout.splitlines():
        if 'EVIDENCE=' in line:
            evidence = Path(line.split('EVIDENCE=', 1)[1].strip())
    detail = None
    if evidence and (evidence / 'result.json').exists():
        detail = json.loads((evidence / 'result.json').read_text())
    return result.returncode, detail, evidence


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('helper', type=Path)
    args = parser.parse_args()
    root, helper = args.root.resolve(), args.helper.resolve()
    work = Path(tempfile.mkdtemp(prefix='installed-sleep-', dir=HERE.parent / 'build'))
    real = Path.home() / 'Library/Application Support/Lampyris'
    protected = [real / 'config.toml', real / 'user-dictionary.tsv']
    before_data = [stamp(path) for path in protected]
    evidence = {'scope': 'one sleep/wake cycle judged by the TextEdit probe; not full product acceptance'}
    error = None
    try:
        before = state(helper, root)
        evidence.update({'preSource': before['current'], 'preHost': host_pids(),
                         'preTime': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
                         'preProbe': probe_commit(root, helper)[1]})
        if not evidence['preProbe'] or not evidence['preProbe'].get('passed'):
            raise ValueError('睡前 TextEdit 探针未通过')

        print('即将进入睡眠；请在方便时唤醒机器，探针会自动继续。', flush=True)
        subprocess.run(['/usr/bin/pmset', 'sleepnow'], check=False, capture_output=True)
        time.sleep(10)

        after = state(helper, root)
        # 唤醒后 macOS 可能把输入源重置为系统键盘（实测 ABC）：把「原源」重新锚定到当前值，
        # 否则探针会在前置条件上直接 BLOCK，测不到真正的唤醒行为。
        journal_path = root / 'selection-state.json'
        journal = json.loads(journal_path.read_text())
        source_reset = after['current'] != journal['current']
        if source_reset:
            journal['current'] = after['current']
            fd = os.open(journal_path, os.O_WRONLY | os.O_TRUNC)
            with os.fdopen(fd, 'w') as stream:
                json.dump(journal, stream, sort_keys=True)
            journal_path.chmod(0o600)
        evidence['sourceResetOnWake'] = source_reset
        code, detail, path = probe_commit(root, helper)
        evidence.update({'postSource': after['current'], 'postHost': host_pids(),
                         'postTime': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
                         'postProbe': detail, 'postEvidence': str(path) if path else None})
        if code != 0 or not detail or not detail.get('passed'):
            raise ValueError('唤醒后 TextEdit 探针未通过')
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as failure:
        error = str(failure)
    finally:
        evidence['realDataUnchanged'] = before_data == [stamp(path) for path in protected]
        try:
            evidence['finalSource'] = state(helper, root)['current']
        except (OSError, ValueError, subprocess.SubprocessError):
            evidence['finalSource'] = None
        passed = (error is None and evidence.get('realDataUnchanged')
                  and evidence.get('postProbe', {}).get('passed'))
        evidence.update({'passed': passed, 'error': error})
        result = work / 'result.json'
        result.write_text(json.dumps(evidence, ensure_ascii=False) + '\n')
        os.chmod(result, 0o600)
        print(('PASS' if passed else 'BLOCKED') + '; EVIDENCE=' + str(work))
    return 0 if passed else 3


if __name__ == '__main__':
    raise SystemExit(main())
