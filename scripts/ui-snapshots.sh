#!/usr/bin/env bash
# 离屏渲染候选 / 关于 / 设置 / 诊断面板（亮暗 + 固定样例），快速看 UI 改动效果。
# 不显示任何窗口、不读真实配置、不碰已安装包。
#
# 用法：
#   make macos-ui-snapshots                 # 候选窗 + 其它面板
#   make macos-ui-snapshots UI=candidate    # 只渲染候选窗（少编译一半源码）
#   OUT=~/Desktop/shots make macos-ui-snapshots
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${OUT:-$ROOT/platforms/macos/build/ui-snapshots}"
ONLY="${UI:-all}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/lampyris-ui-snapshots.XXXXXX")"
CACHE="$ROOT/platforms/macos/build/ui-snapshots/.cache"
trap 'rm -rf "$TMP"' EXIT
cd "$ROOT"

mkdir -p "$TMP" "$OUT" "$CACHE"
cp assets/icons/yinghuo-official-app.icns "$TMP/icon.icns"

CANDIDATE_SOURCES=(
    platforms/macos/Sources/ImeSession.swift
    platforms/macos/Sources/Config.swift
    platforms/macos/Sources/CandidateWindow.swift
)
PANEL_SOURCES=(
    platforms/macos/Sources/ImeSession.swift
    platforms/macos/Sources/Config.swift
    platforms/macos/Sources/CandidateWindow.swift
    platforms/macos/Sources/Settings.swift
    platforms/macos/Sources/Feedback.swift
    platforms/macos/Sources/InfoWindow.swift
    platforms/macos/Sources/UserDictionary.swift
    platforms/macos/Sources/Lookup.swift
)

cargo build --release -p ime-ffi >/dev/null
cp platforms/macos/tests/ui-snapshots.swift "$TMP/main.swift"

build() {
    local name="$1" define="$2"
    shift 2
    local sources=("$@")
    local stamp="$CACHE/$name.sha"
    local hash
    hash=$(cat "$TMP/main.swift" "${sources[@]}" | shasum -a 256 | awk '{print $1}')
    if [[ -x "$CACHE/$name" && -f "$stamp" && "$(cat "$stamp")" == "$hash" ]]; then
        echo "▶ ${name}：源码未变，复用上次编译"
        return 0
    fi
    echo "▶ ${name}：编译中（首次或源码有改动）"
    swiftc -Onone -warnings-as-errors -I crates/ime-ffi/include "$define" \
        "$TMP/main.swift" "${sources[@]}" \
        target/release/libime_ffi.a -framework AppKit -o "$CACHE/$name"
    printf '%s' "$hash" > "$stamp"
}

if [[ "$ONLY" != "panels" ]]; then
    build candidate "" "${CANDIDATE_SOURCES[@]}"
    "$CACHE/candidate" "$TMP" "$OUT"
fi
if [[ "$ONLY" != "candidate" ]]; then
    build panels "-DUI_PANELS" "${PANEL_SOURCES[@]}"
    "$CACHE/panels" "$TMP" "$OUT"
fi

echo "✅ 图片目录：${OUT}（模式 ${ONLY}）"
