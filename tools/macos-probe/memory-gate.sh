#!/bin/sh
# ADR-263「常驻内存 ≤30MB」口径复测：新启动宿主 → marker 先行 → 四个固定时点采样 → 至少 3 个独立轮次。
# 判定：vmmap physical footprint 与「私有已提交」（Writable regions resident + swapped_out）在稳态时点同时 ≤ LIMIT_MB。
# 注意：这不是探针 RSS 口径（报告198），RSS 会随 macOS 版本把共享库/映射页算进来。
# 用法：memory-gate.sh [ROUNDS=3]；输出 JSON 摘要 + 每轮 vmmap 全文到 OUT。
set -u
PROBE="$(cd "$(dirname "$0")" && pwd)"
BIN="$PROBE/bin"
SOURCE="${SOURCE:-cn.jokerhub.inputmethod.Lampyris.default}"
ROUNDS="${ROUNDS:-3}"
LIMIT_MB="${LIMIT_MB:-30}"
OUT="${OUT:-/tmp/lampyris-memory-gate-$(date -u +%Y%m%dT%H%M%SZ)}"
SUPPORT="${SUPPORT:-$HOME/Library/Application Support/Lampyris}"
APP="$HOME/Library/Input Methods/Lampyris.app"
mkdir -p "$OUT"

host_pid() { pgrep -x Lampyris | head -1; }
sample() { # label
    p=$(host_pid)
    [ -n "$p" ] || { echo '{"result":"BLOCKED","reason":"宿主未运行"}'; exit 1; }
    vmmap -summary "$p" 2>/dev/null > "$OUT/round-$ROUND-$1.txt"
}
restart_host() {
    p=$(host_pid); [ -n "$p" ] && kill -TERM "$p" 2>/dev/null
    for _ in $(seq 1 15); do [ -z "$(host_pid)" ] && break; sleep 1; done
    [ -z "$(host_pid)" ] || { echo '{"result":"FAIL","reason":"旧宿主未退出"}'; exit 1; }
    open "$APP" 2>/dev/null
    for _ in $(seq 1 20); do [ -n "$(host_pid)" ] && return 0; sleep 1; done
    echo '{"result":"FAIL","reason":"新宿主未起来"}'; exit 1
}
type_keys() { "$PROBE/type-session.sh" "$1" --settle 2 >/dev/null 2>&1; }

ROUND=1
while [ "$ROUND" -le "$ROUNDS" ]; do
    restart_host
    sleep 2
    "$BIN/tissrc" select "$SOURCE" >/dev/null 2>&1 || { echo '{"result":"BLOCKED","reason":"无法选中输入源"}'; exit 1; }
    sample cold
    type_keys 'wq '                     # marker 先行：证明输入上下文已接上
    sample first-key
    type_keys 'wq nihao xuexi shijie zhongguo renmin .'
    sample six-words
    sleep 8
    sample idle-8s
    { date -u +%FT%TZ; uptime; vm_stat | head -1; sysctl -n vm.swapusage; } > "$OUT/round-$ROUND-env.txt"
    ROUND=$((ROUND + 1))
done
"$BIN/tissrc" select com.apple.keylayout.ABC >/dev/null 2>&1

python3 - "$OUT" "$ROUNDS" "$LIMIT_MB" "$(shasum -a 256 "$APP/Contents/MacOS/Lampyris" | awk '{print $1}')" \
    "$(shasum -a 256 "$SUPPORT/config.toml" 2>/dev/null | awk '{print $1}')" <<'PY'
import glob, json, re, sys

out, rounds, limit, exec_sha, config_sha = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), sys.argv[4], sys.argv[5]
POINTS = ["cold", "first-key", "six-words", "idle-8s"]

def to_mb(value):
    match = re.match(r"([0-9.]+)([KMG]?)", value)
    if not match:
        return None
    number = float(match.group(1))
    return {"": number / 1048576, "K": number / 1024, "M": number, "G": number * 1024}[match.group(2)]

def parse(path):
    text = open(path, encoding="utf-8", errors="replace").read()
    footprint = re.search(r"Physical footprint:\s+([0-9.]+[KMG])", text)
    peak = re.search(r"Physical footprint \(peak\):\s+([0-9.]+[KMG])", text)
    writable = re.search(r"^Writable regions:.*resident=([0-9.]+[KMG]).*swapped_out=([0-9.]+[KMG])", text, re.M)
    if not footprint or not writable:
        return None
    resident, swapped = to_mb(writable.group(1)), to_mb(writable.group(2))
    return {
        "physical_footprint_mb": round(to_mb(footprint.group(1)), 1),
        "physical_footprint_peak_mb": round(to_mb(peak.group(1)), 1) if peak else None,
        "private_committed_mb": round(resident + swapped, 1),
    }

results, missing, failed = {}, [], False
for index in range(1, rounds + 1):
    row = {}
    for point in POINTS:
        path = f"{out}/round-{index}-{point}.txt"
        sample = parse(path) if glob.glob(path) else None
        if sample is None:
            missing.append(f"round-{index}-{point}")
        row[point] = sample
    env = open(f"{out}/round-{index}-env.txt", encoding="utf-8", errors="replace").read().split("\n") if glob.glob(f"{out}/round-{index}-env.txt") else []
    row["env"] = {
        "uptime": env[1].strip() if len(env) > 1 else None,
        "swap": env[3].strip() if len(env) > 3 else None,
    }
    results[f"round-{index}"] = row

steady = [point for point in POINTS if point in ("six-words", "idle-8s")]
for row in results.values():
    for point in steady:
        sample = row.get(point)
        if not sample or sample["physical_footprint_mb"] > limit or sample["private_committed_mb"] > limit:
            failed = True
summary = {
    "rounds": rounds,
    "limit_mb": limit,
    "steady_points": steady,
    "exec_sha": exec_sha,
    "config_sha": config_sha,
    "missing_samples": missing,
    "results": results,
    "result": "FAIL" if failed or missing else "PASS",
}
print(json.dumps(summary, ensure_ascii=False, sort_keys=True, indent=2))
raise SystemExit(0 if summary["result"] == "PASS" else 1)
PY
