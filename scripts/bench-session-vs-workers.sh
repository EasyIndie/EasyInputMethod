#!/usr/bin/env bash
# A/B 实验：对比"每次新 worker(fresh)" vs "一个持久会话(reuse)" 的 token 成本。
#
# 用法:
#   ./scripts/bench-session-vs-workers.sh --micro                       # 固定开销微基准
#   ./scripts/bench-session-vs-workers.sh --workload <文件> --repeat 5   # 自定义负载（每行一 prompt）
#   ./scripts/bench-session-vs-workers.sh --tasks "卡1 卡2" --repeat 3    # 任务卡负载
#
# 选项: --model M   --repeat N   --name 名称   --workload 文件   --tasks "卡..."
#
# 每臂每轮在独立 git worktree 中执行（主仓库不受影响）；结果写入
# docs/experiments/runs/usage.jsonl，用 ./scripts/usage-compare.sh <name> 出中位数对比。
#
# 不花 token 地验证管道：PI_CMD=echo ./scripts/bench-session-vs-workers.sh --micro

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# 绝对路径必须在 source 之前：source 会写入相对默认值，而子 shell 会 cd 进 worktree。
export PI_USAGE_LOG="${PI_USAGE_LOG:-$ROOT/docs/experiments/runs/usage.jsonl}"
export PI_RAW_DIR="${PI_RAW_DIR:-$ROOT/docs/experiments/runs/raw}"
# shellcheck source=lib/pi-usage.sh
source scripts/lib/pi-usage.sh

model="${PI_BENCH_MODEL:-deepseek-v4-flash}"
tasks="" ; workload="" ; repeat=1 ; micro=0 ; wname=""
while [ $# -gt 0 ]; do
  case "$1" in
    --model) model="$2"; shift 2 ;;
    --tasks) tasks="$2"; shift 2 ;;
    --workload) workload="$2"; shift 2 ;;
    --repeat) repeat="$2"; shift 2 ;;
    --name) wname="$2"; shift 2 ;;
    --micro) micro=1; shift ;;
    *) echo "未知参数: $1"; exit 2 ;;
  esac
done

# ---- 组装 prompts ----
prompts=()
if [ "$micro" = 1 ]; then
  wname="${wname:-micro}"
  prompts=("只回复两个字：收到")
elif [ -n "$workload" ]; then
  [ -f "$workload" ] || { echo "负载文件不存在: $workload"; exit 1; }
  wname="${wname:-$(basename "$workload" .txt)}"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*|'>'*) continue ;; esac
    prompts+=("$line")
  done < "$workload"
elif [ -n "$tasks" ]; then
  wname="${wname:-cards}"
  for c in $tasks; do
    [ -f "$c" ] || { echo "任务卡不存在: $c"; exit 1; }
    prompts+=("严格执行任务卡 $c：先读 AGENTS.md 与 HANDOFF.md，按卡执行，完成后跑 make verify，只回简明摘要（≤15 行）。")
  done
else
  echo "需要 --micro / --workload <文件> / --tasks \"<卡...>\" 之一"; exit 2
fi
[ "${#prompts[@]}" -gt 0 ] || { echo "负载为空"; exit 1; }

ts="$(date -u +%Y%m%dT%H%M%SZ)"
rundir="$ROOT/docs/experiments/runs/bench-$ts-${wname}"
mkdir -p "$rundir"
base="$(mktemp -d)"
cleanup() { git worktree prune >/dev/null 2>&1 || true; rm -rf "$base"; }
trap cleanup EXIT

run_prompt() { # $1 worktree $2 label $3 mode $4 session_dir $5 prompt
  ( cd "$1" && pi_measure "$2" "$model" "$3" "$4" "$5" >/dev/null )
}

echo "▶ A/B：workload=${wname}  模型=${model}  重复=${repeat}  提示数=${#prompts[@]}"
echo "  臂 A = 每次新 worker(fresh)   臂 B = 一个持久会话(reuse)"
for rep in $(seq 1 "$repeat"); do
  wt_f="$base/wt-fresh-r$rep"; git worktree add -q --detach "$wt_f" HEAD
  wt_r="$base/wt-reuse-r$rep"; git worktree add -q --detach "$wt_r" HEAD
  i=0
  for p in "${prompts[@]}"; do
    i=$((i+1))
    run_prompt "$wt_f" "bench-fresh:${wname}:r${rep}:p${i}" fresh "$rundir/sess-fresh-${wname}-r${rep}-p${i}" "$p"
    run_prompt "$wt_r" "bench-reuse:${wname}:r${rep}:p${i}" reuse "$rundir/sess-reuse-${wname}-r${rep}" "$p"
  done
  git worktree remove --force "$wt_f" 2>/dev/null || true
  git worktree remove --force "$wt_r" 2>/dev/null || true
  echo "  rep ${rep}/${repeat} 完成"
done

echo "✅ 完成。中位数对比： ./scripts/usage-compare.sh ${wname}"
