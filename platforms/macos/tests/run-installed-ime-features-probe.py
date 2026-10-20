#!/usr/bin/env python3
"""Re-verify long composition, undo and mode cycling on the installed isolated package.

Each scenario drives one owned TextEdit document and reads the text back through the same
owned-window guard as the other probes; mode cycling reads the host's own config file.
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
PRELUDE = r'''
set -u
source "$1"
WORK="$2"; helper="$3"; root="$4"
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
osascript -e 'with timeout of 5 seconds' -e 'tell application "TextEdit" to activate' -e 'end timeout' || exit 98
sleep 1.2
[ -z "$(owned_do read)" ] || exit 98
type_word() {
    for letter in $(printf '%s' "$1" | fold -w1); do
        owned_do char "$letter" || exit 98
        sleep 0.06
    done
}
guarded_toggle_mode() {
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
}
'''

LONG = r'''
type_word "zhongguo"
sleep 0.5
(umask 077; "$hud" windows "$root" > "$WORK/candidates.json") 2>/dev/null || true
owned_do key 49 || exit 98
sleep 0.6
short=$(owned_do read)
[ "$short" = "中国" ] || { printf '%s' "$short" > "$WORK/short.txt"; echo "BLOCKED 8 字母提交不符: $short" >&2; exit 98; }
printf '%s' "$short" > "$WORK/short.txt"
# 20 字母：超出组合上限时按设计退化为直通（报告 101 的既有行为），只要求有界、不崩、不吞后续输入。
type_word "zhongguorenmingonghe"
sleep 0.8
long=$(owned_do read)
printf '%s' "$long" > "$WORK/long-pending.txt"
case "$long" in
    "$short"|"$short""zhongguorenmingonghe") ;;
    *) echo "BLOCKED 20 字结果不符: $long" >&2; exit 98 ;;
esac
owned_do key 53 || exit 98
sleep 0.4
# Esc 取消组合后应回到 8 字母提交的文本（20 字母在组合期以标记文本呈现，AX 值里可见）。
after=$(owned_do read)
[ "$after" = "$short" ] || { printf '%s' "$after" > "$WORK/long-after-esc.txt"; echo "BLOCKED Esc 后未回到已提交文本: $after" >&2; exit 98; }
printf '%s' "$after" > "$WORK/long-after-esc.txt"
(umask 077; printf true > "$WORK/passed-long.txt")
'''

UNDO = r'''
type_word "wq"
sleep 0.2
owned_do key 49 || exit 98
sleep 0.6
committed=$(owned_do read)
[ "$committed" = "你" ] || { printf '%s' "$committed" > "$WORK/commit.txt"; echo "BLOCKED 提交不符: $committed" >&2; exit 98; }
printf '%s' "$committed" > "$WORK/commit.txt"
owned_do undo || exit 98
sleep 0.6
reverted=$(owned_do read)
printf '%s' "$reverted" > "$WORK/undo.txt"
[ "$reverted" = "" ] || { echo "BLOCKED ⌘Z 未回退: $reverted" >&2; exit 98; }
(umask 077; printf true > "$WORK/passed-undo.txt")
'''

MODE = r'''
current_mode() {
    python3 - "$root/config.toml" <<'PY'
import re, sys
from pathlib import Path
path = Path(sys.argv[1])
if not path.exists():
    print("")
else:
    match = re.search(r'^mode\s*=\s*"([a-z]+)"', path.read_text(), re.M)
    print(match.group(1) if match else "")
PY
}
initial=$(current_mode)
[ -n "$initial" ] || initial=mixed
printf '%s' "$initial" > "$WORK/mode-initial.txt"
guarded_toggle_mode
seq=""
for _ in $(seq 1 12); do
    sleep 0.3
    now=$(current_mode)
    [ "$now" != "$initial" ] && { seq="$now"; break; }
done
[ -n "$seq" ] || { echo "BLOCKED 模式未切换" >&2; exit 98; }
printf '%s' "$seq" > "$WORK/mode-after-one.txt"
# 再切两次回到起点，验证循环。
for _ in $(seq 1 4); do
    guarded_toggle_mode
    sleep 0.4
    now=$(current_mode)
    [ "$now" = "$initial" ] && break
done
final=$(current_mode)
printf '%s' "$final" > "$WORK/mode-final.txt"
[ "$final" = "$initial" ] || { echo "BLOCKED 模式未回到起点: $initial -> $final" >&2; exit 98; }
(umask 077; printf true > "$WORK/passed-mode.txt")
'''

BODIES = {'long': LONG, 'undo': UNDO, 'mode': MODE}


def run(arguments):
    return subprocess.run(arguments, check=True, capture_output=True, text=True, timeout=15)


def require_ui_scripting():
    result = run(['/usr/bin/osascript', '-e', 'with timeout of 5 seconds',
                  '-e', 'tell application "System Events" to get UI elements enabled',
                  '-e', 'end timeout'])
    if result.stdout.strip() != 'true':
        raise RuntimeError('当前osascript执行链UI脚本不可用；未创建文档或切换输入源')


def stamp(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('helper', type=Path)
    parser.add_argument('hud', type=Path)
    parser.add_argument('--scenario', choices=sorted(BODIES), required=True)
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
    work = Path(tempfile.mkdtemp(prefix=f'installed-{args.scenario}-',
                                 dir=LIBRARY.parent.parent / 'build'))
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
        body = PRELUDE + BODIES[args.scenario]
        process = subprocess.Popen(['bash', '-c', body, f'isolated-{args.scenario}', str(LIBRARY),
                                    str(work), str(helper), str(root), str(args.hud)],
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
        if status != 0:
            raise RuntimeError(f'{args.scenario} 探针退出码{status}')
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
        marker = work / f'passed-{args.scenario}.txt'
        verified = marker.exists()
        passed = error is None and restored and unchanged and verified
        evidence = {'passed': passed, 'status': status, 'scenario': args.scenario,
                    'sourceAndEnabledRestored': restored, 'realDataUnchanged': unchanged,
                    'verified': verified, 'error': error,
                    'scope': 'isolated IME behaviour through owned TextEdit; not full product acceptance'}
        for name in ('short.txt', 'long-after-esc.txt', 'commit.txt', 'undo.txt',
                     'mode-initial.txt', 'mode-after-one.txt', 'mode-final.txt'):
            path = work / name
            if path.exists():
                evidence[name.replace('.txt', '')] = path.read_text()
        (work / 'result.json').write_text(json.dumps(evidence, ensure_ascii=False) + '\n')
        os.chmod(work / 'result.json', 0o600)
        print(('PASS' if passed else 'BLOCKED') + '; EVIDENCE=' + str(work))
    return 0 if passed else 3


if __name__ == '__main__':
    raise SystemExit(main())
