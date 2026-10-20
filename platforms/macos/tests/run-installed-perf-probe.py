#!/usr/bin/env python3
"""Host-level baseline for the installed isolated package: commit latency, memory and idle CPU.

Latency is sampled by a helper that polls the focused text field until its value changes, so it
includes the client's own update path but not IMK dispatch internals; the scope says so.
"""
import argparse
import base64
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
BODY = r'''
set -u
source "$1"
WORK="$2"; helper="$3"; root="$4"; waiter="$5"
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
# 精确进程名匹配：`pgrep -f` 会命中探针自己的 bash 命令行。
host=$(pgrep -x LampyrisIMKTest | head -1)
client=$(pgrep -f "TextEdit.app/Contents/MacOS/TextEdit" | head -1)
[ -n "$host" ] && [ -n "$client" ] || exit 98
printf '%s' "$host" > "$WORK/host-pid.txt"
printf '%s' "$client" > "$WORK/client-pid.txt"
ps -o rss= -p "$host" > "$WORK/rss-kib.txt" 2>/dev/null || true

# 1) 控制组：只测「等待器自身 + 空 osascript」的固定开销。
attempt=0
while [ "$attempt" -lt 4 ]; do
    attempt=$((attempt + 1))
    refocus || exit 98
    "$waiter" wait "$client" 4000 > "$WORK/control-$attempt.txt" &
    pid=$!
    osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' >/dev/null 2>&1 || true
    # 控制组不产生文本变化：直接结束等待器。
    sleep 0.4
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    printf 'skip' > "$WORK/control-$attempt.txt"
done

# 2) 提交时延：wq + 空格，测「空格发出 → 文档出现『你』」。
attempt=0
while [ "$attempt" -lt 15 ]; do
    attempt=$((attempt + 1))
    refocus || exit 98
    owned_do char w || exit 98
    sleep 0.15
    refocus || exit 98
    owned_do char q || exit 98
    sleep 0.3
    "$waiter" wait "$client" 4000 > "$WORK/latency-$attempt.txt" &
    pid=$!
    sleep 0.02
    osascript -e 'tell application "System Events" to key code 49' || exit 98
    wait "$pid" || { echo "BLOCKED 第 $attempt 次提交未观察到文本变化" >&2; exit 98; }
    sleep 0.3
done

# 3) 空闲 CPU 与稳态内存（无按键 6 秒）。
ps -o rss= -p "$host" > "$WORK/rss-idle-before-kib.txt" 2>/dev/null || true
idle=""
for _ in $(seq 1 6); do
    idle="$idle $(ps -o %cpu= -p "$host" | tr -d ' ')"
    sleep 1
done
printf '%s' "$idle" > "$WORK/idle-cpu.txt"
ps -o rss= -p "$host" > "$WORK/rss-idle-after-kib.txt" 2>/dev/null || true
(umask 077; printf true > "$WORK/passed.txt")
'''


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


def osascript_overhead(samples=5):
    """启动 + 执行一次空 osascript 的固定开销；时延样本里包含这部分。"""
    values = []
    for _ in range(samples):
        start = time.perf_counter()
        subprocess.run(['/usr/bin/osascript', '-e', 'return 1'], capture_output=True, check=False)
        values.append(round((time.perf_counter() - start) * 1000, 1))
    return percentiles(values)


def percentiles(values):
    if not values:
        return {}
    ordered = sorted(values)
    def at(fraction):
        index = min(len(ordered) - 1, max(0, int(round(fraction * (len(ordered) - 1)))))
        return ordered[index]
    return {'count': len(ordered), 'p50': at(0.5), 'p95': at(0.95), 'max': ordered[-1],
            'min': ordered[0], 'mean': round(statistics.fmean(ordered), 2)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('helper', type=Path)
    parser.add_argument('waiter', type=Path)
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
    work = Path(tempfile.mkdtemp(prefix='installed-perf-', dir=LIBRARY.parent.parent / 'build'))
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
        process = subprocess.Popen(['bash', '-c', BODY, 'isolated-perf', str(LIBRARY), str(work),
                                    str(helper), str(root), str(args.waiter.resolve())],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        started = True
        try:
            _, diagnostic = process.communicate(timeout=300)
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
            raise RuntimeError(f'性能探针退出码{status}')
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
        latencies = []
        for path in sorted(work.glob('latency-*.txt')):
            text = path.read_text().strip()
            try:
                latencies.append(float(text))
            except ValueError:
                error = error or f'时延样本无效：{path.name}={text}'
        idle = [float(value) for value in (work / 'idle-cpu.txt').read_text().split()] \
            if (work / 'idle-cpu.txt').exists() else []
        rss = {}
        for name in ('rss-kib', 'rss-idle-before-kib', 'rss-idle-after-kib'):
            path = work / f'{name}.txt'
            if path.exists() and path.read_text().strip().isdigit():
                rss[name] = round(int(path.read_text().strip()) / 1024, 1)
        ok = (error is None and restored and unchanged and (work / 'passed.txt').exists()
              and len(latencies) >= 12)
        evidence = {'passed': ok, 'status': status, 'error': error,
                    'sourceAndEnabledRestored': restored, 'realDataUnchanged': unchanged,
                    'commitLatencyMs': percentiles(latencies),
                    'idleCpuPercent': {'samples': idle, 'mean': round(statistics.fmean(idle), 2) if idle else None},
                    'hostRssMiB': rss,
                    'osascriptOverheadMs': osascript_overhead(),
                    'environment': {'system': platform.platform(), 'python': platform.python_version()},
                    'scope': 'host-level sampling on device A: key-to-text latency via AX polling '
                             '(includes client update, excludes IMK dispatch internals), host RSS and idle CPU'}
        (work / 'result.json').write_text(json.dumps(evidence, ensure_ascii=False) + '\n')
        os.chmod(work / 'result.json', 0o600)
        print(('PASS' if ok else 'BLOCKED') + '; EVIDENCE=' + str(work))
    return 0 if ok else 3


if __name__ == '__main__':
    raise SystemExit(main())
