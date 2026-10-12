#!/usr/bin/env bash
# Independent native panel test resources; never target the installed IMK host.
set -euo pipefail
case "${1:-}" in
  --isolation-probe|--interactive) ;;
  *) echo 'BLOCKED：请用--isolation-probe验证隔离，或--interactive启动独有测试应用；完整UI结果单独记录。' >&2; exit 3 ;;
esac
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
"${ROOT}/platforms/macos/dev-preview.sh" --build-only
if [ "$1" = --isolation-probe ]; then
    exec python3 "${ROOT}/platforms/macos/tests/run-panel-isolation.py"
fi
exec python3 "${ROOT}/platforms/macos/tests/run-panel-interactive.py"
