#!/usr/bin/env bash
# 萤火虫输入法 — C ABI 冒烟：构建 staticlib → clang 链接运行 C 程序 → swiftc typecheck。
#
# 用法：./crates/ime-ffi/tests/run-c-smoke.sh
set -euo pipefail

CRATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$CRATE_DIR/../.." && pwd)"
cd "$ROOT"

echo "▶ 1/3 构建 staticlib"
cargo build -p ime-ffi --release

LIB="$(find target/release -maxdepth 1 -name 'libime_ffi.a' -print -quit)"
if [ -z "$LIB" ]; then
  echo "❌ 找不到 staticlib（target/release/libime_ffi.a）"
  exit 1
fi
echo "  staticlib: $LIB"

echo "▶ 2/3 clang 链接并运行 C 冒烟程序"
BIN="/tmp/ime_ffi_c_smoke"
clang "$CRATE_DIR/tests/c_smoke.c" -I "$CRATE_DIR/include" "$LIB" -o "$BIN"
"$BIN"

echo "▶ 3/3 swiftc -typecheck（import ime）"
swiftc -typecheck -I "$CRATE_DIR/include" "$CRATE_DIR/tests/swift_typecheck.swift"

echo "✅ C ABI 冒烟通过（C 链接运行 + Swift typecheck）"
