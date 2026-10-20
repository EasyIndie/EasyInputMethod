#!/usr/bin/env python3
"""Verify one owned VS Code file with the installed isolated IMK package.

VS Code has no AppleScript dictionary and does not expose the editor to AX here, so the probe
drives its own temporary file, saves with the standard shortcut and reads the bytes back.
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
fixture=""; fixtureName=""
close_fixture() {
    [ -n "$fixture" ] || return 0
    osascript - "$fixtureName" <<'APPLESCRIPT' > "$WORK/closed.txt" 2>&1
on run argv
    set wanted to item 1 of argv
    tell application "System Events"
        if not (exists process "Code") then return "absent"
        tell process "Code"
            if (count of windows) is 0 then return "absent"
            -- 只关闭标题里带本次 fixture 文件名的窗口（不碰用户窗口）。
            set matched to 0
            repeat with candidate in (every window)
                if (name of candidate) contains wanted then
                    set matched to matched + 1
                    try
                        perform action "AXRaise" of candidate
                    end try
                end if
            end repeat
            if matched is 0 then error "BLOCKED 没有本 fixture 的窗口"
            keystroke "w" using command down
        end tell
    end tell
    return "closed"
end run
APPLESCRIPT
}
cleanup() {
    status=$?
    close_fixture || status=99
    "$helper" restore-original "$root" > "$WORK/restored.json" || status=99
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

"$helper" select-owned "$root" > "$WORK/selected.json" || exit 98
fixture="$WORK/vscode-fixture-$$.txt"
fixtureName=$(basename "$fixture")
(umask 077; printf 'seed\n' > "$fixture")
open -a "Visual Studio Code" "$fixture" || exit 98

focused=""
for _ in $(seq 1 60); do
    sleep 1
    focused=$(osascript - "$fixtureName" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set wanted to item 1 of argv
    tell application "System Events"
        if not (exists process "Code") then return ""
        if (count of windows of process "Code") is 0 then return ""
        set frontmost of process "Code" to true
        if not frontmost of process "Code" then return ""
        if (name of front window of process "Code") does not contain wanted then return ""
        return "ready"
    end tell
end run
APPLESCRIPT
)
    [ "$focused" = "ready" ] && break
done
if [ "$focused" != "ready" ]; then
    osascript -e 'tell application "System Events" to tell process "Code" to get name of every window' > "$WORK/windows.txt" 2>&1 || true
    osascript -e 'tell application "System Events" to get {name, frontmost} of first application process whose frontmost is true' > "$WORK/frontmost.txt" 2>&1 || true
    echo "BLOCKED VS Code 窗口未就绪或不是本 fixture" >&2
    exit 98
fi
sleep 0.8

# 组合期：候选窗出现但文件不应被写入。
osascript -e 'tell application "System Events" to keystroke "w"' || exit 98
sleep 0.3
osascript -e 'tell application "System Events" to keystroke "q"' || exit 98
sleep 0.6
[ "$(cat "$fixture")" = "seed" ] || { echo "BLOCKED 组合期写入了文件" >&2; exit 98; }
(umask 077; printf true > "$WORK/composing.txt")

osascript -e 'tell application "System Events" to key code 49' || exit 98
sleep 0.6
osascript -e 'tell application "System Events" to keystroke "s" using command down' || exit 98
saved=""
for _ in $(seq 1 20); do
    sleep 0.3
    saved=$(head -c 64 "$fixture")
    [ "$saved" != "seed" ] && break
done
case "$saved" in
    你*) printf '%s' "$saved" > "$WORK/saved.txt"; (umask 077; printf true > "$WORK/committed.txt") ;;
    *) printf '%s' "$saved" > "$WORK/saved.txt"; echo "BLOCKED 提交内容不符: $saved" >&2; exit 98 ;;
esac
'''


def run(arguments):
    return subprocess.run(arguments, check=True, capture_output=True, text=True, timeout=15)


def require_ui_scripting():
    result = run(['/usr/bin/osascript', '-e', 'with timeout of 5 seconds',
                  '-e', 'tell application "System Events" to get UI elements enabled',
                  '-e', 'end timeout'])
    if result.stdout.strip() != 'true':
        raise RuntimeError('当前osascript执行链UI脚本不可用；未创建文件或切换输入源')


def body_for(scenario):
    if scenario == 'normal':
        return BODY
    action = {'failure': 'exit 7', 'INT': 'kill -INT $$', 'TERM': 'kill -TERM $$'}[scenario]
    return BODY.replace('(umask 077; printf true > "$WORK/composing.txt")',
                        '(umask 077; printf true > "$WORK/composing.txt")\n' + action)


def stamp(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('helper', type=Path)
    parser.add_argument('--scenario', choices=['normal', 'failure', 'INT', 'TERM'], default='normal')
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
    work = Path(tempfile.mkdtemp(prefix='installed-vscode-', dir=LIBRARY.parent.parent / 'build'))
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
        process = subprocess.Popen(['bash', '-c', body_for(args.scenario), 'isolated-vscode', str(LIBRARY),
                                    str(work), str(helper), str(root)],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        started = True
        try:
            _, diagnostic = process.communicate(timeout=120)
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
            raise RuntimeError(f'单文件探针退出码{status}')
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
        closed = (work / 'closed.txt').exists() and (work / 'closed.txt').read_text().strip() in {'closed', 'absent'}
        composing = (work / 'composing.txt').exists()
        committed = (work / 'committed.txt').exists() and (work / 'saved.txt').exists() and \
            (work / 'saved.txt').read_text().startswith('你')
        if args.scenario == 'normal':
            passed = error is None and restored and unchanged and closed and composing and committed
        else:
            passed = error is None and restored and unchanged and closed and composing and not committed
        evidence = {'passed': passed, 'status': status, 'scenario': args.scenario,
                    'sourceAndEnabledRestored': restored, 'realDataUnchanged': unchanged,
                    'ownedWindowClosed': closed, 'compositionVerified': composing,
                    'committedTextVerified': committed, 'error': error,
                    'scope': 'isolated VS Code commit through an owned file; not full product acceptance'}
        (work / 'result.json').write_text(json.dumps(evidence, ensure_ascii=False) + '\n')
        os.chmod(work / 'result.json', 0o600)
        print(('PASS' if passed else 'BLOCKED') + '; EVIDENCE=' + str(work))
    return 0 if passed else 3


if __name__ == '__main__':
    raise SystemExit(main())
