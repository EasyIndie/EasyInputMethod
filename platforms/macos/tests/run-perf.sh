#!/usr/bin/env bash
# Release engine performance only; this does not measure IMK client rendering.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORK="$(mktemp -d -t yinghuo-perf)"
trap 'rm -rf "${WORK}"' EXIT
EXTRA=()
case "${2:-}" in
  "") ;;
  --max-user-dictionary) EXTRA=(--learn-check); python3 "${ROOT}/platforms/macos/tests/make-user-fixture.py" "${WORK}/user-dictionary.tsv" ;;
  *) echo "用法：$0 [1-16会话] [--max-user-dictionary]" >&2; exit 2 ;;
esac
(cd "${ROOT}" && cargo build --release -p ime-ffi)
clang -O2 -I "${ROOT}/crates/ime-ffi/include" \
  "${ROOT}/platforms/macos/tests/perf_probe.c" "${ROOT}/target/release/libime_ffi.a" \
  -framework CoreFoundation -framework Security -liconv -o "${WORK}/probe"
"${WORK}/probe" "${ROOT}/data/generated/wubi86-core.tsv" \
  "${ROOT}/data/generated/pinyin-chars.tsv" "${ROOT}/data/generated/pinyin-core.tsv" "${WORK}/config.toml" "${1:-1}" ${EXTRA[@]+"${EXTRA[@]}"}
