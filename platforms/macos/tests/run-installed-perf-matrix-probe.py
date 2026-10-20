#!/usr/bin/env python3
"""IT-12 matrix sampling on the installed isolated package: cold start, full dictionary,
first variant switch, panels and wake. Latency is sampled by the AX poller, so it is an upper
bound that includes the client update path but not IMK dispatch internals.
"""
import argparse
import hashlib
import json
import os
import platform
import signal
import statistics
from pathlib import Path
import subprocess
import tempfile
import time

LIBRARY = Path(__file__).with_name('owned-resources.sh').resolve()
FIXTURE = Path(__file__).with_name('make-user-fixture.py').resolve()
HOST_PATTERN = 'LampyrisIMKTest-.*MacOS/LampyrisIMKTest'

PRELUDE = r'''
set -u
source "$1"
WORK="$2"; helper="$3"; root="$4"; waiter="$5"; scenario="$6"
cleanup() {
    status=$?
    rm -f "$root/perf-trace.enabled" 2>/dev/null || true
    if [ -n "${SYNTHETIC:-}" ] && [ -f "$root/user-dictionary.tsv.synthetic" ]; then
        mv -f "$root/user-dictionary.tsv.synthetic" "$root/user-dictionary.tsv" 2>/dev/null || true
    fi
    "$helper" restore-original "$root" > "$WORK/restored.json" || status=99
    owned_cleanup || status=99
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

refocus() {
    local role="" front=""
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        osascript -e 'tell application "TextEdit" to activate' >/dev/null 2>&1 || true
        sleep 0.25
        # 唤醒后前台可能是登录窗口/终端：必须同时满足「前台是本进程」和「文本区拿到焦点」。
        front=$(osascript -e 'tell application "System Events" to tell process "TextEdit" to get frontmost' 2>/dev/null || true)
        role=$(osascript -e 'tell application "System Events" to tell process "TextEdit" to get role of (value of attribute "AXFocusedUIElement")' 2>/dev/null || true)
        [ "$front" = "true" ] && [ "$role" = "AXTextArea" ] && return 0
    done
    return 1
}
select_owned() { "$helper" select-owned "$root" > "$WORK/selected.json" || exit 98; }
# 宿主由「客户端连接」触发启动：杀掉/未起来时切回原源再选一次，最多等 12 秒。
ensure_host() {
    for _ in $(seq 1 12); do
        [ -n "$(host_pid)" ] && return 0
        # 宿主由客户端连接拉起：真的敲一下（随后删掉）才会建立连接。
        refocus >/dev/null 2>&1 || true
        osascript -e 'tell application "System Events" to keystroke "a"' >/dev/null 2>&1 || true
        sleep 0.4
        osascript -e 'tell application "System Events" to key code 51' >/dev/null 2>&1 || true
        sleep 0.4
    done
    if [ -z "$(host_pid)" ]; then
        # 系统按需启动偶发失效（反复 SIGTERM 之后）：用 open 启动同一隔离包，方法如实记录。
        local uuid app
        uuid="${root##*lampyris-imk-}"
        app="$HOME/Library/Input Methods/LampyrisIMKTest-$uuid.app"
        [ -d "$app" ] && open "$app" 2>/dev/null && sleep 2
        printf 'opened by probe' > "$WORK/host-launch-fallback.txt"
    fi
    [ -n "$(host_pid)" ]
}
client_pid() { pgrep -x TextEdit | head -1; }
host_pid() { pgrep -x LampyrisIMKTest | head -1; }
rss_mib() {
    local pid=""
    for _ in 1 2 3 4 5 6 7 8; do
        pid=$(host_pid)
        [ -n "$pid" ] && break
        sleep 0.3
    done
    [ -n "$pid" ] || { echo 0; return; }
    ps -o rss= -p "$pid" | tr -d ' ' | awk '{printf "%.1f", $1/1024}'
}
stop_host() { pkill -x LampyrisIMKTest 2>/dev/null || true; sleep 0.5; }

# 一次「wq + 空格」提交，输出等待器测得的毫秒数；超时则返回非零。
commit_latency() {
    local client out
    client=$(client_pid)
    [ -n "$client" ] || return 1
    timeout_pid=""
    refocus || return 1
    "$waiter" wait "$client" 8000 > "$WORK/lat-$1.tmp" &
    timeout_pid=$!
    sleep 0.02
    osascript -e 'tell application "System Events" to key code 49' >/dev/null 2>&1 || true
    wait "$timeout_pid" || return 1
    out=$(cat "$WORK/lat-$1.tmp")
    rm -f "$WORK/lat-$1.tmp"
    printf '%s' "$out" > "$WORK/lat-$1.txt"
    [ -n "$out" ]
}
compose() {
    refocus || return 1
    owned_do char w || return 1
    sleep 0.12
    refocus || return 1
    owned_do char q || return 1
    sleep 0.25
}
# 一次完整取样：组合 + 空格，失败重试一次（焦点抖动时自行恢复，不伪造样本）。
one_commit() {
    local attempt=1
    while [ "$attempt" -le 2 ]; do
        compose || { attempt=$((attempt + 1)); continue; }
        commit_latency "$1" && return 0
        attempt=$((attempt + 1))
    done
    return 1
}

select_owned
owned_textedit_create || exit 98
osascript -e 'with timeout of 5 seconds' -e 'tell application "TextEdit" to activate' -e 'end timeout' || exit 98
ensure_host || { echo "BLOCKED 隔离宿主未启动" >&2; exit 98; }
'''

