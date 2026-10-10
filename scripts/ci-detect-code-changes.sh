#!/usr/bin/env bash
# CI 辅助：判断本次变更是否"代码相关"，以决定是否执行重型检查（macos / fuzz）。
#
# 规则（见 .github/workflows/ci.yml、docs/开发工作流.md）：
#   - pull_request：比较 base 与 HEAD 的文件列表；仅 docs/ 等变更视为"非代码"。
#   - 其它事件（push 到 main 等）或缺少 base：一律 true（重型检查全跑）。
#
# 输出：true / false（stdout，供 $GITHUB_OUTPUT 使用）。
set -euo pipefail

if [ "${GITHUB_EVENT_NAME:-}" != "pull_request" ] || [ -z "${GITHUB_BASE_SHA:-}" ]; then
  echo true
  exit 0
fi

files="$(git diff --name-only "${GITHUB_BASE_SHA}" HEAD 2>/dev/null || true)"
if printf '%s\n' "${files}" \
  | grep -qE '^(crates/|fuzz/|platforms/|tools/|data/|packaging/|Makefile$|Cargo\.(toml|lock)$|rust-toolchain\.toml$|deny\.toml$)'; then
  echo true
else
  echo false
fi
