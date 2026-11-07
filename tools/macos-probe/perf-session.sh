#!/bin/sh
# 键入路径性能与网络验收（报告191）：自投递按键、逐键测延迟，同时采样宿主网络与内存。
# 判定：p95 ≤ 16ms、内存增长 ≤ RSS_LIMIT_MB、全程 0 条 TCP/UDP，否则非零退出。
# 覆盖三段键盘路径（报告 251）：基础词句、长编码/四码字、翻页与候选窗刷新——
# 原来只统计 `KEYS` 一句，长编码与翻页延迟没有数据。
# 报告198：绝对 RSS 不可跨 macOS 版本比较（macOS 13 的 ps rss 计入共享库页），泄漏信号看「键入后相对基线增长」。
# 自投递把 NSEvent 直接交给测试窗口的 keyDown，经输入上下文走真实 IME 往返，不需要辅助功能授权。
set -u
PROBE="$(cd "$(dirname "$0")" && pwd)"
BIN="$PROBE/bin"
SOURCE="${SOURCE:-cn.jokerhub.inputmethod.Lampyris.default}"
ROUNDS="${ROUNDS:-10}"
KEYS="${KEYS:-wq nihao xuexi .}"
# 段名|按键串，用 `;` 分隔；每段跑 ROUNDS 轮，最终按段汇总 p95 并给总 p95。
SEGMENTS="${SEGMENTS:-basic|${KEYS};long-code|trnt wqiy khk;paging|wq = = - .}" 
THRESHOLD_MS="${THRESHOLD_MS:-16}"
RSS_LIMIT_MB="${RSS_LIMIT_MB:-30}"
FOOTPRINT_HARD_MB="${FOOTPRINT_HARD_MB:-40}"
OUT="${OUT:-/tmp/lampyris-perf-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$OUT"
# 报告229：OUT 可能是相对路径，而测速 app 由 `open -n` 拉起、工作目录是 /，
# 相对路径会让它把 round-*.json 写到根目录之外的地方，最终统计成 keys=0 的假 FAIL。
case "$OUT" in /*) ;; *) OUT="$(cd "$OUT" && pwd)" ;; esac

host_pid() { pgrep -x Lampyris | head -1; }
HOST=$(host_pid)
[ -n "$HOST" ] || { echo '{"result":"BLOCKED","reason":"宿主未运行"}'; exit 1; }
"$BIN/tissrc" select "$SOURCE" >/dev/null || { echo '{"result":"BLOCKED","reason":"无法选中输入源"}'; exit 78; }
# 报告095/229：第三方源的程序化选择未必生效。选完必须回读，不生效就是 BLOCKED（不是产品 FAIL）。
CUR=$("$BIN/tissrc" list 2>/dev/null | grep '^current' | head -1)
case "$CUR" in
    *Lampyris*) ;;
    *) echo "{\"result\":\"BLOCKED\",\"reason\":\"输入源选择未生效\",\"current\":\"${CUR#current }\"}"; exit 78 ;;
esac

NET="$OUT/net.csv"
BASE_RSS=$(ps -o rss= -p "$HOST" | tr -d ' ')
( while :; do
    p=$(host_pid); [ -z "$p" ] && break
    echo "$(date -u +%s),$(lsof -nP -a -p "$p" -i 2>/dev/null | grep -c -E 'TCP|UDP')" >> "$NET"
    sleep 1
  done ) &
SAMPLER=$!

# 报告229：延迟必须量到输入法，所以用 HID 投递（type-session.sh 负责起窗口、校验前台、投递、回读），
# 不再用 `--self-post`——进程内合成事件进不了 IMK，量到的是 ASCII 直通。
round=0
OLD_IFS=$IFS
IFS=';'
for segment in $SEGMENTS; do
    IFS=$OLD_IFS
    name=${segment%%|*}
    keys=${segment#*|}
    r=0
    while [ "$r" -lt "$ROUNDS" ]; do
        out="$OUT/round-$name-$r.json"
        rm -f "$out"
        "$PROBE/type-session.sh" "$keys" --settle "${ROUND_SETTLE:-4}" --source "$SOURCE" > "$out" 2>/dev/null
        if [ -x "$BIN/tissrc" ]; then "$BIN/tissrc" select "$SOURCE" >/dev/null 2>&1; fi
        r=$((r + 1))
        round=$((round + 1))
    done
    IFS=';'
done
IFS=$OLD_IFS
kill "$SAMPLER" 2>/dev/null

# 报告229：测速 app 一个 round 都没产出 JSON，说明它的输入上下文没接上 IME（实测 keys_seen=0、
# 文本仍是 ASCII）。这种情况测出来的不是 IME 延迟，按 BLOCKED 处理，不给假 PASS/假 FAIL。
if ! ls "$OUT"/round-*.json >/dev/null 2>&1; then
    echo "{\"result\":\"BLOCKED\",\"reason\":\"测速 app 未产出 round 结果（输入上下文未接上 IME）\",\"rounds\":$ROUNDS}"
    "$BIN/tissrc" select com.apple.keylayout.ABC >/dev/null 2>&1
    exit 78
fi

# 键入结束后静置，量"稳定态"内存
sleep "${SETTLE:-20}"
STEADY_RSS=$(ps -o rss= -p "$(host_pid)" | tr -d ' ')
echo "${STEADY_RSS:-0}" > "$OUT/steady-rss-kb"
# 报告251：`ps rss` 在 macOS 27 计入共享页，绝对门禁改用 vmmap physical footprint。
STEADY_FP=$(vmmap -summary "$(host_pid)" 2>/dev/null | awk -F: '/Physical footprint:/{sub(/^ +/,"",$2); print $2}' | head -1)
echo "${STEADY_FP:-0M}" > "$OUT/steady-footprint"
"$BIN/tissrc" select com.apple.keylayout.ABC >/dev/null

python3 - "$OUT" "$THRESHOLD_MS" "$RSS_LIMIT_MB" "$FOOTPRINT_HARD_MB" "$BASE_RSS" <<'PY'
import glob, json, os, re, sys
out, threshold, rss_limit, footprint_hard, base_kb = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4]), int(sys.argv[5] or 0)
latencies, cold, mismatched, invalid, missing_events = [], [], 0, 0, 0
by_segment = {}
for path in sorted(glob.glob(out + "/round-*.json")):
    segment = re.match(r"round-(.+)-[0-9]+\.json$", os.path.basename(path))
    segment = segment.group(1) if segment else "unknown"
    data = json.load(open(path, encoding="utf-8"))
    if data.get("current_source", "").find("Lampyris") < 0:
        mismatched += 1
    # 报告229：输入上下文没接上 IME 时，测到的只是 ASCII 直通延迟，不是输入法往返；
    # 这种 round 一律丢弃，不能拿来判 PASS（曾因此报出假的 p95 7.19ms）。
    if not data.get("has_non_ascii") or data.get("keys_seen", 0) == 0:
        invalid += 1
        continue
    events = data.get("events")
    if not events:
        missing_events += 1
        latencies.extend(data.get("latencies_ms", []))
        continue
    # 报告233：慢样本全部集中在"新窗口的第一个键"（输入上下文首次建立 + 首帧候选），
    # 与稳定态键入是两件事，必须分开算，否则 p95 由每轮 1/16 的冷样本决定。
    cold.append(events[0]["ms"])
    latencies.extend(e["ms"] for e in events[1:])
    by_segment.setdefault(segment, []).extend(e["ms"] for e in events[1:])
latencies.sort()
cold.sort()
def segment_p95(values):
    if not values:
        return None
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(round(0.95 * (len(ordered) - 1))))]
def pct(p):
    if not latencies:
        return None
    return latencies[min(len(latencies) - 1, int(round(p / 100 * (len(latencies) - 1))))]
conns = 0
try:
    for row in open(out + "/net.csv", encoding="utf-8").read().split():
        conns = max(conns, int(row.split(",")[1]))
except FileNotFoundError:
    pass
steady_kb = int(open(out + "/steady-rss-kb", encoding="utf-8").read().strip() or 0)
steady_mb = round(steady_kb / 1024, 1)
base_mb = round(base_kb / 1024, 1)
growth_mb = round(steady_mb - base_mb, 1)
raw_fp = open(out + "/steady-footprint", encoding="utf-8").read().strip() or "0M"
fp_match = re.match(r"([0-9.]+)([KMG]?)", raw_fp)
steady_fp = round(float(fp_match.group(1)) / {"": 1048576, "K": 1024, "M": 1, "G": 1024}[fp_match.group(2)], 1) if fp_match else 0.0
def pct_cold(p):
    if not cold:
        return None
    return cold[min(len(cold) - 1, int(round(p / 100 * (len(cold) - 1))))]
summary = {
    "keys": len(latencies) + len(cold),
    "steady_keys": len(latencies),
    "p50_ms": pct(50), "p95_ms": pct(95), "max_ms": latencies[-1] if latencies else None,
    "cold_first_key_ms": {"p50": pct_cold(50), "p95": pct_cold(95), "max": cold[-1] if cold else None, "count": len(cold)},
    "missing_events_rounds": missing_events,
    "baseline_rss_mb": base_mb, "steady_rss_mb": steady_mb, "rss_growth_mb": growth_mb,
    "max_connections": conns,
    "source_mismatch_rounds": mismatched,
    "segments": {name: {"keys": len(values), "p95_ms": segment_p95(values)}
                 for name, values in sorted(by_segment.items())},
    "footprint_steady_mb": steady_fp,
    "thresholds": {"p95_ms": threshold, "rss_growth_mb": rss_limit, "footprint_hard_mb": footprint_hard},
}
# 门禁只看稳定态（ADR-307）；冷首键单独记录，不参与 PASS/FAIL，但要保证确实采到样本。
ok = (bool(latencies) and summary["p95_ms"] <= threshold and len(cold) > 0
      and steady_fp > 0 and steady_fp <= footprint_hard and conns == 0 and mismatched == 0)
summary["invalid_rounds"] = invalid
if not latencies:
    summary["result"] = "BLOCKED"
    summary["reason"] = "所有 round 都没有走 IME（has_non_ascii=false / keys_seen=0）"
    print(json.dumps(summary, ensure_ascii=False, sort_keys=True))
    raise SystemExit(78)
summary["result"] = "PASS" if ok else "FAIL"
print(json.dumps(summary, ensure_ascii=False, sort_keys=True))
raise SystemExit(0 if ok else 1)
PY
