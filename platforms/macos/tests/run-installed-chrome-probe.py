#!/usr/bin/env python3
"""Verify one owned offline Chrome tab with the installed isolated IMK package.

Chrome hides page content from non-assistive AX clients, so the fixture reports the focused
element and the textarea value through the tab title, which AppleScript can read.
"""
import argparse
import hashlib
import json
import os
import signal
from pathlib import Path
import subprocess
import tempfile

LIBRARY = Path(__file__).with_name('owned-resources.sh').resolve()
BODY = r'''
set -u
source "$1"
WORK="$2"; helper="$3"; root="$4"
channel=""
close_fixture() {
    [ -n "$channel" ] || return 0
    osascript - "$channel" <<'APPLESCRIPT' > "$WORK/closed.txt" 2>&1
on run argv
    set prefix to item 1 of argv
    tell application "Google Chrome"
        set remaining to 0
        repeat with candidate in (every window)
            if (title of active tab of candidate) starts with prefix then
                close candidate
            else
                set remaining to remaining + 1
            end if
        end repeat
        return "closed:" & (remaining as text)
    end tell
end run
APPLESCRIPT
}
cleanup() {
    status=$?
    "$helper" restore-original "$root" > "$WORK/restored.json" || status=99
    close_fixture || status=99
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

"$helper" select-owned "$root" > "$WORK/selected.json" || exit 98
python3 "$(dirname "$1")/chrome-fixture.py" "$WORK" > "$WORK/fixture.json" || exit 98
url=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["url"])' "$WORK/fixture.json")
title=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["title"])' "$WORK/fixture.json")
channel="fx|$title|fixture-input|"
osascript - "$url" "$channel" <<'APPLESCRIPT' || exit 98
on run argv
    set fixtureURL to item 1 of argv
    set expected to item 2 of argv
    tell application "Google Chrome"
        set created to make new window
        set URL of active tab of created to fixtureURL
        set index of created to 1
        activate
        delay 0.8
        -- 输入上下文在窗口创建后才连接：重载一次让 IMK 宿主接管该页面（报告 103 实测）。
        tell active tab of created to reload
        delay 1.2
        if not frontmost then error "BLOCKED Chrome非前台"
        set actual to title of active tab of front window
        if actual is not expected then error "BLOCKED 标题通道不符: " & actual
    end tell
end run
APPLESCRIPT

osascript - "$channel" <<'APPLESCRIPT' || exit 98
on run argv
    set expected to item 1 of argv
    tell application "Google Chrome"
        if not frontmost then error "BLOCKED Chrome非前台"
        set actual to title of active tab of front window
        if actual is not expected then error "BLOCKED 前台页面不是本 fixture: " & actual
        tell application "System Events"
            keystroke "w"
            delay 0.2
            keystroke "q"
            delay 0.3
        end tell
        set composing to title of active tab of front window
        if composing is not expected then error "BLOCKED 组合期出现提交: " & composing
        tell application "System Events" to key code 49
        delay 0.6
        set committed to title of active tab of front window
        if committed is not (expected & "你") then error "BLOCKED 提交文本不符: " & committed
        return committed
    end tell
end run
APPLESCRIPT
printf '%s' "$channel你" > "$WORK/commit.txt"
(umask 077; printf true > "$WORK/committed.txt")
'''

SCENARIOS = {'normal': None, 'failure': 'exit 7', 'INT': 'kill -INT $$', 'TERM': 'kill -TERM $$'}


def body_for(scenario):
    action = SCENARIOS[scenario]
    if action is None:
        return BODY
    checkpoint = ('(umask 077; printf true > "$WORK/prefix-verified.txt")\n' + action + '\n')
    return BODY.replace('(umask 077; printf true > "$WORK/committed.txt")', checkpoint)


def run(arguments):
    return subprocess.run(arguments, check=True, capture_output=True, text=True, timeout=15)


def require_ui_scripting():
    result = run(['/usr/bin/osascript', '-e', 'with timeout of 5 seconds',
                  '-e', 'tell application "System Events" to get UI elements enabled',
                  '-e', 'end timeout'])
    if result.stdout.strip() != 'true':
        raise RuntimeError('当前osascript执行链UI脚本不可用；未创建页面或切换输入源')