SCENARIOS = {
    'cold': r'''
# 冷启动：先让宿主连上，再杀掉宿主，测「重新起来后第一次提交」。
refocus || exit 98
one_commit 0 || exit 98
stop_host
printf '%s' "$(host_pid)" > "$WORK/host-after-kill.txt"
refocus || exit 98
ensure_host || { echo "BLOCKED 冷启动前宿主未重新启动" >&2; exit 98; }
one_commit 1 || exit 98
printf '%s' "$(rss_mib)" > "$WORK/rss-after-cold.txt"
(umask 077; printf true > "$WORK/passed.txt")
''',
    'dictionary': r'''
# 满词库：把真实词库暂时挪开、换成 1 万条合成词库，测完再恢复。
refocus || exit 98
one_commit 0 || exit 98
stop_host
if [ -f "$root/user-dictionary.tsv" ]; then
    mv -f "$root/user-dictionary.tsv" "$root/user-dictionary.tsv.synthetic"
    SYNTHETIC=1
fi
python3 "$FIXTURE_PATH" "$root/user-dictionary.tsv" > "$WORK/synthetic.txt" 2>&1 || exit 98
refocus || exit 98
ensure_host || { echo "BLOCKED 满词库场景宿主未启动" >&2; exit 98; }
one_commit 1 || exit 98
i=2
while [ "$i" -le 9 ]; do
    one_commit "$i" || exit 98
    i=$((i + 1))
done
printf '%s' "$(rss_mib)" > "$WORK/rss-with-dictionary.txt"
(umask 077; printf true > "$WORK/passed.txt")
''',
    'variant': r'''
# 首次简繁切换：暖机提交，然后切繁体，测切换后第一次提交。
refocus || exit 98
one_commit 0 || exit 98
one_commit 1 || exit 98
refocus || exit 98
osascript -e 'tell application "System Events" to keystroke "t" using {option down}' || exit 98
sleep 0.2
one_commit 2 || exit 98
i=3
while [ "$i" -le 8 ]; do
    one_commit "$i" || exit 98
    i=$((i + 1))
done
refocus || exit 98
osascript -e 'tell application "System Events" to keystroke "t" using {option down}' || exit 98
printf '%s' "$(rss_mib)" > "$WORK/rss-after-variant.txt"
(umask 077; printf true > "$WORK/passed.txt")
''',
    'wake': r'''
refocus || exit 98
i=0
while [ "$i" -le 6 ]; do
    one_commit "$i" || exit 98
    i=$((i + 1))
done
printf '%s' "$(rss_mib)" > "$WORK/rss-before-sleep.txt"
/usr/bin/pmset sleepnow > "$WORK/sleep.txt" 2>&1 || exit 98
sleep 10
refocus || { echo "BLOCKED 唤醒后取不到焦点" >&2; exit 98; }
i=7
while [ "$i" -le 13 ]; do
    one_commit "$i" || exit 98
    i=$((i + 1))
done
printf '%s' "$(rss_mib)" > "$WORK/rss-after-wake.txt"
(umask 077; printf true > "$WORK/passed.txt")
''',
    'trace': r'''
# 计时开关写在私有根内：宿主启动时读它（测试入口专有，产品路径不读）。
printf '%s' "$WORK/trace.jsonl" > "$root/perf-trace.enabled"
chmod 600 "$root/perf-trace.enabled"
stop_host
ensure_host || { echo "BLOCKED 带计时的宿主未起来" >&2; exit 98; }
i=0
while [ "$i" -le 14 ]; do
    one_commit "$i" || exit 98
    i=$((i + 1))
done
# 面板：默认 alt+, 打开设置；alt+a 打开关于。
refocus || exit 98
osascript -e 'tell application "System Events" to keystroke "," using {option down}' || exit 98
sleep 1.5
refocus >/dev/null 2>&1 || true
osascript -e 'tell application "System Events" to keystroke "a" using {option down}' || exit 98
sleep 1.5
# 只有真的拿到内嵌计时样本才算通过（插桩接线未生效时必须 BLOCK）。
[ -s "$WORK/trace.jsonl" ] || { echo "BLOCKED 宿主未产生内嵌计时样本（插桩接线待验证）" >&2; exit 98; }
lines=$(wc -l < "$WORK/trace.jsonl" | tr -d ' ')
[ "$lines" -ge 10 ] || { echo "BLOCKED 内嵌计时样本过少: $lines" >&2; exit 98; }
(umask 077; printf true > "$WORK/passed.txt")
''',
    'panels': r'''
# 面板：从输入法菜单打开设置窗口，测「菜单项按下 → 宿主新窗口出现」。
refocus || exit 98
one_commit 0 || exit 98
"$hud" windows "$root" > "$WORK/windows-before.json" || exit 98
AXMENU="${AXMENU_PATH:-}"
[ -n "$AXMENU" ] && [ -x "$AXMENU" ] || { echo "BLOCKED 缺少 axmenu 工具" >&2; exit 98; }
"$AXMENU" dump > "$WORK/axmenu.json" 2>&1 || { echo "BLOCKED 无法读取输入法菜单" >&2; exit 98; }
(umask 077; printf true > "$WORK/panels-dumped.txt")
''',
}


