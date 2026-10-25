#!/bin/sh
# 键入路径性能与网络验收（报告191）：自投递按键、逐键测延迟，同时采样宿主网络与内存。
# 判定：p95 ≤ 16ms、RSS 增长 ≤ RSS_LIMIT_MB、稳定态 ≤ RSS_HARD_MB、全程 0 条 TCP/UDP，否则非零退出。
# 报告198：绝对 RSS 不可跨 macOS 版本比较（macOS 13 的 ps rss 计入共享库页），泄漏信号看「键入后相对基线增长」。
# 自投递把 NSEvent 直接交给测试窗口的 keyDown，经输入上下文走真实 IME 往返，不需要辅助功能授权。
set -u
PROBE="$(cd "$(dirname "$0")" && pwd)"
BIN="$PROBE/bin"
SOURCE="${SOURCE:-cn.jokerhub.inputmethod.Lampyris.default}"
ROUNDS="${ROUNDS:-10}"
KEYS="${KEYS:-wq nihao xuexi .}"
THRESHOLD_MS="${THRESHOLD_MS:-16}"
RSS_LIMIT_MB="${RSS_LIMIT_MB:-30}"
RSS_HARD_MB="${RSS_HARD_MB:-96}"
OUT="${OUT:-/tmp/lampyris-perf-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$OUT"

host_pid() { pgrep -x Lampyris | head -1; }
HOST=$(host_pid)
[ -n "$HOST" ] || { echo '{"result":"BLOCKED","reason":"宿主未运行"}'; exit 1; }
"$BIN/tissrc" select "$SOURCE" >/dev/null || { echo '{"result":"BLOCKED","reason":"无法选中输入源"}'; exit 1; }

NET="$OUT/net.csv"
BASE_RSS=$(ps -o rss= -p "$HOST" | tr -d ' ')
( while :; do
    p=$(host_pid); [ -z "$p" ] && break
    echo "$(date -u +%s),$(lsof -nP -a -p "$p" -i 2>/dev/null | grep -c -E 'TCP|UDP')" >> "$NET"
    sleep 1
  done ) &
SAMPLER=$!

round=0
while [ "$round" -lt "$ROUNDS" ]; do
    out="$OUT/round-$round.json"
    rm -f "$out"
    open -n /tmp/lampyris-imetype.app --args --source "$SOURCE" --keys "$KEYS" \
        --settle 2 --delay 1.0 --self-post --out "$out" >/dev/null 2>&1
    i=0
    while [ $i -lt 30 ]; do [ -s "$out" ] && break; i=$((i + 1)); sleep 0.5; done
    round=$((round + 1))
done
kill "$SAMPLER" 2>/dev/null

# 键入结束后静置，量"稳定态"内存
sleep "${SETTLE:-20}"
STEADY_RSS=$(ps -o rss= -p "$(host_pid)" | tr -d ' ')
echo "${STEADY_RSS:-0}" > "$OUT/steady-rss-kb"
"$BIN/tissrc" select com.apple.keylayout.ABC >/dev/null

python3 - "$OUT" "$THRESHOLD_MS" "$RSS_LIMIT_MB" "$RSS_HARD_MB" "$BASE_RSS" <<'PY'
import glob, json, sys
out, threshold, rss_limit, rss_hard, base_kb = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4]), int(sys.argv[5] or 0)
latencies, mismatched = [], 0
for path in sorted(glob.glob(out + "/round-*.json")):
    data = json.load(open(path, encoding="utf-8"))
    latencies.extend(data.get("latencies_ms", []))
    if data.get("current_source", "").find("Lampyris") < 0:
        mismatched += 1
latencies.sort()
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
summary = {
    "keys": len(latencies),
    "p50_ms": pct(50), "p95_ms": pct(95), "max_ms": latencies[-1] if latencies else None,
    "baseline_rss_mb": base_mb, "steady_rss_mb": steady_mb, "rss_growth_mb": growth_mb,
    "max_connections": conns,
    "source_mismatch_rounds": mismatched,
    "thresholds": {"p95_ms": threshold, "rss_growth_mb": rss_limit, "rss_hard_mb": rss_hard},
}
ok = (bool(latencies) and summary["p95_ms"] <= threshold
      and growth_mb <= rss_limit and steady_mb <= rss_hard and conns == 0 and mismatched == 0)
summary["result"] = "PASS" if ok else "FAIL"
print(json.dumps(summary, ensure_ascii=False, sort_keys=True))
raise SystemExit(0 if ok else 1)
PY
