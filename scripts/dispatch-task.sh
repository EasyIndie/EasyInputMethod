#!/usr/bin/env bash
# 派发任务卡给指定的低成本模型 headless 执行（把 flash 当子代理用）。
#
# 用法:
#   ./scripts/dispatch-task.sh <docs/tasks/T-XXX.md> [模型]
#
# 模型名以 `/model` 或 `pi --model` 实际可用为准；deepseek-v4-flash 是占位示例。

set -euo pipefail

card="${1:?用法: dispatch-task.sh <docs/tasks/T-XXX.md> [模型]}"
model="${2:-deepseek-v4-flash}"

[ -f "$card" ] || { echo "任务卡不存在: $card"; exit 1; }

prompt="你是萤火虫输入法（EasyInputMethod）仓库的执行代理。
1. 先读根目录 AGENTS.md（铁律/工作流/约定）与 HANDOFF.md（当前状态）。
2. 完整阅读并**严格执行**任务卡：$card
3. 完成后运行 \`make verify\`，确保全绿。
4. 更新 HANDOFF.md（会话日志追加一条）与 ROADMAP.md（勾选完成项）。
5. 用简洁格式汇报：改了什么 / 如何验证（贴命令与结果）/ 风险与未决问题。
注意：一次只做这一张卡，不做卡外的事。"

pi --print --model "$model" "$prompt"
