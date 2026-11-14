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
# 学习区结构化提示（ADR-311）：预览也需要，便于看真实渲染
[ -f "${DATA}/B0-runtime.tsv" ] && cp "${DATA}/B0-runtime.tsv" "${APP}/Contents/Resources/B0-runtime.tsv"
# 练习的词组题库直接读 Resources 下的码表。
[ -f "${DATA}/wubi86-core.tsv" ] && cp "${DATA}/wubi86-core.tsv" "${APP}/Contents/Resources/wubi86-core.tsv"
# 符号面板与正式包同源读取 Resources 下的 TSV，预览也要能打开。
[ -f "${ROOT}/data/symbols.tsv" ] && cp "${ROOT}/data/symbols.tsv" "${APP}/Contents/Resources/symbols.tsv"
[ -f "${DATA}/emoji.tsv" ] && cp "${DATA}/emoji.tsv" "${APP}/Contents/Resources/emoji.tsv"
[ -f "${ROOT}/data/sources/wubi86-level3-codes.tsv" ] && cp "${ROOT}/data/sources/wubi86-level3-codes.tsv" "${APP}/Contents/Resources/wubi86-level3-codes.tsv"
ln -sfn "${DATA}" "${APP}/Contents/Resources/data"
export SWIFT_MODULECACHE_PATH="${BUILD}/module-cache"
export CLANG_MODULE_CACHE_PATH="${BUILD}/module-cache"
(cd "${ROOT}" && cargo build -p ime-ffi)
swiftc -g -Onone -warnings-as-errors -module-name LampyrisPreview \
  -I "${ROOT}/crates/ime-ffi/include" \
  "${SCRIPT_DIR}/Preview/main.swift" \
  "${SCRIPT_DIR}/Preview/InputMenuPreview.swift" \
  "${SCRIPT_DIR}/Sources/InputMenu.swift" \
  "${SCRIPT_DIR}/Sources/ImeSession.swift" \
  "${SCRIPT_DIR}/Sources/CandidateWindow.swift" \
  "${SCRIPT_DIR}/Sources/CaretPlacement.swift" \
  "${SCRIPT_DIR}/Sources/Config.swift" \
  "${SCRIPT_DIR}/Sources/StateHUD.swift" \
  "${SCRIPT_DIR}/Sources/Settings.swift" \
  "${SCRIPT_DIR}/Sources/Feedback.swift" \
  "${SCRIPT_DIR}/Sources/InfoWindow.swift" \
  "${SCRIPT_DIR}/Sources/UserDictionary.swift" \
  "${SCRIPT_DIR}/Sources/Lookup.swift" \
  "${SCRIPT_DIR}/Sources/LearningHints.swift" \
  "${SCRIPT_DIR}/Sources/Practice.swift" \
  "${SCRIPT_DIR}/Sources/PracticeWindow.swift" \
  "${SCRIPT_DIR}/Sources/PassageBank.swift" \
  "${SCRIPT_DIR}/Sources/PassageWindow.swift" \
  "${SCRIPT_DIR}/Sources/PracticeAnswerView.swift" \
  "${SCRIPT_DIR}/Sources/PracticeExplanationView.swift" \
  "${SCRIPT_DIR}/Sources/Onboarding.swift" \
  "${SCRIPT_DIR}/Sources/OnboardingWindow.swift" \
  "${SCRIPT_DIR}/Sources/SymbolCatalog.swift" \
  "${SCRIPT_DIR}/Sources/SymbolPickerWindow.swift" \
  "${ROOT}/modules/keymap/Sources/KeyboardMapView.swift" \
  "${ROOT}/modules/keymap/Sources/KeymapPanelView.swift" \
  "${ROOT}/modules/keymap/Sources/KeyRootLayout.swift" \
  "${SCRIPT_DIR}/Sources/WubiHints.generated.swift" \
  "${ROOT}/target/debug/libime_ffi.a" \
  -framework AppKit -o "${BIN}"
echo "调试窗口构建完成：${BIN}"
if ${RUN}; then exec "${BIN}" ${ARGS[@]+"${ARGS[@]}"} "${DATA}"; fi
