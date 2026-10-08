#!/usr/bin/env bash
# Release engine performance only; this does not measure IMK client rendering.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORK="$(mktemp -d -t yinghuo-perf)"
trap 'rm -rf "${WORK}"' EXIT
(cd "${ROOT}" && cargo build --release -p ime-ffi)
clang -O2 -I "${ROOT}/crates/ime-ffi/include" \
  "${ROOT}/platforms/macos/tests/perf_probe.c" "${ROOT}/target/release/libime_ffi.a" \
  -framework CoreFoundation -framework Security -liconv -o "${WORK}/probe"
"${WORK}/probe" "${ROOT}/data/generated/wubi86-core.tsv" \
  "${ROOT}/data/generated/pinyin-chars.tsv" "${ROOT}/data/generated/pinyin-core.tsv" "${WORK}/config.toml"
