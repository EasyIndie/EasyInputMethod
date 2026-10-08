#!/usr/bin/env bash
# 编译并运行宿主 FFI 冒烟（真实数据文件）。
#
# 用法：./platforms/macos/tests/run-ffi-smoke.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
GEN="${ROOT}/data/generated"
WUBI="${GEN}/wubi86-core.tsv"
CHARS="${GEN}/pinyin-chars.tsv"
WORDS="${GEN}/pinyin-words.tsv"

for f in "${WUBI}" "${CHARS}" "${WORDS}"; do
  if [ ! -f "${f}" ]; then
    echo "❌ 缺少数据文件：${f}"
    echo "   词表可由 data/sources/fetch-*.sh + 'cargo run -p ime-pinyin --example generate' 复现。"
    exit 1
  fi
done

echo "▶ 构建 ime-ffi staticlib"
( cd "${ROOT}" && cargo build --release -p ime-ffi )

BIN="$(mktemp -t ime_ffi_smoke)"
trap 'rm -f "${BIN}"' EXIT

echo "▶ 编译 Swift 冒烟（swiftc）"
swiftc -O \
  -I "${ROOT}/crates/ime-ffi/include" \
  "${SCRIPT_DIR}/ffi_smoke.swift" \
  "${ROOT}/target/release/libime_ffi.a" \
  -o "${BIN}"

echo "▶ 运行"
"${BIN}" "${WUBI}" "${CHARS}" "${WORDS}"
