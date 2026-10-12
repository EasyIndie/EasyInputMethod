#!/usr/bin/env python3
"""Verify a new Terminal window/TTY/process binding without sending input."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import time

BASE = Path(__file__).resolve().parent


def call(operation, *arguments):
    result = subprocess.run(['/usr/bin/osascript', str(BASE / 'owned-terminal.applescript'), operation, *arguments], check=True, capture_output=True, text=True, timeout=12)
    return result.stdout.strip()


def process_matches(process_tty, process_command, terminal_tty, runtime, receiver):
    expected = ' '.join([str(runtime), str(BASE / 'terminal-input-sink.py'), str(receiver)])
    return process_tty == terminal_tty.removeprefix('/dev/') and process_command == expected


def main():
    work = Path(tempfile.mkdtemp(prefix='terminal-ownership-', dir=BASE.parent / 'build'))
    receiver = work / 'receiver'
    receiver.mkdir(mode=0o700)
    interpreter = Path(sys.executable).resolve()
    framework_runtime = interpreter.parent.parent / 'Resources/Python.app/Contents/MacOS/Python'
    runtime = framework_runtime if framework_runtime.is_file() else interpreter
    command = 'exec ' + shlex.join([sys.executable, str(BASE / 'terminal-input-sink.py'), str(receiver)])
    window = None
    terminal_tty = None
    evidence = {'passed': False, 'scope': 'Terminal window/TTY/process ownership only; no input or source changes'}
    try:
        response = call('create', command)
        window, terminal_tty = response.split(', ', 1)
        if not window.isdecimal() or not terminal_tty.startswith('/dev/ttys'):
            raise ValueError('Terminal窗口/TTY格式不符')
        evidence.update(windowID=window, tty=terminal_tty)
        deadline = time.monotonic() + 8
        while not (receiver / 'ready.json').exists():
            if time.monotonic() > deadline:
                raise RuntimeError('接收器未就绪')
            time.sleep(0.1)
        ready = json.loads((receiver / 'ready.json').read_text())
        if ready['tty'] != terminal_tty or not isinstance(ready['pid'], int):
            raise ValueError('接收器TTY/PID不符')
        process = subprocess.run(['/bin/ps', '-p', str(ready['pid']), '-o', 'tty=', '-o', 'command='], check=True, capture_output=True, text=True, timeout=5).stdout.strip()
        process_tty, process_command = process.split(None, 1)
        expected = ' '.join([str(runtime), str(BASE / 'terminal-input-sink.py'), str(receiver)])
        (work / 'process-identity.json').write_text(json.dumps({'observedTTY': process_tty, 'expectedTTY': terminal_tty, 'observedCommand': process_command, 'expectedCommand': expected}))
        (work / 'process-identity.json').chmod(0o600)
        if not process_matches(process_tty, process_command, terminal_tty, runtime, receiver):
            raise ValueError('接收器进程身份不符')
        evidence['bindingVerified'] = call('check', window, terminal_tty) == 'owned'
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as failure:
        evidence['error'] = str(failure)
        if isinstance(failure, subprocess.CalledProcessError):
            evidence['nativeDiagnostic'] = failure.stderr.strip()
    finally:
        (receiver / 'stop').touch(mode=0o600, exist_ok=True)
        deadline = time.monotonic() + 8
        while not (receiver / 'result.json').exists() and time.monotonic() < deadline:
            time.sleep(0.1)
        if (receiver / 'result.json').exists():
            result = json.loads((receiver / 'result.json').read_text())
            evidence['receiver'] = result
            if window and terminal_tty:
                try:
                    # Let Terminal observe exec process termination before busy check.
                    time.sleep(0.3)
                    evidence['closed'] = call('close', window, terminal_tty) in {'closed', 'absent'}
                except subprocess.SubprocessError as failure:
                    evidence['cleanupError'] = str(failure)
            evidence['passed'] = bool(evidence.get('bindingVerified') and evidence.get('closed') and result['classification'] == 'empty' and result['ttyRestored'] and not evidence.get('error'))
        target = work / 'result.json'
        target.write_text(json.dumps(evidence, ensure_ascii=False, indent=2))
        target.chmod(0o600)
        print(('PASS' if evidence['passed'] else 'BLOCKED') + '; EVIDENCE=' + str(work))
    return 0 if evidence['passed'] else 3


if __name__ == '__main__':
    raise SystemExit(main())