def run(arguments, timeout=30):
    return subprocess.run(arguments, check=True, capture_output=True, text=True, timeout=timeout)


def require_ui_scripting():
    result = run(['/usr/bin/osascript', '-e', 'with timeout of 5 seconds',
                  '-e', 'tell application "System Events" to get UI elements enabled',
                  '-e', 'end timeout'])
    if result.stdout.strip() != 'true':
        raise RuntimeError('当前osascript执行链UI脚本不可用')


def stamp(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None


def percentiles(values):
    if not values:
        return {}
    ordered = sorted(values)
    def at(fraction):
        return ordered[min(len(ordered) - 1, max(0, int(round(fraction * (len(ordered) - 1)))))]
    return {'count': len(ordered), 'p50': at(0.5), 'p95': at(0.95),
            'max': ordered[-1], 'min': ordered[0], 'mean': round(statistics.fmean(ordered), 2)}


def osascript_overhead(samples=3):
    values = []
    for _ in range(samples):
        start = time.perf_counter()
        subprocess.run(['/usr/bin/osascript', '-e', 'return 1'], capture_output=True, check=False)
        values.append(round((time.perf_counter() - start) * 1000, 1))
    return percentiles(values)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('helper', type=Path)
    parser.add_argument('waiter', type=Path)
    parser.add_argument('hud', type=Path)
    parser.add_argument('--scenario', choices=sorted(SCENARIOS), required=True)
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
    work = Path(tempfile.mkdtemp(prefix=f'imk12-{args.scenario}-', dir=LIBRARY.parent.parent / 'build'))
    real = Path.home() / 'Library/Application Support/Lampyris'
    protected = [real / 'config.toml', real / 'user-dictionary.tsv']
    before_data = [stamp(path) for path in protected]
    body = PRELUDE + SCENARIOS[args.scenario]
    before = None
    error = None
    status = None
    started = False
    try:
        before = json.loads(run([str(helper), 'state', str(root)]).stdout)
        journal = json.loads((root / 'selection-state.json').read_text())
        if before['current'] != journal['current'] or len(before['owned']) != 2 or not all(item['enabled'] for item in before['owned']):
            raise ValueError('原源不匹配或独有父源/模式未启用')
        environment = {**os.environ, 'LC_ALL': 'en_US.UTF-8', 'LANG': 'en_US.UTF-8',
                       'FIXTURE_PATH': str(FIXTURE),
                       'AXMENU_PATH': str(LIBRARY.parents[3] / 'tools' / 'macos-probe' / 'bin' / 'axmenu')}
        process = subprocess.Popen(['bash', '-c', body, f'it12-{args.scenario}', str(LIBRARY), str(work),
                                    str(helper), str(root), str(args.waiter.resolve()), args.scenario],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                   env=environment)
        started = True
        try:
            _, diagnostic = process.communicate(timeout=600)
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
            raise RuntimeError(f'{args.scenario} 场景退出码{status}')
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
        samples = {}
        for path in sorted(work.glob('lat-*.txt')):
            try:
                samples[int(path.stem.split('-')[1])] = float(path.read_text().strip())
            except (ValueError, IndexError):
                error = error or f'时延样本无效：{path.name}'
        ordered = [samples[index] for index in sorted(samples)]
        rss = {}
        for path in sorted(work.glob('rss-*.txt')):
            try:
                rss[path.stem.replace('rss-', '')] = float(path.read_text().strip())
            except ValueError:
                pass
        ok = error is None and restored and unchanged and (work / 'passed.txt').exists()
        evidence = {'passed': ok, 'scenario': args.scenario, 'status': status, 'error': error,
                    'sourceAndEnabledRestored': restored, 'realDataUnchanged': unchanged,
                    'latenciesMs': percentiles(ordered), 'samplesMs': ordered,
                    'rssMiB': rss, 'osascriptOverheadMs': osascript_overhead(),
                    'environment': {'system': platform.platform(), 'python': platform.python_version()},
                    'scope': 'IT-12 matrix sample on device A via AX polling (client update included, '
                             'IMK dispatch internals excluded); no product threshold is claimed'}
        trace = work / 'trace.jsonl'
        if trace.exists():
            engine, total, panels = [], [], []
            for line in trace.read_text().splitlines():
                try:
                    entry = json.loads(line)
                except ValueError:
                    continue
                if entry.get('panel'):
                    panels.append(entry.get('totalUs', 0) / 1000)
                else:
                    total.append(entry.get('totalUs', 0) / 1000)
                    if entry.get('engineUs', -1) >= 0:
                        engine.append(entry['engineUs'] / 1000)
            if total:
                evidence['inProcessMs'] = {'total': percentiles(total), 'engine': percentiles(engine),
                                           'panels': percentiles(panels)}
        for name in ('synthetic', 'axmenu', 'sleep', 'host-after-kill'):
            path = work / f'{name}.txt'
            if path.exists():
                evidence[name] = path.read_text()[:2000]
        (work / 'result.json').write_text(json.dumps(evidence, ensure_ascii=False) + '\n')
        os.chmod(work / 'result.json', 0o600)
        print(('PASS' if ok else 'BLOCKED') + '; EVIDENCE=' + str(work))
    return 0 if ok else 3


if __name__ == '__main__':
    raise SystemExit(main())
