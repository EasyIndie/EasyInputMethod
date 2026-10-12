#!/usr/bin/env python3
"""Verify one owned offline Safari textarea with the installed isolated IMK package."""
import argparse
import hashlib
import json
import os
import signal
from pathlib import Path
import subprocess
import tempfile

LIBRARY = Path(__file__).with_name('owned-resources.sh').resolve()
BODY = '''umask 077
script="$(dirname "$1")/owned-safari.applescript"
WORK="$2"
helper="$3"
root="$4"
window=""
cleanup() {
    status=$?
    "$helper" restore-original "$root" > "$WORK/restored.json" || status=99
    if [ -n "$window" ]; then
        osascript "$script" close "$url" "$window" > "$WORK/closed.txt" || status=99
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
python3 "$(dirname "$1")/safari-fixture.py" "$WORK" > "$WORK/fixture.json" || exit 98
url="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["url"])' "$WORK/fixture.json")"
title="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["title"])' "$WORK/fixture.json")"
"$helper" select-owned "$root" > "$WORK/selected.json" || exit 98
window="$(osascript "$script" create "$url")" || exit 98
case "$window" in ''|*[!0-9]*) exit 98 ;; esac
osascript -e 'with timeout of 5 seconds' -e 'tell application "Safari" to activate' -e 'end timeout' || exit 98
sleep 0.5
osascript "$script" focus "$url" "$window" "$title" > "$WORK/focused.txt" || exit 98
owned_do() { osascript "$script" "$1" "$url" "$window" "$title" "${2:-}" || exit 98; }
[ -z "$(owned_do read)" ] || exit 98
check_source() {
    "$helper" state "$root" | python3 -c 'import json,sys; expected=json.load(open(sys.argv[1]))["current"]; actual=json.load(sys.stdin)["current"]; sys.exit(0 if actual == expected else 3)' "$WORK/selected.json" || exit 98
}
check_source
owned_do key 13
sleep 0.2
check_source
owned_do key 12
sleep 0.2
check_source
owned_do key 49
sleep 0.5
[ "$(owned_do read)" = '你' ] || exit 97
'''


def scenario_body(scenario):
    if scenario == 'normal':
        return BODY
    actions = {'failure': 'exit 7', 'INT': 'kill -INT $$', 'TERM': 'kill -TERM $$'}
    checkpoint = '[ "$(owned_do read)" = wq ] || exit 96\n(umask 077; printf true > "$WORK/prefix-verified.txt")\n' + actions[scenario]
    return BODY.replace('check_source\nowned_do key 49', checkpoint + '\ncheck_source\nowned_do key 49')


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
    parser.add_argument('--scenario', choices=['normal', 'failure', 'INT', 'TERM'], default='normal')
    args = parser.parse_args()
    try:
        require_ui_scripting()
    except (OSError, RuntimeError, subprocess.SubprocessError) as failure:
        print("BLOCKED: " + str(failure))
        return 3
    def interrupted(signum, _frame):
        raise RuntimeError(f'探针收到信号{signum}')
    signal.signal(signal.SIGINT, interrupted)
    signal.signal(signal.SIGTERM, interrupted)
    root, helper = args.root.resolve(), args.helper.resolve()
    work = Path(tempfile.mkdtemp(prefix='installed-safari-', dir=LIBRARY.parent.parent / 'build'))
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
        identity = journal['identity']
        if before['current'] != journal['current'] or len(before['owned']) != 2 or not all(item['enabled'] for item in before['owned']):
            raise ValueError('原源不匹配或独有父源/模式未启用')
        suffix = root.name.removeprefix('lampyris-imk-')
        app = Path.home() / f'Library/Input Methods/LampyrisIMKTest-{suffix}.app'
        import plistlib
        metadata = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        if metadata['CFBundleIdentifier'] != identity or (app / 'Contents/Resources/IMKTestRoot').read_text() != str(root):
            raise ValueError('已装包身份或绑定不符')
        run(['codesign', '--verify', '--strict', str(app)])
        process = subprocess.Popen(['bash', '-c', scenario_body(args.scenario), 'isolated-safari', str(LIBRARY), str(work), str(helper), str(root)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        started = True
        try:
            _, diagnostic = process.communicate(timeout=45)
            (work / "driver-stderr.txt").write_text(diagnostic)
            os.chmod(work / "driver-stderr.txt", 0o600)
        except (subprocess.TimeoutExpired, RuntimeError) as interruption:
            process.send_signal(signal.SIGTERM)
            try:
                process.communicate(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate(timeout=5)
            raise RuntimeError('探针超时或中断，清理结果须核查') from interruption
        status = process.returncode
        expected = {'normal': 0, 'failure': 7, 'INT': 130, 'TERM': 143}[args.scenario]
        if status != expected:
            raise RuntimeError(f'单文档探针退出码{status}')
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
        focused = (work / 'focused.txt').exists() and (work / 'focused.txt').read_text().strip() == 'focused'
        closed = (work / 'closed.txt').exists() and (work / 'closed.txt').read_text().strip() in {'closed', 'absent'}
        passed = error is None and restored and unchanged and focused and closed
        evidence = {'passed': passed, 'status': status, 'sourceAndEnabledRestored': restored, 'realDataUnchanged': unchanged, 'error': error, 'focusedTextareaVerified': focused, 'ownedWindowClosed': closed, 'scenario': args.scenario, 'prefixVerified': (work / 'prefix-verified.txt').exists(), 'scope': 'isolated Safari prefix recovery or basic commit only; not final product acceptance'}
        (work / 'result.json').write_text(json.dumps(evidence, ensure_ascii=False) + '\n')
        os.chmod(work / 'result.json', 0o600)
        print(('PASS' if passed else 'BLOCKED') + '; EVIDENCE=' + str(work))
    return 0 if passed else 3


if __name__ == '__main__':
    raise SystemExit(main())
