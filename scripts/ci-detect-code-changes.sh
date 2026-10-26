#!/usr/bin/env bash
# CI 辅助：判断本次变更属于哪条泳道（ADR-293），决定重型检查的档位。
#
# 输出一行 `lane=full|tooling|docs`（供 $GITHUB_OUTPUT 使用），并额外输出
# `code=true|false` 以兼容旧调用（full/tooling 视为 true）。
#
#   full     产品码：crates/ platforms/ data/ Cargo.* rust-toolchain.toml deny.toml
#   tooling  工具与打包：tools/ scripts/ packaging/ .github/ Makefile
#   docs     文档与站点：docs/ *.md site/ 及其它未列出的路径
#
# 非 pull_request 事件（push 到 main 等）或缺少 base：一律 full，宁可多跑。
set -euo pipefail

if [ "${GITHUB_EVENT_NAME:-}" != "pull_request" ] || [ -z "${GITHUB_BASE_SHA:-}" ]; then
  echo "lane=full"
  echo "code=true"
  exit 0
fi

files="$(git diff --name-only "${GITHUB_BASE_SHA}" HEAD 2>/dev/null || true)"
lane=docs

product='^(crates/|platforms/|data/|Cargo\.(toml|lock)$|rust-toolchain\.toml$|deny\.toml$)'
tooling='^(tools/|scripts/|packaging/|\.github/|Makefile$)'

if printf '%s\n' "${files}" | grep -qE "${product}"; then
  lane=full
elif printf '%s\n' "${files}" | grep -qE "${tooling}"; then
  lane=tooling
fi

echo "lane=${lane}"
if [ "${lane}" = "docs" ]; then echo "code=false"; else echo "code=true"; fi
