#!/usr/bin/env bash
# 派发任务卡给指定模型 headless 执行，并记录 token / 成本。
#
# 用法:
#   ./scripts/dispatch-task.sh <docs/tasks/T-XXX.md> [选项]
#
# 选项:
#   --model <名>    使用模型（默认 $PI_BENCH_MODEL 或 deepseek-v4-flash）
#   --provider <名>  指定 provider（当模型名在多 provider 下歧义时必需，如 pro）
#   --reuse <会话名> 复用同一会话（缓存热）；仅用于强依赖序列
#   --label <名>    记录用的标签（默认取任务卡文件名）
#   --jobs <N>      传给 worker 的 CARGO_BUILD_JOBS（控制编译并行度，防 CPU 超订）
#   --min-free-gb <N> 磁盘余量下限（默认 3 GiB），不足则拒绝派发
#
# 用量写入 docs/experiments/runs/usage.jsonl；用 ./scripts/usage-report.sh 汇总。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# 绝对路径须在 source 之前（source 会写入相对默认值）。
export PI_USAGE_LOG="${PI_USAGE_LOG:-$ROOT/docs/experiments/runs/usage.jsonl}"
export PI_RAW_DIR="${PI_RAW_DIR:-$ROOT/docs/experiments/runs/raw}"
# shellcheck source=lib/pi-usage.sh
source scripts/lib/pi-usage.sh

card="${1:?用法: dispatch-task.sh <docs/tasks/T-XXX.md> [--model M] [--reuse 名] [--label 名]}"
shift
[ -f "$card" ] || { echo "任务卡不存在: $card"; exit 1; }

model="${PI_BENCH_MODEL:-deepseek-v4-flash}"
provider=""
mode="fresh"
sdir=""
jobs=""
min_free_gb=3
label="$(basename "$card" .md)"

while [ $# -gt 0 ]; do
  case "$1" in
    --model) model="$2"; shift 2 ;;
    --provider) provider="$2"; shift 2 ;;
    --reuse) mode="reuse"; sdir="docs/experiments/runs/sessions/$2"; shift 2 ;;
    --label) label="$2"; shift 2 ;;
    --jobs) jobs="$2"; shift 2 ;;
    --min-free-gb) min_free_gb="$2"; shift 2 ;;
    *) echo "未知参数: $1"; exit 2 ;;
  esac
done

# 派发前预检：磁盘余量（Rust 编译会显著占盘）
require_disk_headroom "$min_free_gb" || exit 1
if [ -n "$jobs" ]; then
  export CARGO_BUILD_JOBS="$jobs"
  echo "🔧 CARGO_BUILD_JOBS=${jobs}（限制 worker 编译并行度）"
fi

prompt="你是萤火虫输入法（EasyInputMethod）仓库的执行代理。
1. 先读根目录 AGENTS.md（铁律/工作流/约定）与 HANDOFF.md（当前状态）。
2. 完整阅读并**严格执行**任务卡：$card
3. 完成后运行 \`make verify\`，确保全绿。
4. 更新 HANDOFF.md（会话日志追加一条）与 ROADMAP.md（勾选完成项）。
5. 只回**简明摘要**（≤15 行）：改了什么 / 如何验证（贴命令与结果）/ 风险与未决问题。
注意：一次只做这一张卡，不做卡外的事；不要粘贴大段代码或完整 transcript。"

pargs=()
[ -n "$provider" ] && pargs=(--provider "$provider")

echo "▶ 派发 $card → 模型 ${model}（provider=${provider:-默认}，mode=${mode}）"
usage="$(pi_measure "$label" "$model" "$mode" "$sdir" "$prompt" ${pargs[@]+"${pargs[@]}"})"
echo "💰 本次用量: $usage"
