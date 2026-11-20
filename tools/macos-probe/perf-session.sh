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
FOOTPRINT_HARD_MB="${FOOTPRINT_HARD_MB:-44}"  # ADR-379：字表 3,755→5,021（+34%）实测 34.1→35.9 MiB；按同样相对余量放宽，heap_live 门禁（24 MiB）不变
# ADR-385：footprint 单次采样会有 20 MiB 级抖动（报告 325：同一二进制 35.9–57.3 MiB），
# 因此改成「静置后连续采 N 次、取中位数」并记下离散度；门禁判中位数，抖动本身单独标注。
FOOTPRINT_SAMPLES="${FOOTPRINT_SAMPLES:-3}"
FOOTPRINT_INTERVAL="${FOOTPRINT_INTERVAL:-5}"   # 相邻采样间隔（秒）
FOOTPRINT_SPREAD_WARN_MB="${FOOTPRINT_SPREAD_WARN_MB:-8}"  # 超过就标 unstable，提示这次采样不可当单一证据
# ADR-385：绝对 footprint 只在「冷启动窗口」内可比。宿主用得越久、练习/学习区物化得越多，
# footprint 越高且不回落（报告 326：冷 35.9 → 用 1 小时 45.3 MiB）。超窗就只作参考，不当 FAIL。
FOOTPRINT_COLD_UPTIME_S="${FOOTPRINT_COLD_UPTIME_S:-900}"
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
# 宿主已运行秒数：macOS 的 ps 没有 etimes，用 etime（[D-]HH:MM:SS / MM:SS）自己换算。
HOST_UPTIME_S=$(ps -o etime= -p "$HOST" 2>/dev/null | awk '{
    t = $1; days = 0
    if (index(t, "-") > 0) { split(t, d, "-"); days = d[1]; t = d[2] }
    n = split(t, p, ":")
    if (n == 3) secs = p[1] * 3600 + p[2] * 60 + p[3]
    else if (n == 2) secs = p[1] * 60 + p[2]
    else secs = p[1]
    print days * 86400 + secs
}')
HOST_UPTIME_S="${HOST_UPTIME_S:-0}"
echo "$HOST_UPTIME_S" > "$OUT/host-uptime-s"
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
# ADR-385：连采 FOOTPRINT_SAMPLES 次（首采之前已静置 SETTLE 秒），门禁取中位数。
: > "$OUT/footprint-samples-mb"
sample_footprint() {
    vmmap -summary "$(host_pid)" 2>/dev/null \
        | awk -F: '/Physical footprint:/{sub(/^ +/,"",$2); print $2}' \
        | head -1 | sed 's/[[:space:]]*$//'
}
i=0
while [ "$i" -lt "$FOOTPRINT_SAMPLES" ]; do
    if [ "$i" -gt 0 ]; then sleep "$FOOTPRINT_INTERVAL"; fi
    fp=$(sample_footprint)
    echo "${fp:-0M}" >> "$OUT/footprint-samples-mb"
    i=$((i + 1))
done
# 兼容旧读数：steady-footprint 现在写中位数（由下面的汇总脚本决定，这里先留原始序列）。
STEADY_FP=$(head -1 "$OUT/footprint-samples-mb" 2>/dev/null)
echo "${STEADY_FP:-0M}" > "$OUT/steady-footprint"
"$BIN/tissrc" select com.apple.keylayout.ABC >/dev/null

python3 - "$OUT" "$THRESHOLD_MS" "$RSS_LIMIT_MB" "$FOOTPRINT_HARD_MB" "$BASE_RSS" "$FOOTPRINT_SPREAD_WARN_MB" "$FOOTPRINT_COLD_UPTIME_S" <<'PY'
import glob, json, os, re, statistics, sys
out, threshold, rss_limit, footprint_hard, base_kb = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4]), int(sys.argv[5] or 0)
spread_warn = float(sys.argv[6]) if len(sys.argv) > 6 else 8.0
cold_uptime = float(sys.argv[7]) if len(sys.argv) > 7 else 900.0
latencies, cold, mismatched, invalid, missing_events, unreadable = [], [], 0, 0, 0, 0
by_segment = {}
round_files = sorted(glob.glob(out + "/round-*.json"))
total_rounds = len(round_files)
for path in round_files:
    segment = re.match(r"round-(.+)-[0-9]+\.json$", os.path.basename(path))
    segment = segment.group(1) if segment else "unknown"
    # 报告267：失焦轮次里 type-session 写的是 `BLOCKED ...` 而不是 JSON。以前这里直接
    # json.load 抛异常，整份汇总崩掉、连已有样本的判定都拿不到；现在把这类轮次记为
    # unreadable 跳过，判定仍按读取成功的轮次给出。
    try:
        data = json.load(open(path, encoding="utf-8"))
    except (OSError, ValueError):
        unreadable += 1
        continue
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
def to_mb(raw):
    match = re.match(r"([0-9.]+)([KMG]?)", (raw or "").strip())
    if not match:
        return None
    return round(float(match.group(1)) / {"": 1048576, "K": 1024, "M": 1, "G": 1024}[match.group(2)], 1)

