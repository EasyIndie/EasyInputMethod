#!/usr/bin/env python3
"""Protect an existing isolated test fixture from blind backup restoration."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def digest(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError('测试配置必须为已有普通文件，不接受符号链接')
    return hashlib.sha256(path.read_bytes()).hexdigest()


def atomic_write(path, data, mode):
    fd, name = tempfile.mkstemp(prefix='.lampyris-restore-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as output:
            os.fchmod(output.fileno(), mode)
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def main(args):
    operation, journal = args[0], Path(args[1])
    if operation == 'save':
        path = Path(args[2]).absolute()
        before = digest(path)
        data = path.read_bytes()
        if hashlib.sha256(data).hexdigest() != before:
            raise ValueError('读取期间配置改变')
        backup = journal.with_suffix('.original')
        # Refuse accidental reuse of a journal or backup.
        with backup.open('xb') as output:
            os.fchmod(output.fileno(), 0o600)
            output.write(data)
        state = {'path': str(path), 'backup': str(backup), 'expected': before,
                 'mode': path.stat().st_mode & 0o777}
        with journal.open('x') as output:
            os.fchmod(output.fileno(), 0o600)
            json.dump(state, output)
        return 0
    state = json.loads(journal.read_text())
    path = Path(state['path'])
    if digest(path) != state['expected']:
        raise ValueError('配置已有未登记修改，保留新内容及备份')
    if operation == 'run':
        status = subprocess.run(args[2:], check=False).returncode
        # A failed mutation may have partially written; do not claim ownership.
        if status:
            return status
        state['expected'] = digest(path)
        atomic_write(journal, json.dumps(state).encode(), 0o600)
    elif operation == 'restore':
        backup = Path(state['backup']).read_bytes()
        atomic_write(path, backup, state['mode'])
    else:
        raise ValueError('未知配置恢复操作')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main(sys.argv[1:]))
    except (OSError, ValueError, IndexError) as error:
        print(f'BLOCKED 配置恢复保护：{error}', file=sys.stderr)
        sys.exit(3)
