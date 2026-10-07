#!/usr/bin/env bash
# A/B 实验：对比"每次新 worker" vs "一个持久会话跑完所有任务"的 token/成本。
#
# 用法:
#   ./scripts/bench-session-vs-workers.sh --micro            # 廉价的冷启动开销微基准
#   ./scripts/bench-session-vs-workers.sh --tasks "docs/tasks/T-M1-01.md docs/tasks/T-M1-04.md"
#
# 选项:
#   --tasks "<卡1 卡2 ...>"  完整 A/B 的工作负载（会真的跑 pi，花 token！）
#   --micro                 只测冷启动开销（跑 3 次极短 prompt）
#   --model <名>            模型（默认 $PI_BENCH_MODEL 或 deepseek-v4-flash）
#
# 两个 worktree 隔离（主仓库不受影响）；结果写入 docs/experiments/runs/usage.jsonl，
# 用 ./scripts/usage-report.sh bench- 汇总。
#
# 测试管道（不花 token）：PI_CMD=echo ./scripts/bench-session-vs-workers.sh --micro

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# shellcheck source=lib/pi-usage.sh
source scripts/lib/pi-usage.sh
export PI_USAGE_LOG="${PI_USAGE_LOG:-$ROOT/docs/experiments/runs/usage.jsonl}"
export PI_RAW_DIR="${PI_RAW_DIR:-$ROOT/docs/experiments/runs/raw}"

model="${PI_BENCH_MODEL:-deepseek-v4-flash}"
tasks=""
micro=0
while [ $# -gt 0 ]; do
  case "$1" in
    --model) model="$2"; shift 2 ;;
    --tasks) tasks="$2"; shift 2 ;;
    --micro) micro=1; shift ;;
    *) echo "未知参数: $1"; exit 2 ;;
  esac
done

ts="$(date -u +%Y%m%dT%H%M%SZ)"
rundir="$ROOT/docs/experiments/runs/bench-$ts"
mkdir -p "$rundir"
base="$(mktemp -d)"
cleanup() { git worktree remove --force "$base/wt-fresh" 2>/dev/null || true;
            git worktree remove --force "$base/wt-reuse" 2>/dev/null || true;
            git worktree remove --force "$base/wt-micro" 2>/dev/null || true;
            rm -rf "$base"; }
trap cleanup EXIT

make_wt() { local d="$base/wt-$1"; git worktree add -q --detach "$d" HEAD; echo "$d"; }

prompt_for() { # $1 卡片相对路径
  echo "严格执行任务卡 ${1}：先读 AGENTS.md 与 HANDOFF.md，按卡执行，完成后跑 make verify，只回简明摘要（≤15 行）。"
}

if [ "$micro" = 1 ]; then
  echo "▶ 微基准：冷启动开销（模型 ${model}）"
  wt="$(make_wt micro)"
  p="只回复两个字：收到"
  ( cd "$wt" && pi_measure "micro-fresh" "$model" "fresh" "$rundir/sess-micro-fresh" "$p" >/dev/null )
  ( cd "$wt" && pi_measure "micro-reuse-1" "$model" "reuse" "$rundir/sess-micro-reuse" "$p" >/dev/null )
  ( cd "$wt" && pi_measure "micro-reuse-2" "$model" "reuse" "$rundir/sess-micro-reuse" "$p" >/dev/null )
  echo "✅ 完成。汇总： ./scripts/usage-report.sh micro-"
  exit 0
fi

[ -n "$tasks" ] || { echo "需要 --tasks \"<卡...>\" 或 --micro"; exit 2; }
for c in $tasks; do [ -f "$c" ] || { echo "任务卡不存在: $c"; exit 1; }; done

echo "▶ A/B 开始（模型 ${model}）"
echo "  A 臂 = 每次新 worker；B 臂 = 一个持久会话"

wt_f="$(make_wt fresh)"
wt_r="$(make_wt reuse)"
i=0
for c in $tasks; do
  i=$((i+1)); l="bench-fresh:$(basename "$c" .md)"
  echo "  [A/$i] $c"
  ( cd "$wt_f" && pi_measure "$l" "$model" "fresh" "$rundir/sess-fresh-$i" "$(prompt_for "$c")" >/dev/null )
done
i=0
for c in $tasks; do
  i=$((i+1)); l="bench-reuse:$(basename "$c" .md)"
  echo "  [B/$i] $c"
  ( cd "$wt_r" && pi_measure "$l" "$model" "reuse" "$rundir/sess-reuse" "$(prompt_for "$c")" >/dev/null )
done

echo "✅ 完成。汇总： ./scripts/usage-report.sh bench-"
