#!/usr/bin/env bash
# 对比 fresh vs reuse 的每轮总 token，输出中位数（跨 repeat 取中位数，抗方差）。
#
# 用法:
#   ./scripts/usage-compare.sh [workload 名]     # 省略则汇总所有 bench-* 记录
#
# 只看形如 bench-<arm>:<wl>:r<rep>:p<i> 的记录；纯本地，不花 token。

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
LOG="${PI_USAGE_LOG:-docs/experiments/runs/usage.jsonl}"
[ -f "$LOG" ] || { echo "ℹ️  无数据（$LOG）"; exit 0; }

wl="${1:-}"
rows="$(jq -s --arg wl "$wl" '
  [ .[]
    | select(.label | test("^bench-[^:]+:[^:]+:r[0-9]+:p[0-9]+$"))
    | select($wl=="" or (.label | contains(":"+$wl+":")))
    | . + (.label | capture("^bench-(?<arm>[^:]+):(?<w>[^:]+):r(?<rep>[0-9]+):p[0-9]+$"))
  ]
  | group_by([.w,.arm,.rep])
  | map({ w:.[0].w, arm:.[0].arm, rep:.[0].rep,
          toks:(map(.totalTokens)|add), cin:(map(.input)|add),
          cread:(map(.cacheRead)|add), out:(map(.output)|add) })
  | group_by([.w,.arm])
  | map({
      w: .[0].w, arm: .[0].arm, n: length,
      med_toks:  ((map(.toks) |sort) as $s | ($s|length) as $n | if $n%2==1 then $s[($n-1)/2] else ((($s[$n/2-1]+$s[$n/2])/2)|floor) end),
      med_cin:   ((map(.cin)  |sort) as $s | ($s|length) as $n | if $n%2==1 then $s[($n-1)/2] else ((($s[$n/2-1]+$s[$n/2])/2)|floor) end),
      med_cread: ((map(.cread)|sort) as $s | ($s|length) as $n | if $n%2==1 then $s[($n-1)/2] else ((($s[$n/2-1]+$s[$n/2])/2)|floor) end),
      med_out:   ((map(.out)  |sort) as $s | ($s|length) as $n | if $n%2==1 then $s[($n-1)/2] else ((($s[$n/2-1]+$s[$n/2])/2)|floor) end)
    })
  | sort_by([.w,.arm])
' "$LOG")"

n="$(jq 'length' <<<"$rows")"
[ "$n" -gt 0 ] || { echo "ℹ️  无匹配的 bench- 记录（wl=${wl:-全部}）"; exit 0; }

printf '## 中位数对比（跨 repeat，抗方差）\n\n'
jq -r '
  ["workload","arm","reps","med_tokens","med_input","med_cacheRead","med_output"],
  ( .[] | [ .w, .arm, (.n|tostring), (.med_toks|tostring),
            (.med_cin|tostring), (.med_cread|tostring), (.med_out|tostring) ] )
  | @tsv' <<<"$rows" | column -t -s $'\t'

printf '\n## reuse / fresh 比值（med_tokens）\n\n'
jq -r '
  ( group_by(.w)
    | map(
        ( map(select(.arm=="fresh"))[0].med_toks // 0 ) as $f
        | ( map(select(.arm=="reuse"))[0].med_toks // 0 ) as $r
        | [ .[0].w, ($f|tostring), ($r|tostring),
            (if $f==0 then "n/a" else (((($r/$f - 1)*1000)|round/10)|tostring)+"%" end) ]
      )
    | sort_by(.[0]) )
  | (["workload","fresh_med","reuse_med","reuse相对fresh"],
     .[])
  | @tsv' <<<"$rows" | column -t -s $'\t'

printf '\n> 比值 <0%% ⇒ reuse 更省；>0%% ⇒ fresh 更省。看中位数，不看单次。\n'
