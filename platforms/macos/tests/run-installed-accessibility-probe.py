#!/usr/bin/env python3
"""Verify VoiceOver-facing behaviour: state changes are announced and the client keeps focus.

Runs the AX announcement watcher while the isolated input method composes and toggles state in an
owned TextEdit document. VoiceOver itself must be enabled by the user; the probe only observes.
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
WORK="$2"; helper="$3"; root="$4"; watch="$5"
cleanup() {
    status=$?
    "$helper" restore-original "$root" > "$WORK/restored.json" || status=99
    owned_cleanup || status=99
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

"$helper" select-owned "$root" > "$WORK/selected.json" || exit 98
owned_textedit_create || exit 98
refocus() {
    local role=""
    for _ in 1 2 3 4 5 6 7 8; do
        osascript -e 'tell application "TextEdit" to activate' >/dev/null 2>&1 || true
        sleep 0.25
        role=$(osascript -e 'tell application "System Events" to tell process "TextEdit" to get role of (value of attribute "AXFocusedUIElement")' 2>/dev/null || true)
        [ "$role" = "AXTextArea" ] && return 0
    done
    return 1
}
refocus || exit 98
"$watch" watch 14 > "$WORK/events.json" 2> "$WORK/watch.log" &
watcher=$!
sleep 1.5
refocus || exit 98
owned_do key 13 || exit 98
sleep 0.2
refocus || exit 98
owned_do key 12 || exit 98
sleep 0.4
refocus || exit 98
osascript -e "on run argv
with timeout of 5 seconds
tell application \"TextEdit\"
if not frontmost then error \"BLOCKED 应用焦点不符\"
if (id of front window) is not $OWNED_ID then error \"BLOCKED 测试对象焦点不符\"
end tell
tell application \"System Events\"
tell process \"TextEdit\"
set focusedRole to role of (value of attribute \"AXFocusedUIElement\")
if focusedRole is not \"AXTextArea\" then error \"BLOCKED 聚焦控件不符\"
end tell
keystroke \"m\" using {option down}
end tell
end timeout
end run" || exit 98
wait "$watcher" || exit 98
role_after=$(osascript -e 'tell application "System Events" to tell process "TextEdit" to get role of (value of attribute "AXFocusedUIElement")' 2>/dev/null || true)
printf '%s' "$role_after" > "$WORK/focus-after.txt"
[ "$role_after" = "AXTextArea" ] || { echo "BLOCKED 状态切换后客户端焦点被夺走: $role_after" >&2; exit 98; }
(umask 077; printf true > "$WORK/passed.txt")
'''


def run(arguments):
    return subprocess.run(arguments, check=True, capture_output=True, text=True, timeout=15)


def require_ui_scripting():
    result = run(['/usr/bin/osascript', '-e', 'with timeout of 5 seconds',
                  '-e', 'tell application "System Events" to get UI elements enabled',
                  '-e', 'end timeout'])
    if result.stdout.strip() != 'true':
        raise RuntimeError('当前osascript执行链UI脚本不可用')


def voiceover_running():
    return bool(subprocess.run(['pgrep', '-f', 'VoiceOver.app/Contents/MacOS/VoiceOver'],
                               capture_output=True, text=True).stdout.strip())


def stamp(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('helper', type=Path)
    parser.add_argument('watch', type=Path)
    args = parser.parse_args()
    if not voiceover_running():
        print('BLOCKED: VoiceOver 未运行；请在系统设置 → 辅助功能里打开 VoiceOver 后重试')
        return 3
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
    work = Path(tempfile.mkdtemp(prefix='installed-accessibility-', dir=LIBRARY.parent.parent / 'build'))
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
        process = subprocess.Popen(['bash', '-c', BODY, 'isolated-accessibility', str(LIBRARY),
                                    str(work), str(helper), str(root), str(args.watch.resolve())],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        started = True
        try:
            _, diagnostic = process.communicate(timeout=180)
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
        if status != 0:
            raise RuntimeError(f'无障碍探针退出码{status}')
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
        events = []
        raw = work / 'events.json'
        if raw.exists():
            text = raw.read_text().strip()
            if text:
                try:
                    events = json.loads(text.splitlines()[-1]).get('events', [])
                except ValueError:
                    events = []
        announcements = [event for event in events if event.get('kind', '').endswith('AnnouncementRequested')]
        announced = [event.get('announcement', '') for event in announcements if event.get('announcement')]
        focus_after = (work / 'focus-after.txt').read_text() if (work / 'focus-after.txt').exists() else None
        passed = (error is None and restored and unchanged and (work / 'passed.txt').exists()
                  and bool(announced) and focus_after == 'AXTextArea')
        evidence = {'passed': passed, 'status': status, 'error': error,
                    'sourceAndEnabledRestored': restored, 'realDataUnchanged': unchanged,
                    'voiceOverRunning': voiceover_running(),
                    'announcements': announced, 'eventCount': len(events),
                    'focusAfterToggle': focus_after,
                    'scope': 'VoiceOver announcements and client focus; not a full VoiceOver reading review'}
        (work / 'result.json').write_text(json.dumps(evidence, ensure_ascii=False) + '\n')
        os.chmod(work / 'result.json', 0o600)
        print(('PASS' if passed else 'BLOCKED') + '; EVIDENCE=' + str(work))
    return 0 if passed else 3


if __name__ == '__main__':
    raise SystemExit(main())