def stamp(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('helper', type=Path)
    parser.add_argument('--scenario', choices=sorted(SCENARIOS), default='normal')
    args = parser.parse_args()
    try:
        require_ui_scripting()
    except (OSError, RuntimeError, subprocess.SubprocessError) as failure:
        print('BLOCKED: ' + str(failure))
        return 3

    def interrupted(signum, _frame):
        raise RuntimeError(f'探针收到信号{signum}')

    signal.signal(signal.SIGINT, interrupted)
    signal.signal(signal.SIGTERM, interrupted)
    root, helper = args.root.resolve(), args.helper.resolve()
    work = Path(tempfile.mkdtemp(prefix='installed-chrome-', dir=LIBRARY.parent.parent / 'build'))
    real = Path.home() / 'Library/Application Support/Lampyris'
    protected = [real / 'config.toml', real / 'user-dictionary.tsv']
    before_data = [stamp(path) for path in protected]
    before = None
    error = None
    status = None
    started = False
    try:
        before = json.loads(run([str(helper), 'state', str(root)]).stdout)
        journal = json.loads((root / 'selection-state.json').read_text())
        if before['current'] != journal['current'] or len(before['owned']) != 2 or not all(item['enabled'] for item in before['owned']):
            raise ValueError('原源不匹配或独有父源/模式未启用')
        process = subprocess.Popen(['bash', '-c', body_for(args.scenario), 'isolated-chrome', str(LIBRARY),
                                    str(work), str(helper), str(root)],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        started = True
        try:
            _, diagnostic = process.communicate(timeout=90)
            (work / 'driver-stderr.txt').write_text(diagnostic)
            os.chmod(work / 'driver-stderr.txt', 0o600)
        except (subprocess.TimeoutExpired, RuntimeError) as interruption:
            process.send_signal(signal.SIGTERM)
            try:
                process.communicate(timeout=20)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate(timeout=5)
            raise RuntimeError('探针超时或中断，清理结果须核查') from interruption
        status = process.returncode
        expected = {'normal': 0, 'failure': 7, 'INT': 130, 'TERM': 143}[args.scenario]
        if status != expected:
            raise RuntimeError(f'单页面探针退出码{status}')
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as failure:
        error = str(failure)
    finally:
        restored = False
        try:
            action = 'restore-original' if started else 'state'
            after = json.loads(run([str(helper), action, str(root)]).stdout)
            restored = before is not None and after['current'] == before['current'] and after['enabled'] == before['enabled']
        except (OSError, ValueError, subprocess.SubprocessError):
            error = error or '输入源恢复失败，保留现场'
        unchanged = before_data == [stamp(path) for path in protected]
        closed = (work / 'closed.txt').exists() and (work / 'closed.txt').read_text().strip().startswith('closed')
        committed = (work / 'committed.txt').exists() and (work / 'commit.txt').exists() and \
            (work / 'commit.txt').read_text().strip().endswith('|fixture-input|你')
        prefix = (work / 'prefix-verified.txt').exists()
        if args.scenario == 'normal':
            passed = error is None and restored and unchanged and closed and committed
        else:
            passed = error is None and restored and unchanged and closed and prefix and not committed
        evidence = {'passed': passed, 'status': status, 'scenario': args.scenario,
                    'sourceAndEnabledRestored': restored, 'realDataUnchanged': unchanged,
                    'ownedWindowClosed': closed, 'committedTextVerified': committed,
                    'compositionVerified': prefix, 'error': error,
                    'scope': 'isolated Chrome prefix/commit through the tab-title channel; '
                             'not full product acceptance'}
        (work / 'result.json').write_text(json.dumps(evidence, ensure_ascii=False) + '\n')
        os.chmod(work / 'result.json', 0o600)
        print(('PASS' if passed else 'BLOCKED') + '; EVIDENCE=' + str(work))
    return 0 if passed else 3


if __name__ == '__main__':
    raise SystemExit(main())
