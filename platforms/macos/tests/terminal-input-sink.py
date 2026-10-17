#!/usr/bin/env python3
"""Bounded TTY byte receiver; never evaluate received input."""
import argparse
import json
import os
from pathlib import Path
import select
import signal
import sys
import termios
import time
import tty


def write_private(path, value):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'w') as stream:
        json.dump(value, stream)


def tty_equivalent(left, right):
    # macOS sets transient PENDIN when restoring canonical input.
    first, second = list(left), list(right)
    first[3] &= ~getattr(termios, 'PENDIN', 0)
    second[3] &= ~getattr(termios, 'PENDIN', 0)
    return first == second


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    args = parser.parse_args()
    root = args.root.resolve(strict=True)
    metadata = root.stat()
    if args.root.is_symlink() or metadata.st_uid != os.getuid() or metadata.st_mode & 0o077:
        raise ValueError('接收器目录必须为当前用户私有目录')
    descriptor = sys.stdin.fileno()
    if not os.isatty(descriptor):
        raise ValueError('接收器要求TTY')
    original = termios.tcgetattr(descriptor)
    received = bytearray()
    outcome = 'timeout'
    was_interrupted = False
    def interrupted(_signum, _frame):
        nonlocal was_interrupted
        was_interrupted = True
    signal.signal(signal.SIGINT, interrupted)
    signal.signal(signal.SIGTERM, interrupted)
    try:
        tty.setcbreak(descriptor)
        settings = termios.tcgetattr(descriptor)
        settings[3] &= ~termios.ECHO
        termios.tcsetattr(descriptor, termios.TCSANOW, settings)
        write_private(root / 'ready.json', {'pid': os.getpid(), 'tty': os.ttyname(descriptor)})
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            if was_interrupted:
                outcome = 'interrupted'
                break
            if (root / 'stop').exists():
                outcome = 'stopped'
                break
            if select.select([descriptor], [], [], 0.1)[0]:
                chunk = os.read(descriptor, 64 - len(received))
                if not chunk:
                    outcome = 'eof'
                    break
                received.extend(chunk)
                if len(received) >= 64:
                    outcome = 'limit'
                    break
    except InterruptedError:
        outcome = 'interrupted'
    finally:
        termios.tcsetattr(descriptor, termios.TCSANOW, original)
    classification = {b'': 'empty', b'wq': 'prefix', '你'.encode(): 'committed'}.get(bytes(received), 'unexpected')
    write_private(root / 'result.json', {'classification': classification, 'outcome': outcome, 'ttyRestored': tty_equivalent(termios.tcgetattr(descriptor), original)})


if __name__ == '__main__':
    main()