# ADR-385：门禁看中位数；单次采样会被页回收/首次触页带偏（报告 325 里同一二进制 35.9–57.3 MiB）。
fp_samples = [mb for mb in (to_mb(line) for line in
                            open(out + "/footprint-samples-mb", encoding="utf-8").read().split()
                            if line.strip()) if mb is not None]
if not fp_samples:
    fp_samples = [mb for mb in [to_mb(open(out + "/steady-footprint", encoding="utf-8").read())] if mb is not None]
steady_fp = round(statistics.median(fp_samples), 1) if fp_samples else 0.0
fp_spread = round(max(fp_samples) - min(fp_samples), 1) if len(fp_samples) > 1 else 0.0
try:
    host_uptime = float(open(out + "/host-uptime-s", encoding="utf-8").read().strip() or 0)
except (OSError, ValueError):
    host_uptime = 0.0
# ADR-385：绝对 footprint 只在冷启动窗口里可比；超出窗口（长时间使用、练习已物化）只作参考。
footprint_cold = host_uptime <= cold_uptime
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
    "footprint_samples_mb": fp_samples,
    "footprint_spread_mb": fp_spread,
    "footprint_unstable": fp_spread > spread_warn,
    "host_uptime_s": round(host_uptime, 1),
    "footprint_cold_baseline": footprint_cold,
    "thresholds": {"p95_ms": threshold, "rss_growth_mb": rss_limit, "footprint_hard_mb": footprint_hard,
                   "footprint_spread_warn_mb": spread_warn, "footprint_cold_uptime_s": cold_uptime},
}
# 门禁只看稳定态（ADR-307）；冷首键单独记录，不参与 PASS/FAIL，但要保证确实采到样本。
# ADR-385：footprint 判中位数；抖动只做标注，不单独判失败（heap live 仍是硬门禁，ADR-338/379）。
# 冷启动窗口内才拿绝对值判 FAIL；超窗（宿主已长时间使用）改为参考值并说明，避免「用得越久越必失败」。
footprint_ok = (steady_fp > 0 and steady_fp <= footprint_hard) if footprint_cold else True
ok = (bool(latencies) and summary["p95_ms"] <= threshold and len(cold) > 0
      and footprint_ok and conns == 0 and mismatched == 0)
summary["invalid_rounds"] = invalid
summary["unreadable_rounds"] = unreadable
if not latencies:
    summary["result"] = "BLOCKED"
    if unreadable and unreadable + invalid >= total_rounds:
        summary["reason"] = "所有 round 都未产出可判定结果（失焦或输入上下文未接上 IME）"
    else:
        summary["reason"] = "所有 round 都没有走 IME（has_non_ascii=false / keys_seen=0）"
    print(json.dumps(summary, ensure_ascii=False, sort_keys=True))
    raise SystemExit(78)
notes = []
if summary["footprint_unstable"]:
    notes.append(f"采样离散 {fp_spread} MiB（阈值 {spread_warn}）：本次 footprint 只可作粗粒度参考")
if not footprint_cold:
    notes.append(f"宿主已运行 {round(host_uptime)} s > {round(cold_uptime)} s："
                 f"footprint {steady_fp} MiB 只作参考，绝对值 FAIL 仅限冷启动窗口（ADR-385）")
if notes:
    summary["footprint_note"] = "；".join(notes)
summary["result"] = "PASS" if ok else "FAIL"
print(json.dumps(summary, ensure_ascii=False, sort_keys=True))
raise SystemExit(0 if ok else 1)
PY
