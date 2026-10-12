#!/usr/bin/env python3
"""Verify a new Terminal window/TTY/process binding without sending input."""
import argparse
import importlib.util
import signal
import plistlib
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


def acceptance_passed(evidence, result, scenario):
    state = all(evidence.get(name) for name in ('bindingVerified', 'closed', 'focusVerified', 'sourceAndEnabledRestored', 'realDataUnchanged'))
    if scenario == 'normal':
        input_valid = result['classification'] == 'committed'
    else:
        input_valid = evidence.get('prefixVerified') and 'injected' in evidence and result['classification'] in {'empty', 'prefix'}
    return bool(state and input_valid and result['ttyRestored'] and not evidence.get('error'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('helper', type=Path)
    parser.add_argument('--scenario', choices=['normal', 'failure', 'INT', 'TERM'], default='normal')
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('guards', BASE / 'run-installed-safari-probe.py')
    guards = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(guards)
    guards.require_ui_scripting()
    root, helper = args.root.resolve(), args.helper.resolve()
    def source(action):
        return json.loads(guards.run([str(helper), action, str(root)]).stdout)
    before = source('state')
    journal = json.loads((root / 'selection-state.json').read_text())
    if before['current'] != journal['current'] or len(before['owned']) != 2 or not all(entry['enabled'] for entry in before['owned']):
        raise ValueError('独有源/恢复日志不符')
    app = Path.home() / ('Library/Input Methods/LampyrisIMKTest-' + root.name.removeprefix('lampyris-imk-') + '.app')
    metadata = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if metadata['CFBundleIdentifier'] != journal['identity'] or (app / 'Contents/Resources/IMKTestRoot').read_text() != str(root):
        raise ValueError('已装包身份/绑定不符')
    guards.run(['codesign', '--verify', '--strict', str(app)])
    real = Path.home() / 'Library/Application Support/Lampyris'
    protected = [real / 'config.toml', real / 'user-dictionary.tsv']
    data_before = [guards.stamp(path) for path in protected]
    class InjectedInterruption(Exception):
        pass
    def interrupted(signum, _frame):
        raise InjectedInterruption(signum)
    signal.signal(signal.SIGINT, interrupted)
    signal.signal(signal.SIGTERM, interrupted)
    work = Path(tempfile.mkdtemp(prefix='installed-terminal-', dir=BASE.parent / 'build'))
    receiver = work / 'receiver'
    receiver.mkdir(mode=0o700)
    interpreter = Path(sys.executable).resolve()
    framework_runtime = interpreter.parent.parent / 'Resources/Python.app/Contents/MacOS/Python'
    runtime = framework_runtime if framework_runtime.is_file() else interpreter
    command = 'exec ' + shlex.join([sys.executable, str(BASE / 'terminal-input-sink.py'), str(receiver)])
    window = None
    terminal_tty = None
    evidence = {'passed': False, 'scenario': args.scenario, 'scope': 'isolated Terminal fixed commit/prefix recovery; not final candidate'}
    try:
        selected = source('select-owned')
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
        guards.run(['/usr/bin/osascript', '-e', 'with timeout of 5 seconds', '-e', 'tell application "Terminal" to activate', '-e', 'end timeout'])
        time.sleep(0.3)
        identity_arguments = [window, terminal_tty, str(ready['pid']), process]
        evidence['focusVerified'] = call('focus', *identity_arguments) == 'focused'
        def key(code):
            if source('state')['current'] != selected['current']:
                raise ValueError('输入源改变，停止发键')
            call('key', *identity_arguments, str(code))
            time.sleep(0.2)
        key(13)
        key(12)
        if args.scenario != 'normal':
            evidence['prefixVerified'] = call('prefix', *identity_arguments) == 'true'
            if not evidence['prefixVerified']:
                raise ValueError('Terminal预编辑前缀未确认')
            if args.scenario == 'failure':
                raise InjectedInterruption(0)
            os.kill(os.getpid(), signal.SIGINT if args.scenario == 'INT' else signal.SIGTERM)
        key(49)
        time.sleep(0.3)
    except InjectedInterruption as interruption:
        evidence['injected'] = int(interruption.args[0])
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as failure:
        evidence['error'] = str(failure)
        if isinstance(failure, subprocess.CalledProcessError):
            evidence['nativeDiagnostic'] = failure.stderr.strip()
    finally:
        try:
            after = source('restore-original')
            evidence['sourceAndEnabledRestored'] = after['current'] == before['current'] and after['enabled'] == before['enabled']
        except Exception as failure:
            evidence['restoreError'] = str(failure)
        evidence['realDataUnchanged'] = data_before == [guards.stamp(path) for path in protected]
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
            evidence['passed'] = acceptance_passed(evidence, result, args.scenario)
        target = work / 'result.json'
        target.write_text(json.dumps(evidence, ensure_ascii=False, indent=2))
        target.chmod(0o600)
        print(('PASS' if evidence['passed'] else 'BLOCKED') + '; EVIDENCE=' + str(work))
    return 0 if evidence['passed'] else 3


if __name__ == '__main__':
    raise SystemExit(main())
