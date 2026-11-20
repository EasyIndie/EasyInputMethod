#!/bin/sh
# 久用与持久化验收（报告192）：连续键入若干分钟，采样网络/内存，然后重启宿主验证词库不丢。
# 判定：全程 0 连接、**footprint** 增长 ≤ GROWTH_LIMIT_MB、稳定态 footprint ≤ FOOTPRINT_HARD_MB、
# 词库行数重启前后一致、宿主存活。
# 报告198/229：`ps rss` 在 macOS 27 计入共享页（同宿主 footprint 33 MiB / rss 95 MiB），
# 不能当硬顶（ADR 报告 251 起改用 vmmap physical footprint）；rss 仍采样，只作参考。
set -u
PROBE="$(cd "$(dirname "$0")" && pwd)"
BIN="$PROBE/bin"
SUPPORT="${SUPPORT:-$HOME/Library/Application Support/Lampyris}"
DICT="$SUPPORT/user-dictionary.tsv"
SOURCE="${SOURCE:-cn.jokerhub.inputmethod.Lampyris.default}"
MINUTES="${MINUTES:-3}"
GROWTH_LIMIT_MB="${GROWTH_LIMIT_MB:-5}"
# 报告331 / ADR-385：与 perf-session 用同一个硬门（44 MiB，不抬高），且只在冷启动窗口内判定。
FOOTPRINT_HARD_MB="${FOOTPRINT_HARD_MB:-44}"
OUT="${OUT:-/tmp/lampyris-soak-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$OUT"

host_pid() { pgrep -x Lampyris | head -1; }
dict_lines() { [ -f "$DICT" ] && wc -l < "$DICT" | tr -d ' ' || echo 0; }
restart_host() {
    p=$(host_pid); [ -n "$p" ] && kill -TERM "$p" 2>/dev/null
    for _ in $(seq 1 10); do [ -z "$(host_pid)" ] && break; sleep 1; done
    open "$HOME/Library/Input Methods/Lampyris.app" 2>/dev/null
    for _ in $(seq 1 15); do [ -n "$(host_pid)" ] && return 0; sleep 1; done
    return 1
}

HOST=$(host_pid)
[ -n "$HOST" ] || { echo '{"result":"BLOCKED","reason":"宿主未运行"}'; exit 1; }
# 报告331 / ADR-385：footprint 只在冷启动窗口（900 s）内可比。跑之前先把宿主重启成冷态，
# 否则前一次探针留下的 AppKit 缓存会让 `footprint_first` 直接超过硬门。窗口外的采样只作参考。
restart_host || { echo '{"result":"BLOCKED","reason":"宿主冷启动失败"}'; exit 1; }
HOST=$(host_pid)
"$BIN/tissrc" select "$SOURCE" >/dev/null || { echo '{"result":"BLOCKED","reason":"无法选中输入源"}'; exit 1; }
# 报告229：`tissrc` 查询/选源会把宿主拉起来，刚启动的 RSS 会虚高（README「重启后立刻读数会偏高」），
# 先热身再取基线，否则 rss_hard 会被启动瞬时值误判成 FAIL。
sleep "${WARMUP:-10}"
L0=$(dict_lines)

NET="$OUT/net.csv"; RSS="$OUT/rss.csv"; FP="$OUT/footprint.csv"
: > "$NET"; : > "$RSS"; : > "$FP"
# 报告200：RSS 跨 macOS 版本不可比，这里额外每 5 秒记一次 physical footprint（趋势用，门禁仍是 memory-gate.sh）。
# 报告331 / ADR-389：**不用 `vmmap -summary`**。它会 task_suspend 目标再走地址空间，实测把宿主按键延迟
# 从 15–30 ms 抬到 300–600 ms（10/10 轮），久用探针会把自己量成"卡顿"。`bin/footprint` 只读
# `proc_pid_rusage`（不挂起），15 ms 完成。
( tick=0; while [ "$tick" -lt $((MINUTES * 60)) ]; do
    p=$(host_pid); [ -z "$p" ] && break
    echo "$(lsof -nP -a -p "$p" -i 2>/dev/null | grep -c -E 'TCP|UDP')" >> "$NET"
    echo "$(ps -o rss= -p "$p" | tr -d ' ')" >> "$RSS"
    if [ $((tick % 5)) -eq 0 ]; then
        "$BIN/footprint" "$p" 2>/dev/null >> "$FP"
    fi
    tick=$((tick + 1))
    sleep 1
  done ) &
SAMPLER=$!

