#!/usr/bin/env bash
# 零诊断门禁：运行给定命令，输出照常转发；若日志里出现工具链的 warning/error 级诊断，
# 则在命令自身退出码之外以 9 退出。见 docs/开发工作流.md §4。
#
# 为什么需要它：`cargo test`/`cargo deny` 即使有警告也返回 0，clippy 的 `-D warnings`
# 也管不到 cargo 自己打印的告警（例如 "output filename collision"）。这里统一把关，
# 代价只是「同一次运行 + 一次 grep」，不额外编译。
#
# 只匹配「行首即诊断」的形式，避免误伤测试名（如 `test ..._returns_error ... ok`）。
#
# 用法：scripts/check-clean.sh <命令> [参数...]
set -uo pipefail

if [ "$#" -eq 0 ]; then
  echo "用法：$0 <命令> [参数...]" >&2
  exit 2
fi

log="$(mktemp)"
trap 'rm -f "${log}"' EXIT

"$@" 2>&1 | tee "${log}"
rc="${PIPESTATUS[0]}"

# 三种形态：`warning: ` / `error: `（cargo、rustc、swiftc 前缀式）、
# `warning[x]` / `error[x]` / `bug[x]`（cargo-deny 诊断）、
# `path:line:col: warning: `（swiftc / clang）。
pattern='^(warning|error)(\[|:)|^bug\[|[^[:space:]]+:[0-9]+:[0-9]+: (warning|error):'
hits="$(grep -nE "${pattern}" "${log}" || true)"
if [ -n "${hits}" ]; then
  printf '\n❌ 零诊断门禁未通过（以下诊断必须清零）：\n%s\n' "${hits}" >&2
  [ "${rc}" -ne 0 ] || rc=9
fi

exit "${rc}"
