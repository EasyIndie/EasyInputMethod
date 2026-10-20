#!/usr/bin/env python3
"""Verify real IMK candidate panel and state HUD on the installed isolated package."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile

LIBRARY = Path(__file__).with_name('owned-resources.sh').resolve()
BODY = r'''
set -u
source "$1"
WORK="$2"; helper="$3"; root="$4"; hud="$5"
shots="$WORK/captures"
mkdir -p "$shots"
cleanup() {
    status=$?
    if [ -n "${DARK_BEFORE:-}" ]; then
        osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to ${DARK_BEFORE}" >/dev/null 2>&1 || status=99
    fi
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
# 窗口刚建好时 TextEdit 可能还没拿到键盘焦点（AXFocusedUIElement 为 missing value）：轮询再断言。
focused=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
    osascript -e 'tell application "TextEdit" to activate' >/dev/null 2>&1 || true
    sleep 0.3
    focused=$(osascript -e 'tell application "System Events" to tell process "TextEdit" to get value of attribute "AXFocusedUIElement"' 2>/dev/null || true)
    [ "$focused" != "missing value" ] && [ -n "$focused" ] && break
done
[ "$focused" != "missing value" ] && [ -n "$focused" ] || { echo "BLOCKED TextEdit 未取得键盘焦点" >&2; exit 98; }
[ -z "$(owned_do read)" ] || exit 98
sleep 0.4
refocus() {
    osascript -e 'tell application "TextEdit" to activate' >/dev/null 2>&1 || true
    local value=""
    for _ in 1 2 3 4 5 6; do
        sleep 0.2
        value=$(osascript -e 'tell application "System Events" to tell process "TextEdit" to get value of attribute "AXFocusedUIElement"' 2>/dev/null || true)
        [ "$value" != "missing value" ] && [ -n "$value" ] && return 0
    done
    return 1
}
"$hud" windows "$root" > "$WORK/baseline.json" || exit 98
refocus || { echo "BLOCKED TextEdit 未取得键盘焦点" >&2; exit 98; }
# 起点固定在内建屏（确定性）：先按 bounds 把测试窗口挪过去。
move_window() {
    osascript -e "with timeout of 5 seconds" -e "tell application \"TextEdit\"
set oldBounds to bounds of window id $OWNED_ID
set windowWidth to (item 3 of oldBounds) - (item 1 of oldBounds)
set windowHeight to (item 4 of oldBounds) - (item 2 of oldBounds)
set bounds of window id $OWNED_ID to {$1, $2, $1 + windowWidth, $2 + windowHeight}
end tell" -e 'end timeout'
}
PRIMARY_X=$("$hud" windows "$root" | python3 -c '
import json,sys
d=json.load(sys.stdin)
s=[x for x in d["screens"] if x["index"]==0][0]
print(int(s["axX"]+60), int(s["axY"]+60))')
move_window $PRIMARY_X || exit 98
sleep 0.5
osascript -e 'tell application "System Events" to tell process "TextEdit" to get {position, size} of window 1' > "$WORK/client-window.txt" 2>&1 || true

compose() {
    refocus || { echo "BLOCKED 组合前失去焦点" >&2; exit 98; }
    owned_do key 13 || exit 98
    sleep 0.2
    owned_do key 12 || exit 98
    sleep 0.5
}

# 默认配置的模式快捷键是 ⌥M（schema hotkey.toggle_mode = alt+m）。守卫与按键在同一次
# AppleScript 里：前台、窗口身份、聚焦控件任一不符就 BLOCK，不重试、不重新聚焦。
hud_toggle() {
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

# 截 HUD 所在屏幕矩形：直接用刚拿到的窗口 JSON（CG 坐标），避免再查一次窗口导致错过 1.15s 存活期。
shot() {
    rect=$(python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
picked=[w for w in d["windows"] if 1<=w["height"]<=60 and w["onScreen"]]
if not picked: raise SystemExit(1)
w=picked[-1]
print("%d,%d,%d,%d" % (w["x"], w["y"], w["width"], w["height"]))' "$1") || return 1
    /usr/sbin/screencapture -x -o -R "$rect" "$2"
}

# 明确亮色起点；cleanup恢复DARK_BEFORE，包括失败路径。
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to false' || exit 98
sleep 1.5
compose
"$hud" windows "$root" > "$WORK/candidate-0.json" || exit 98
hud_toggle
sleep 0.2
"$hud" windows "$root" > "$WORK/hud-0.json" || exit 98
shot "$WORK/hud-0.json" "$shots/hud-0.png" || exit 98

if [ "${SECOND_DISPLAY:-0}" = "1" ]; then
    SECOND_AX_X=$("$hud" windows "$root" | python3 -c '
import json,sys
d=json.load(sys.stdin)
s=[x for x in d["screens"] if x["index"]==1]
print(int(s[0]["axX"]+60) if s else "")')
    SECOND_AX_Y=$("$hud" windows "$root" | python3 -c '
import json,sys
d=json.load(sys.stdin)
s=[x for x in d["screens"] if x["index"]==1]
print(int(s[0]["axY"]+60) if s else "")')
    if [ -n "$SECOND_AX_X" ]; then
        # 移动窗口用 TextEdit 自己的 bounds（AX 的 set position 在这个应用上会失败）。
        osascript -e "with timeout of 5 seconds" -e "tell application \"TextEdit\"
set oldBounds to bounds of window id $OWNED_ID
set windowWidth to (item 3 of oldBounds) - (item 1 of oldBounds)
set windowHeight to (item 4 of oldBounds) - (item 2 of oldBounds)
set bounds of window id $OWNED_ID to {$SECOND_AX_X, $SECOND_AX_Y, $SECOND_AX_X + windowWidth, $SECOND_AX_Y + windowHeight}
end tell" -e 'end timeout' || exit 98
        sleep 0.8
        compose
        "$hud" windows "$root" > "$WORK/candidate-1.json" || exit 98
        hud_toggle
        sleep 0.2
        "$hud" windows "$root" > "$WORK/hud-1.json" || exit 98
        shot "$WORK/hud-1.json" "$shots/hud-1.png" || exit 98
    fi
fi

osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' || exit 98
sleep 1.5
hud_toggle
sleep 0.2
"$hud" windows "$root" > "$WORK/hud-dark.json" || exit 98
shot "$WORK/hud-dark.json" "$shots/hud-dark.png" || exit 98
'''


def run(arguments):
    return subprocess.run(arguments, check=True, capture_output=True, text=True, timeout=15)


def require_ui_scripting():
    result = run(['/usr/bin/osascript', '-e', 'with timeout of 5 seconds',
                  '-e', 'tell application "System Events" to get UI elements enabled',
                  '-e', 'end timeout'])
    if result.stdout.strip() != 'true':
        raise RuntimeError('当前osascript执行链UI脚本不可用；未创建文档或切换输入源')


def dark_mode():
    result = run(['/usr/bin/osascript', '-e',
                  'tell application "System Events" to tell appearance preferences to get dark mode'])
    return 'true' if result.stdout.strip().lower() == 'true' else 'false'


def load(path):
    return json.loads(path.read_text())


def fresh(report):
    """Hidden leftovers are ignored; visible windows are identified by geometry, not by number."""
    return [window for window in report['windows'] if window.get('onScreen')]


def pick(windows, kind):
    """Candidate panel and state HUD are told apart by height (70pt vs 36pt on this build)."""
    if kind == 'candidate':
        return [w for w in windows if w['layer'] == 101 and w['height'] >= 60
                and w['width'] >= 200 and w['alpha'] > 0.9]
    return [w for w in windows if w['layer'] == 101 and w['height'] <= 60
            and w['width'] <= 600 and w['alpha'] > 0.9]


def check_screen(name, windows, expected_screen, kind, problems):
    picked = pick(windows, kind)
    if len(picked) != 1:
        problems.append(f'{name}: 面板数量={len(picked)}（期望 1）')
        return None
    window = picked[0]
    if expected_screen is not None and window['screen'] != expected_screen:
        problems.append(f'{name}: 屏 {window["screen"]}（期望 {expected_screen}）')
    return window


def client_frontmost(report):
    return report['frontmost'] in ('TextEdit', '文本编辑')


def client_screen(work, screens):
    """Screen index containing the client window (AppleScript positions use AX top-left coordinates)."""
    text = work / 'client-window.txt'
    if not text.exists():
        return None
    numbers = [int(value) for value in ''.join(ch if ch.isdigit() or ch == '-'
                                               else ' ' for ch in text.read_text()).split()]
    if len(numbers) < 4:
        return None
    x, y, width, height = numbers[:4]
    center_x, center_y = x + width / 2, y + height / 2
    for screen in screens:
        if (screen['axX'] <= center_x <= screen['axX'] + screen['width']
                and screen['axY'] <= center_y <= screen['axY'] + screen['height']):
            return screen['index']
    return None


def collect(work):
    problems = []
    screens = load(work / 'baseline.json')['screens']
    expected = client_screen(work, screens)
    if expected is None:
        problems.append('无法确定客户端窗口所在屏')
    candidate_0, hud_0 = load(work / 'candidate-0.json'), load(work / 'hud-0.json')
    if not client_frontmost(candidate_0) or not client_frontmost(hud_0):
        problems.append('候选/HUD 出现时前台不是 TextEdit')
    candidate = check_screen('candidate-0', fresh(candidate_0), expected, 'candidate', problems)
    hud = check_screen('hud-0', fresh(hud_0), expected, 'hud', problems)
    second = None
    if (work / 'hud-1.json').exists():
        candidate_1, hud_1 = load(work / 'candidate-1.json'), load(work / 'hud-1.json')
        if not client_frontmost(candidate_1) or not client_frontmost(hud_1):
            problems.append('第二屏：前台不是 TextEdit')
        check_screen('candidate-1', fresh(candidate_1), 1, 'candidate', problems)
        second = check_screen('hud-1', fresh(hud_1), 1, 'hud', problems)
    hud_dark = load(work / 'hud-dark.json')
    dark_expected = 1 if (work / 'hud-1.json').exists() else expected
    dark = check_screen('hud-dark', fresh(hud_dark), dark_expected, 'hud', problems)
    captures = {}
    for name in ('hud-0', 'hud-1', 'hud-dark'):
        path = work / 'captures' / f'{name}.png'
        captures[name] = path.stat().st_size if path.is_file() else 0
    if not captures['hud-0'] or not captures['hud-dark']:
        problems.append('亮/暗 HUD 截图缺失')
    elif captures['hud-0'] == captures['hud-dark']:
        problems.append('亮/暗 HUD 截图字节数相同，疑似外观未切换')
    return {
        'problems': problems,
        'screens': screens,
        'clientScreen': expected,
        'candidate0': candidate,
        'hud0': hud,
        'hud1': second,
        'hudDark': dark,
        'captures': {name: size for name, size in captures.items() if size},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('helper', type=Path)
    parser.add_argument('hud', type=Path)
    parser.add_argument('--second-display', action='store_true', help='同时验证第二屏 HUD 定位')
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
    root, helper, hud = args.root.resolve(), args.helper.resolve(), args.hud.resolve()
    work = Path(tempfile.mkdtemp(prefix='installed-hud-', dir=LIBRARY.parent.parent / 'build'))
    evidence = work / 'evidence.json'
    status = None
    error = None
    started = False
    try:
        before = json.loads(run([str(helper), 'state', str(root)]).stdout)
        journal = load(root / 'selection-state.json')
        if before['current'] != journal['current'] or len(before['owned']) != 2 or not all(item['enabled'] for item in before['owned']):
            raise ValueError('原源不匹配或独有父源/模式未启用')
        environment = {**os.environ, 'DARK_BEFORE': dark_mode(),
                       'SECOND_DISPLAY': '1' if args.second_display else '0'}
        process = subprocess.Popen(['bash', '-c', BODY, 'isolated-hud', str(LIBRARY), str(work),
                                    str(helper), str(root), str(hud)],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                   env=environment)
        started = True
        try:
            _, diagnostic = process.communicate(timeout=150)
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
            raise RuntimeError(f'HUD 探针退出码{status}')
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
        details = {}
        try:
            details = collect(work)
        except (OSError, ValueError, KeyError) as failure:
            error = error or f'证据解析失败：{failure}'
        problems = details.get('problems', [])
        if problems:
            error = (error + '；' if error else '') + '；'.join(problems)
        passed = error is None and restored and not problems
        result = {'passed': passed, 'status': status, 'error': error,
                  'sourceAndEnabledRestored': restored,
                  'secondDisplay': args.second_display,
                  'focusStayedInClient': all(client_frontmost(load(work / name))
                                             for name in ('candidate-0.json', 'hud-0.json')
                                             if (work / name).exists()),
                  'clientScreen': details.get('clientScreen'),
                  'candidate': details.get('candidate0'), 'hud': details.get('hud0'),
                  'hudSecondDisplay': details.get('hud1'), 'hudDark': details.get('hudDark'),
                  'captures': details.get('captures', {}),
                  'scope': 'real IMK candidate/HUD window identity, placement and appearance; '
                           'not full product acceptance'}
        evidence.write_text(json.dumps(result, ensure_ascii=False) + '\n')
        os.chmod(evidence, 0o600)
        print(('PASS' if passed else 'BLOCKED') + '; EVIDENCE=' + str(work))
    return 0 if passed else 3


if __name__ == '__main__':
    raise SystemExit(main())
