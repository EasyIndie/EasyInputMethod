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
# 报告229：`tissrc` 查询/选源会把宿主拉起来，刚启动的 RSS 会虚高（README「重启后立刻读数会偏高」），
# 先热身再取基线，否则 rss_hard 会被启动瞬时值误判成 FAIL。
sleep "${WARMUP:-10}"
L0=$(dict_lines)

NET="$OUT/net.csv"; RSS="$OUT/rss.csv"; FP="$OUT/footprint.csv"
: > "$NET"; : > "$RSS"; : > "$FP"
# 报告200：RSS 跨 macOS 版本不可比，这里额外每 10 秒记一次 physical footprint（趋势用，门禁仍是 memory-gate.sh）。
( tick=0; while [ "$tick" -lt $((MINUTES * 60)) ]; do
    p=$(host_pid); [ -z "$p" ] && break
    echo "$(lsof -nP -a -p "$p" -i 2>/dev/null | grep -c -E 'TCP|UDP')" >> "$NET"
    echo "$(ps -o rss= -p "$p" | tr -d ' ')" >> "$RSS"
    if [ $((tick % 10)) -eq 0 ]; then
        vmmap -summary "$p" 2>/dev/null | awk -F: '/Physical footprint:/{sub(/^ +/,"",$2); print $2}' >> "$FP"
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
IME_ROUNDS=$(grep -l '"has_non_ascii": true' "$OUT"/round-*.json 2>/dev/null | wc -l | tr -d ' ')
L1=$(dict_lines)

restart_host || { echo '{"result":"FAIL","reason":"宿主重启失败"}'; exit 1; }
sleep 5
L2=$(dict_lines)
"$BIN/tissrc" select com.apple.keylayout.ABC >/dev/null 2>&1

python3 - "$OUT" "$L0" "$L1" "$L2" "$GROWTH_LIMIT_MB" "$RSS_HARD_MB" "$ROUND" "${IME_ROUNDS:-0}" "$TRUNCATED" <<'PY'
import json, re, sys
out, l0, l1, l2 = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
growth_limit, rss_hard, rounds = float(sys.argv[5]), float(sys.argv[6]), int(sys.argv[7])
ime_rounds = int(sys.argv[8])
truncated = int(sys.argv[9])
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
            values.append({"": number / 1048576, "K": number / 1024, "M": number, "G": number * 1024}[match.group(2)])
    return values
footprint = mb("footprint.csv")
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
    "thresholds": {"growth_mb": growth_limit, "rss_hard_mb": rss_hard},
}
# 报告229：一个走 IME 的 round 都没有，说明久用测的不是输入法，直接判 FAIL。
ok = (rounds > 0 and ime_rounds > 0 and truncated == 0 and summary["max_connections"] == 0
      and growth <= growth_limit and tail_avg <= rss_hard
      and l2 == l1 and l1 >= l0)
summary["result"] = "PASS" if ok else "FAIL"
print(json.dumps(summary, ensure_ascii=False, sort_keys=True))
raise SystemExit(0 if ok else 1)
PY
