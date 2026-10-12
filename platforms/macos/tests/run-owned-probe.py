#!/usr/bin/env python3
"""Bounded native protocol probe; no typing or existing-document reads."""
from pathlib import Path
import shutil
import tempfile
import subprocess
import sys

PROBE = Path(__file__).with_name('probe-owned-textedit.applescript')
SUCCESS = 'PASS TextEdit窗口关联及仅清理自建文档'


def probe(mode, timeout=15):
    if mode not in ('normal', 'failure'):
        print('BLOCKED 未知协议探针模式', file=sys.stderr)
        return 3
    directory = Path(tempfile.mkdtemp(prefix="lampyris-owned-probe-"))
    fixture = directory / (directory.name + ".txt")
    fixture.touch(mode=0o600)
    print(f"探针临时资源：{fixture}", file=sys.stderr)
    try:
        result = subprocess.run(['osascript', str(PROBE), mode, str(fixture), fixture.name], capture_output=True,
                                text=True, timeout=timeout)
    except (subprocess.TimeoutExpired, OSError) as error:
        print(f'BLOCKED 原生协议探针无有效结果：{type(error).__name__}；不清理未知窗口', file=sys.stderr)
        return 3
    if result.returncode != 0 or result.stdout.strip() != SUCCESS:
        print('BLOCKED 原生协议探针失败：' + result.stderr.strip(), file=sys.stderr)
        return 3
    shutil.rmtree(directory)
    print(f'{SUCCESS}（{mode}）')
    return 0


if __name__ == '__main__':
    # Stop after the first failure; never claim a partial run is complete.
    for mode in ('normal', 'failure'):
        status = probe(mode)
        if status:
            sys.exit(status)
