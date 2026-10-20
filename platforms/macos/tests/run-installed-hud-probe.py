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
shots="$root/hud-shots-$$"
cleanup() {
    status=$?
    if [ -n "${DARK_BEFORE:-}" ]; then
        osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to ${DARK_BEFORE}" >/dev/null 2>&1 || status=99
    fi
    "$helper" restore-original "$root" > "$WORK/restored.json" || status=99
    if [ -n "${shots:-}" ] && [ -d "$shots" ]; then rm -rf "$shots"; fi
    owned_cleanup || status=99
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
"$helper" select-owned "$root" > "$WORK/selected.json" || exit 98
owned_textedit_create || exit 98
osascript -e 'with timeout of 5 seconds' -e 'tell application "TextEdit" to activate' -e 'end timeout' || exit 98
sleep 0.6
[ -z "$(owned_do read)" ] || exit 98
sleep 0.4
"$hud" windows "$root" > "$WORK/baseline.json" || exit 98
compose() {
    owned_do key 13 || exit 98
    sleep 0.2
    owned_do key 12 || exit 98
    sleep 0.5
}
compose
"$hud" windows "$root" > "$WORK/candidate-0.json" || exit 98
"$hud" capture "$root" "$shots/candidate-0" > "$WORK/capture-candidate-0.json" || exit 98
owned_do mode || exit 98
sleep 0.25
"$hud" windows "$root" > "$WORK/hud-0.json" || exit 98
"$hud" capture "$root" "$shots/hud-0" > "$WORK/capture-hud-0.json" || exit 98
if [ -n "${SECOND_AX_X:-}" ]; then
    osascript -e "with timeout of 5 seconds" -e "tell application \"System Events\" to tell process \"TextEdit\"
set position of window id $OWNED_ID to {$SECOND_AX_X, $SECOND_AX_Y}
end tell" -e 'end timeout' || exit 98
    sleep 0.8
    compose
    "$hud" windows "$root" > "$WORK/candidate-1.json" || exit 98
    owned_do mode || exit 98
    sleep 0.25
    "$hud" windows "$root" > "$WORK/hud-1.json" || exit 98
    "$hud" capture "$root" "$shots/hud-1" > "$WORK/capture-hud-1.json" || exit 98
fi
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' || exit 98
sleep 1.5
owned_do mode || exit 98
sleep 0.25
"$hud" windows "$root" > "$WORK/hud-dark.json" || exit 98
"$hud" capture "$root" "$shots/hud-dark" > "$WORK/capture-hud-dark.json" || exit 98
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


def fresh(report, baseline_numbers):
    """Hidden leftovers are ignored; visible windows are identified by geometry, not by number."""
    return [w for w in report['windows'] if w.get('onScreen')]


def pick(windows, kind):
    """Candidate panel and state HUD are told apart by height (70pt vs 32pt on this build)."""
    if kind == 'candidate':
        return [w for w in windows if w.get('onScreen') and w['layer'] == 101
                and w['height'] >= 60 and w['width'] >= 200 and w['alpha'] > 0.9]
    return [w for w in windows if w.get('onScreen') and w['layer'] == 101
            and w['height'] <= 60 and w['width'] <= 600 and w['alpha'] > 0.9]


def client_frontmost(report):
    return report['frontmost'] in ('TextEdit', '文本编辑')


def check_screen(name, windows, expected_screen, kind, problems):
    picked = pick(windows, kind)
    if len(picked) != 1:
        problems.append(f'{name}: 面板数量={len(picked)}（期望 1）')
        return None
    window = picked[0]
    if window['screen'] != expected_screen:
        problems.append(f'{name}: 屏 {window["screen"]}（期望 {expected_screen}）')
    return window


def collect(directory, work):
    problems = []
    baseline = {w['number'] for w in load(work / 'baseline.json')['windows']}
    screens = load(work / 'baseline.json')['screens']
    candidate_0 = load(work / 'candidate-0.json')
    hud_0 = load(work / 'hud-0.json')
    if not client_frontmost(candidate_0) or not client_frontmost(hud_0):
        problems.append('候选/HUD 出现时前台不是 TextEdit')
    candidate = check_screen('candidate-0', fresh(candidate_0, baseline), 0, 'candidate', problems)
    hud = check_screen('hud-0', fresh(hud_0, baseline), 0, 'hud', problems)
    second = None
    if (work / 'candidate-1.json').exists():
        candidate_1 = load(work / 'candidate-1.json')
        hud_1 = load(work / 'hud-1.json')
        if not client_frontmost(candidate_1) or not client_frontmost(hud_1):
            problems.append('第二屏：前台不是 TextEdit')
        check_screen('candidate-1', fresh(candidate_1, baseline), 1, 'candidate', problems)
        second = check_screen('hud-1', fresh(hud_1, baseline), 1, 'hud', problems)
    hud_dark = load(work / 'hud-dark.json')
    dark_screen = 1 if (work / 'hud-1.json').exists() else 0
    dark = check_screen('hud-dark', fresh(hud_dark, baseline), dark_screen, 'hud', problems)
    captures = {}
    for name in ('hud-0', 'hud-dark'):
        data = load(work / f'capture-{name}.json')
        captures[name] = [(c['file'], (directory / c['file']).stat().st_size) for c in data.get('captures', [])]
    if not captures['hud-0'] or not captures['hud-dark']:
        problems.append('亮/暗截图缺失')
    elif [size for _, size in captures['hud-0']] == [size for _, size in captures['hud-dark']]:
        problems.append('亮/暗 HUD 截图字节数相同，疑似外观未切换')
    return {
        'problems': problems,
        'screens': screens,
        'candidate0': candidate,
        'hud0': hud,
        'hud1': second,
        'hudDark': dark,
        'captures': {name: [file for file, _ in items] for name, items in captures.items()},
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
        screens = json.loads(run([str(hud), 'windows', str(root)]).stdout)['screens']
        environment = {**os.environ, 'DARK_BEFORE': dark_mode()}
        if args.second_display:
            if len(screens) < 2:
                raise ValueError('当前只有一块屏幕，无法验证双屏')
            second = [s for s in screens if s['index'] == 1][0]
            environment['SECOND_AX_X'] = str(int(second['axX'] + 60))
            environment['SECOND_AX_Y'] = str(int(second['axY'] + 60))
        process = subprocess.Popen(['bash', '-c', BODY, 'isolated-hud', str(LIBRARY), str(work),
                                    str(helper), str(root), str(hud)],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                   env=environment)
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
            details = collect(work, work)
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
