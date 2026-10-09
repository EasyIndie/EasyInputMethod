#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORK="$(mktemp -d -t lampyris-render-perf)"
trap 'rm -rf "${WORK}"' EXIT
case "${1:-}" in
  "") ;;
  --max-user-dictionary) python3 "${ROOT}/platforms/macos/tests/make-user-fixture.py" "${WORK}/user-dictionary.tsv" ;;
  *) echo "用法：$0 [--max-user-dictionary]" >&2; exit 2 ;;
esac
(cd "${ROOT}" && cargo build --release -p ime-ffi)
swiftc -O -whole-module-optimization -target "$(uname -m)-apple-macosx13.0" \
  -module-cache-path "${WORK}/module-cache" -I "${ROOT}/crates/ime-ffi/include" \
  "${ROOT}/platforms/macos/tests/render_perf.swift" \
  "${ROOT}/platforms/macos/Sources/ImeSession.swift" \
  "${ROOT}/platforms/macos/Sources/CandidateWindow.swift" \
  "${ROOT}/platforms/macos/Sources/Config.swift" \
  -Xlinker "${ROOT}/target/release/libime_ffi.a" -framework Cocoa -o "${WORK}/probe"
"${WORK}/probe" "${ROOT}/data/generated" "${WORK}/config.toml" ${2:+"$2"}
