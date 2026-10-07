#!/usr/bin/env bash
# 汇总 docs/experiments/runs/usage.jsonl，输出可对比的用量/成本表。
#
# 用法:
#   ./scripts/usage-report.sh              # 汇总全部
#   ./scripts/usage-report.sh <关键词>      # 只看 label 含该关键词的记录（如 bench-fresh）
#
# 纯本地读取，不消耗任何 token。

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LOG="${PI_USAGE_LOG:-docs/experiments/runs/usage.jsonl}"
if [ ! -f "$LOG" ]; then
  echo "ℹ️  暂无数据（$LOG 不存在）。先运行 dispatch-task.sh 或 bench-session-vs-workers.sh。"
  exit 0
fi

filter="${1:-}"
if [ -n "$filter" ]; then
  data="$(jq -s --arg f "$filter" '[.[] | select(.label | contains($f))]' "$LOG")"
else
  data="$(jq -s '.' "$LOG")"
fi

runs="$(jq 'length' <<<"$data")"
if [ "$runs" -eq 0 ]; then
  echo "ℹ️  无匹配记录（filter=${filter:-无}）。"
  exit 0
fi

printf '## 总览（%d 次调用）\n\n' "$runs"
jq -r '
  ["runs","totalTokens","input","output","cacheRead","cacheWrite","cost"],
  [ (length|tostring),
    (map(.totalTokens)|add//0|tostring),
    (map(.input)|add//0|tostring),
    (map(.output)|add//0|tostring),
    (map(.cacheRead)|add//0|tostring),
    (map(.cacheWrite)|add//0|tostring),
    ((map(.cost)|add//0)*1000000|round/1000000|tostring) ]
  | @tsv' <<<"$data" | column -t -s $'\t'

printf '\n## 按模式分组（关键对比）\n\n'
jq -r '
  ["mode","runs","avgTokens","avgCost(µ$)","cacheRead","cacheWrite","cacheHitRate"],
  ( group_by(.mode)
    | map(
        ( map(.cacheRead)|add//0 ) as $cr
        | ( map(.input)|add//0 ) as $in
        | [ .[0].mode,
            (length|tostring),
            ((map(.totalTokens)|add//0)/length|round|tostring),
            ((map(.cost)|add//0)/length*1000000|round|tostring),
            ($cr|tostring),
            ((map(.cacheWrite)|add//0)|tostring),
            (if ($cr+$in)==0 then "n/a"
             else ((($cr / ($cr+$in))*1000|round/10)|tostring)+"%" end) ]
      )
    | sort_by(.[0]) | .[] )
  | @tsv' <<<"$data" | column -t -s $'\t'

printf '\n## 按标签分组\n\n'
jq -r '
  ["label","mode","runs","tokens","cost(µ$)","cacheRead","exit!=0"],
  ( group_by(.label)
    | map([ .[0].label, .[0].mode, (length|tostring),
            ((map(.totalTokens)|add//0)|tostring),
            ((map(.cost)|add//0)*1000000|round|tostring),
            ((map(.cacheRead)|add//0)|tostring),
            ((map(select(.exit!=0))|length)|tostring) ])
    | sort_by(.[0]) | .[] )
  | @tsv' <<<"$data" | column -t -s $'\t'

printf '\n> cacheHitRate = cacheRead / (cacheRead + input)。越高越省：reuse 会话应显著高于 fresh。\n'
