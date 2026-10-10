#!/usr/bin/env bash
# 本地独立窗口：debug 增量构建，不注册/安装系统输入法，不上传公证。
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD="${SCRIPT_DIR}/build/preview"
DATA="${ROOT}/data/generated"
ARGS=()
case "${1:-}" in
  '') RUN=true ;;
  --build-only) RUN=false ;;
  --smoke-test) RUN=true; ARGS=(--smoke-test) ;;
  *) echo '用法：dev-preview.sh [--build-only|--smoke-test]' >&2; exit 2 ;;
esac
for name in wubi86-core.tsv pinyin-chars.tsv pinyin-core.tsv; do
  [ -f "${DATA}/${name}" ] || { echo "缺少 ${DATA}/${name}，请按 README 生成真实数据。" >&2; exit 1; }
done
APP="${BUILD}/LampyrisPreview.app"
BIN="${APP}/Contents/MacOS/LampyrisPreview"
mkdir -p "${BUILD}/module-cache" "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cat > "${APP}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>cn.jokerhub.lampyris.debugpreview</string>
<key>CFBundleExecutable</key><string>LampyrisPreview</string>
<key>CFBundleName</key><string>LampyrisPreview</string>
<key>CFBundleIconFile</key><string>Lampyris.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
cp "${ROOT}/assets/icons/yinghuo-official-app.icns" "${APP}/Contents/Resources/Lampyris.icns"
ln -sfn "${DATA}" "${APP}/Contents/Resources/data"
export SWIFT_MODULECACHE_PATH="${BUILD}/module-cache"
export CLANG_MODULE_CACHE_PATH="${BUILD}/module-cache"
(cd "${ROOT}" && cargo build -p ime-ffi)
swiftc -g -Onone -module-name LampyrisPreview \
  -I "${ROOT}/crates/ime-ffi/include" \
  "${SCRIPT_DIR}/Preview/main.swift" \
  "${SCRIPT_DIR}/Sources/ImeSession.swift" \
  "${SCRIPT_DIR}/Sources/CandidateWindow.swift" \
  "${SCRIPT_DIR}/Sources/Config.swift" \
  "${SCRIPT_DIR}/Sources/Settings.swift" \
  "${SCRIPT_DIR}/Sources/Feedback.swift" \
  "${SCRIPT_DIR}/Sources/UserDictionary.swift" \
  "${SCRIPT_DIR}/Sources/Lookup.swift" \
  "${ROOT}/target/debug/libime_ffi.a" \
  -framework AppKit -o "${BIN}"
echo "调试窗口构建完成：${BIN}"
if ${RUN}; then exec "${BIN}" ${ARGS[@]+"${ARGS[@]}"} "${DATA}"; fi