END=$(( $(date +%s) + MINUTES * 60 ))
ROUND=0
TRUNCATED=0
CHUNKS="wq nihao xuexi .;nihao shijie .;wq xuexi nihao .;zhongguo .;renmin .;shijian ."
# 报告229：原来用 `printf '%s' | tr ';' '\n' | wc -l` 数行数，末段没有换行 → 少算一条，
# 最后一条 chunk（shijian）从来没跑过。改成按分隔符数段。
COUNT=$(printf '%s' "$CHUNKS" | awk -F';' '{print NF}')
while [ "$(date +%s)" -lt "$END" ]; do
    idx=$((ROUND % COUNT + 1))
    chunk=$(printf '%s' "$CHUNKS" | tr ';' '\n' | sed -n "${idx}p")
    out="$OUT/round-$ROUND.json"; rm -f "$out"
    # 报告229：久用必须真的走输入法（`--self-post` 的进程内合成事件进不了 IMK），
    # 所以复用 type-session.sh 的 HID 投递：起窗口→校验前台→投键→回读。
    KEY_HOLD="${KEY_HOLD:-120}" KEY_INTERVAL="${KEY_INTERVAL:-250}" \
        "$PROBE/type-session.sh" "$chunk" --settle "${ROUND_SETTLE:-3}" --source "$SOURCE" > "$out" 2>/dev/null
    [ -x "$BIN/tissrc" ] && "$BIN/tissrc" select "$SOURCE" >/dev/null 2>&1
    # 报告199/229：节奏加快后要防"读出口早于最后一个键"，keys_seen 必须等于该 chunk 的字符数。
    got=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("keys_seen") or 0)' "$out" 2>/dev/null)
    [ "${got:-0}" = "${#chunk}" ] || TRUNCATED=$((TRUNCATED + 1))
    ROUND=$((ROUND + 1))
done
kill "$SAMPLER" 2>/dev/null
# 窗口内的 footprint 采样数（1 行 = 5 s）：ADR-385 规定只有冷启动窗口内的读数可作门禁。
FP_IN_WINDOW=$(wc -l < "$FP" 2>/dev/null | tr -d ' ')
[ -n "$FP_IN_WINDOW" ] || FP_IN_WINDOW=0
IME_ROUNDS=$(grep -l '"has_non_ascii": true' "$OUT"/round-*.json 2>/dev/null | wc -l | tr -d ' ')
L1=$(dict_lines)
# 报告331：采样不再挂起宿主，久用里可以真的量按键延迟——按轮取 p95，门禁用中位数（P2-3 的 40 ms 线）。
LAT=$(python3 - "$OUT" <<'EOLAT'
import glob, json, statistics, sys
out = sys.argv[1]
p95s, slow = [], 0
for path in glob.glob(f"{out}/round-*.json"):
    try:
        data = json.load(open(path, encoding="utf-8"))
    except (OSError, ValueError):
        continue
    values = data.get("latencies_ms") or []
    if not values:
        continue
    p95s.append(data.get("latency_ms", {}).get("p95", max(values)))
    if p95s[-1] > 100:
        slow += 1
median = statistics.median(p95s) if p95s else 0
print(f"{median:.2f} {slow} {len(p95s)}")
EOLAT
)
LAT_MEDIAN=$(printf '%s' "$LAT" | awk '{print $1}')
LAT_SLOW=$(printf '%s' "$LAT" | awk '{print $2}')
LAT_ROUNDS=$(printf '%s' "$LAT" | awk '{print $3}')
[ -n "$LAT_MEDIAN" ] || LAT_MEDIAN=0
[ -n "$LAT_SLOW" ] || LAT_SLOW=0
[ -n "$LAT_ROUNDS" ] || LAT_ROUNDS=0

restart_host || { echo '{"result":"FAIL","reason":"宿主重启失败"}'; exit 1; }
sleep 5
L2=$(dict_lines)
"$BIN/tissrc" select com.apple.keylayout.ABC >/dev/null 2>&1

python3 - "$OUT" "$L0" "$L1" "$L2" "$GROWTH_LIMIT_MB" "$FOOTPRINT_HARD_MB" "$ROUND" "${IME_ROUNDS:-0}" "$TRUNCATED" "$LAT_MEDIAN" "$LAT_SLOW" "$LAT_ROUNDS" <<'PY'
import json, re, sys
out, l0, l1, l2 = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
growth_limit, footprint_hard, rounds = float(sys.argv[5]), float(sys.argv[6]), int(sys.argv[7])
ime_rounds = int(sys.argv[8])
truncated = int(sys.argv[9])
latency_median = float(sys.argv[10])
slow_rounds = int(sys.argv[11])
latency_rounds = int(sys.argv[12])
LATENCY_LIMIT_MS = 40.0
def numbers(name):
    try:
        return [int(x) for x in open(f"{out}/{name}", encoding="utf-8").read().split()]
    except FileNotFoundError:
        return []
