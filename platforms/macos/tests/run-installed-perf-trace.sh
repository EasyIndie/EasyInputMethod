#!/usr/bin/env bash
# IT-12 内嵌计时采集（ADR-218）：用已确认可用的顺序拿到「按键→候选窗更新完成」的真实样本。
#
# 顺序很关键：open 拉起公证隔离包 → 等注册完成 → 切一次输入源让客户端绑定 → 再用全新文档发键。
# 宿主偶尔不接客（同一顺序下也会发生），所以先做「一个键 + 候选窗」探测，最多重试 3 轮；
# 拿不到候选窗就如实失败退出，不写假样本。
#
# 用法：run-installed-perf-trace.sh <root> <helper> <hud-probe> <输出目录>
# 输出：<输出目录>/trace.jsonl（0600）+ 标准输出上的分位数摘要；退出码 0 表示采到 ≥30 行样本。
set -euo pipefail

ROOT="$1"; HELPER="$2"; HUD="$3"; OUT="$4"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBRARY="${HERE}/owned-resources.sh"
UUID="${ROOT##*lampyris-imk-}"
APP="${HOME}/Library/Input Methods/LampyrisIMKTest-${UUID}.app"
TRACE="${OUT}/trace.jsonl"

mkdir -p "$OUT"
chmod 700 "$OUT"
# owned-resources.sh 通过 WORK 定位临时文档，这里是探针的工作目录。
export WORK="$OUT"
rm -f "$TRACE"
printf '%s' "$TRACE" > "${ROOT}/perf-trace.enabled"
chmod 600 "${ROOT}/perf-trace.enabled"

# shellcheck source=/dev/null
source "$LIBRARY"

refocus() {
    local front="" role="" try
    for try in $(seq 1 8); do
        osascript -e 'tell application "TextEdit" to activate' >/dev/null 2>&1 || true
        sleep 0.25
        front=$(osascript -e 'tell application "System Events" to tell process "TextEdit" to get frontmost' 2>/dev/null || true)
        role=$(osascript -e 'tell application "System Events" to tell process "TextEdit" to get role of (value of attribute "AXFocusedUIElement")' 2>/dev/null || true)
        [ "$front" = "true" ] && [ "$role" = "AXTextArea" ] && return 0
    done
    return 1
}

serving() {
    "$HUD" windows "$ROOT" 2>/dev/null | python3 -c '
import json, sys
data = json.load(sys.stdin)
print("1" if any(w.get("onScreen") and w["height"] >= 60 and w["width"] >= 200 for w in data["windows"]) else "")' 2>/dev/null | grep -q 1
}

bind() {
    pkill -x LampyrisIMKTest 2>/dev/null || true
    sleep 1
    open "$APP" 2>/dev/null || return 1
    sleep 3
    "$HELPER" restore-original "$ROOT" >/dev/null 2>&1 || true
    sleep 0.5
    "$HELPER" select-owned "$ROOT" >/dev/null || return 1
    sleep 1.0
    owned_cleanup >/dev/null 2>&1 || true
    owned_textedit_create || return 1
    refocus || return 1
    owned_do char w || return 1
    sleep 0.4
    serving || return 1
    refocus || return 1
    owned_do key 49 || return 1
    sleep 0.4
    return 0
}

cleanup() {
    status=$?
    rm -f "${ROOT}/perf-trace.enabled" 2>/dev/null || true
    owned_cleanup >/dev/null 2>&1 || true
    "$HELPER" restore-original "$ROOT" >/dev/null 2>&1 || true
    exit "$status"
}
trap cleanup EXIT

bound=""
for attempt in 1 2 3; do
    if bind; then bound="$attempt"; break; fi
    echo "第 ${attempt} 轮宿主未接客，重试" >&2
done
[ -n "$bound" ] || { echo "BLOCKED 宿主未接客：3 轮都没有候选窗" >&2; exit 3; }
echo "接客于第 ${bound} 轮"

i=0
while [ "$i" -lt 14 ]; do
    refocus || exit 3
    owned_do char w
    sleep 0.12
    refocus || exit 3
    owned_do char q
    sleep 0.25
    refocus || exit 3
    owned_do key 49
    sleep 0.35
    i=$((i + 1))
done

refocus || exit 3
osascript -e 'tell application "System Events" to keystroke "," using {option down}'
sleep 1.2
refocus >/dev/null 2>&1 || true
osascript -e 'tell application "System Events" to keystroke "a" using {option down}'
sleep 1.2

[ -s "$TRACE" ] || { echo "BLOCKED 没有 trace 样本" >&2; exit 3; }
chmod 600 "$TRACE"
lines=$(wc -l < "$TRACE" | tr -d ' ')
[ "$lines" -ge 30 ] || { echo "BLOCKED 样本过少：${lines}" >&2; exit 3; }

python3 - "$TRACE" <<'PY'
import json, sys
from pathlib import Path
totals, engines, panels = [], [], []
for line in Path(sys.argv[1]).read_text().splitlines():
    entry = json.loads(line)
    if entry.get('panel'):
        panels.append(entry['totalUs'] / 1000)
    else:
        totals.append(entry['totalUs'] / 1000)
        engines.append(entry['engineUs'] / 1000)

def summary(values):
    if not values:
        return {}
    ordered = sorted(values)
    pick = lambda f: round(ordered[min(len(ordered) - 1, max(0, int(round(f * (len(ordered) - 1)))))], 1)
    return {'n': len(ordered), 'p50': pick(0.5), 'p95': pick(0.95), 'max': round(ordered[-1], 1)}

print('按键→候选/提交 total(ms):', summary(totals))
print('其中引擎 engine(ms):', summary(engines))
print('面板(ms):', summary(panels))
PY
