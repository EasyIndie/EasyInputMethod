#!/bin/sh
# 久用与持久化验收（报告192）：连续键入若干分钟，采样网络/内存，然后重启宿主验证词库不丢。
# 判定：全程 0 连接、RSS 增长 ≤ GROWTH_LIMIT_MB、稳定态 ≤ RSS_HARD_MB、词库行数重启前后一致、宿主存活。
# 报告198：绝对 RSS 不可跨 macOS 版本比较（macOS 13 的 ps rss 计入共享库页），泄漏信号看「相对热身段增长」。
set -u
PROBE="$(cd "$(dirname "$0")" && pwd)"
BIN="$PROBE/bin"
SUPPORT="${SUPPORT:-$HOME/Library/Application Support/Lampyris}"
DICT="$SUPPORT/user-dictionary.tsv"
SOURCE="${SOURCE:-cn.jokerhub.inputmethod.Lampyris.default}"
MINUTES="${MINUTES:-3}"
GROWTH_LIMIT_MB="${GROWTH_LIMIT_MB:-5}"
RSS_HARD_MB="${RSS_HARD_MB:-96}"
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
"$BIN/tissrc" select "$SOURCE" >/dev/null || { echo '{"result":"BLOCKED","reason":"无法选中输入源"}'; exit 1; }
L0=$(dict_lines)

NET="$OUT/net.csv"; RSS="$OUT/rss.csv"
: > "$NET"; : > "$RSS"
( for _ in $(seq 1 $((MINUTES * 60))); do
    p=$(host_pid); [ -z "$p" ] && break
    echo "$(lsof -nP -a -p "$p" -i 2>/dev/null | grep -c -E 'TCP|UDP')" >> "$NET"
    echo "$(ps -o rss= -p "$p" | tr -d ' ')" >> "$RSS"
    sleep 1
  done ) &
SAMPLER=$!

END=$(( $(date +%s) + MINUTES * 60 ))
ROUND=0
CHUNKS="wq nihao xuexi .;nihao shijie .;wq xuexi nihao .;zhongguo .;renmin .;shijian ."
COUNT=$(printf '%s' "$CHUNKS" | tr ';' '\n' | wc -l | tr -d ' ')
while [ "$(date +%s)" -lt "$END" ]; do
    idx=$((ROUND % COUNT + 1))
    chunk=$(printf '%s' "$CHUNKS" | tr ';' '\n' | sed -n "${idx}p")
    out="$OUT/round-$ROUND.json"; rm -f "$out"
    open -n /tmp/lampyris-imetype.app --args --source "$SOURCE" --keys "$chunk" \
        --settle 2 --delay 1.0 --self-post --out "$out" >/dev/null 2>&1
    i=0; while [ $i -lt 30 ]; do [ -s "$out" ] && break; i=$((i + 1)); sleep 0.5; done
    ROUND=$((ROUND + 1))
done
kill "$SAMPLER" 2>/dev/null
L1=$(dict_lines)

restart_host || { echo '{"result":"FAIL","reason":"宿主重启失败"}'; exit 1; }
sleep 5
L2=$(dict_lines)
"$BIN/tissrc" select com.apple.keylayout.ABC >/dev/null 2>&1

python3 - "$OUT" "$L0" "$L1" "$L2" "$GROWTH_LIMIT_MB" "$RSS_HARD_MB" "$ROUND" <<'PY'
import json, sys
out, l0, l1, l2 = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
growth_limit, rss_hard, rounds = float(sys.argv[5]), float(sys.argv[6]), int(sys.argv[7])
def numbers(name):
    try:
        return [int(x) for x in open(f"{out}/{name}", encoding="utf-8").read().split()]
    except FileNotFoundError:
        return []
conns, rss = numbers("net.csv"), numbers("rss.csv")
first = rss[0] / 1024 if rss else 0
peak = max(rss) / 1024 if rss else 0
# 只用后半段与热身段比较，避免把首次候选窗/字体加载算作增长
warm = rss[len(rss) // 4] / 1024 if len(rss) > 8 else first
tail = rss[-max(1, len(rss) // 4):]
tail_avg = sum(tail) / len(tail) / 1024 if tail else peak
growth = tail_avg - warm
summary = {
    "rounds": rounds, "dict_before": l0, "dict_after_typing": l1, "dict_after_restart": l2,
    "learned_delta": l1 - l0,
    "samples": len(rss), "rss_first_mb": round(first, 1), "rss_peak_mb": round(peak, 1),
    "rss_steady_mb": round(tail_avg, 1),
    "rss_growth_mb": round(growth, 1), "rss_tail_avg_mb": round(tail_avg, 1),
    "max_connections": max(conns) if conns else 0,
    "thresholds": {"growth_mb": growth_limit, "rss_hard_mb": rss_hard},
}
ok = (rounds > 0 and summary["max_connections"] == 0
      and growth <= growth_limit and tail_avg <= rss_hard
      and l2 == l1 and l1 >= l0)
summary["result"] = "PASS" if ok else "FAIL"
print(json.dumps(summary, ensure_ascii=False, sort_keys=True))
raise SystemExit(0 if ok else 1)
PY