conns, rss = numbers("net.csv"), numbers("rss.csv")
def mb(name):
    try:
        rows = open(f"{out}/{name}", encoding="utf-8").read().split()
    except FileNotFoundError:
        return []
    values = []
    for row in rows:
        match = re.match(r"([0-9.]+)([KMG]?)", row)
        if match:
            number = float(match.group(1))
            # 报告331：`bin/footprint` 直接给 MiB（`proc_pid_rusage`），无后缀；带后缀的旧 vmmap 文本仍兼容。
            values.append({"": number, "K": number / 1024, "M": number, "G": number * 1024}[match.group(2)])
    return values
footprint = mb("footprint.csv")
# 冷启动窗口 900 s，采样间隔 5 s；门禁只用窗口内的样本（ADR-385）。
fp_window = min(len(footprint), 900 // 5)
fp_warm = footprint[len(footprint) // 4] if len(footprint) > 8 else (footprint[0] if footprint else 0)
fp_tail = footprint[-max(1, len(footprint) // 4):]
fp_tail_avg = sum(fp_tail) / len(fp_tail) if fp_tail else 0
fp_growth = fp_tail_avg - fp_warm
first = rss[0] / 1024 if rss else 0
peak = max(rss) / 1024 if rss else 0
# 只用后半段与热身段比较，避免把首次候选窗/字体加载算作增长
warm = rss[len(rss) // 4] / 1024 if len(rss) > 8 else first
tail = rss[-max(1, len(rss) // 4):]
tail_avg = sum(tail) / len(tail) / 1024 if tail else peak
growth = tail_avg - warm
summary = {
    "rounds": rounds, "ime_rounds": ime_rounds, "truncated_rounds": truncated, "dict_before": l0, "dict_after_typing": l1, "dict_after_restart": l2,
    "learned_delta": l1 - l0,
    "samples": len(rss), "rss_first_mb": round(first, 1), "rss_peak_mb": round(peak, 1),
    "rss_steady_mb": round(tail_avg, 1),
    "rss_growth_mb": round(growth, 1), "rss_tail_avg_mb": round(tail_avg, 1),
    "max_connections": max(conns) if conns else 0,
    "footprint_samples": len(footprint),
    "footprint_first_mb": round(footprint[0], 1) if footprint else None,
    "footprint_peak_mb": round(max(footprint), 1) if footprint else None,
    "footprint_last_mb": round(footprint[-1], 1) if footprint else None,
    "footprint_tail_delta_mb": round(footprint[-1] - footprint[len(footprint) // 2], 1) if len(footprint) > 2 else None,
    "footprint_steady_mb": round(fp_tail_avg, 1),
    "footprint_growth_mb": round(fp_growth, 1),
    "latency_p95_median_ms": latency_median, "latency_slow_rounds": slow_rounds,
    "latency_rounds": latency_rounds, "footprint_window_samples": fp_window,
    "thresholds": {"growth_mb": growth_limit, "footprint_hard_mb": footprint_hard,
                   "latency_p95_median_ms": LATENCY_LIMIT_MS},
}
# 报告229：一个走 IME 的 round 都没有，说明久用测的不是输入法，直接判 FAIL。
# 报告331：延迟也要进门禁——采样不再挂起宿主后，久用里有 300 ms 以上的键就是真问题。
# ADR-385：footprint 只在冷启动窗口内可比；窗口外的读数照样打印，但不参与判定。
footprint_gated = "window" if fp_window > 0 else "informational"
ok = (rounds > 0 and ime_rounds > 0 and truncated == 0 and summary["max_connections"] == 0
      and l2 == l1 and l1 >= l0 and fp_tail_avg > 0 and fp_growth <= growth_limit
      and latency_rounds > 0 and latency_median <= LATENCY_LIMIT_MS
      and (fp_window == 0 or fp_tail_avg <= footprint_hard))
summary["footprint_gate"] = footprint_gated
summary["result"] = "PASS" if ok else "FAIL"
print(json.dumps(summary, ensure_ascii=False, sort_keys=True))
raise SystemExit(0 if ok else 1)
PY
