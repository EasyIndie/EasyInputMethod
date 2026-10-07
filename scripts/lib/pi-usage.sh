#!/usr/bin/env bash
# pi 用量量测助手 —— 被其它脚本 `source`，不直接执行。
#
# 目的：把每次 headless pi 调用的 token / 成本记录下来，用于对比
#   "一个持久会话" vs "每次新 worker" 的经济性（见 docs/experiments/）。
#
# 记录格式（JSONL，追加到 $PI_USAGE_LOG）：
#   {"ts","label","model","mode","session","input","output",
#    "cacheRead","cacheWrite","totalTokens","cost","exit"}
#
# 可用环境变量覆盖：
#   PI_CMD        pi 可执行文件（默认 pi，便于用桩测试）
#   PI_USAGE_LOG  用量日志路径
#   PI_RAW_DIR    原始事件流目录

PI_CMD="${PI_CMD:-pi}"
PI_USAGE_LOG="${PI_USAGE_LOG:-docs/experiments/runs/usage.jsonl}"
PI_RAW_DIR="${PI_RAW_DIR:-docs/experiments/runs/raw}"

# 从 `pi --mode json` 事件流提取累计用量。
# 计费口径：assistant 的 message_end.usage + type=="usage" 条目（二者不重叠）。
pi_extract_usage() {
  jq -s '
    ([.[] | select(.type=="message_end") | .message
        | select(.role=="assistant") | .usage]
     + [.[] | select(.type=="usage") | .usage])
    | map(select(. != null))
    | {
        input:       (map(.input // 0)       | add // 0),
        output:      (map(.output // 0)      | add // 0),
        cacheRead:   (map(.cacheRead // 0)   | add // 0),
        cacheWrite:  (map(.cacheWrite // 0)  | add // 0),
        totalTokens: (map(.totalTokens // 0) | add // 0),
        cost:        (map(.cost.total // 0)  | add // 0)
      }' "$1" 2>/dev/null \
  || echo '{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"totalTokens":0,"cost":0}'
}

# pi_measure <label> <model> <mode:fresh|reuse> <session_dir> <prompt>
#   mode=reuse 且同 session_dir 已跑过 → 自动加 --continue（保持缓存热）。
# 结果写入 $PI_USAGE_LOG，并把用量 JSON 打到 stdout。
pi_measure() {
  local label="$1" model="$2" mode="$3" sdir="$4" prompt="$5"; shift 5
  local ts raw usage exit_code=0
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "$PI_RAW_DIR" "$(dirname "$PI_USAGE_LOG")"
  [ -n "$sdir" ] && mkdir -p "$sdir"
  raw="$PI_RAW_DIR/${ts}-${label//\//_}.jsonl"

  local -a args=(--mode json --model "$model")
  [ -n "$sdir" ] && args+=(--session-dir "$sdir")
  if [ "$mode" = "reuse" ] && [ -n "$sdir" ] && [ -f "$sdir/.seen" ]; then
    args+=(--continue)
  fi
  [ -n "$sdir" ] && : > "$sdir/.seen"

  "$PI_CMD" "${args[@]}" "$@" "$prompt" >"$raw" 2>"${raw}.err" || exit_code=$?

  usage="$(pi_extract_usage "$raw")"
  jq -cn \
    --arg ts "$ts" --arg label "$label" --arg model "$model" \
    --arg mode "$mode" --arg sdir "${sdir:-<default>}" \
    --argjson u "$usage" --argjson ec "$exit_code" \
    '{ts:$ts,label:$label,model:$model,mode:$mode,session:$sdir,
      input:$u.input,output:$u.output,cacheRead:$u.cacheRead,
      cacheWrite:$u.cacheWrite,totalTokens:$u.totalTokens,
      cost:$u.cost,exit:$ec}' >>"$PI_USAGE_LOG"
  echo "$usage"
}
