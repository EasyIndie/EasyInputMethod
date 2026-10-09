#!/usr/bin/env bash
# 萤火虫输入法 · macOS 宿主构建脚本
#
# 纯命令行构建（本机无 Xcode 亦可）：
#   cargo 构建 ime-ffi staticlib → swiftc 编译 Swift 宿主 → 拼装 .app bundle。
#
# 用法：./platforms/macos/build.sh
#
# 产物：platforms/macos/build/Yinghuo.app
#
# ⚠️ 必须是 .app：macOS 13 的 LaunchServices 无法扫描 .inputmethod（实测 -10811）。
# ⚠️ bundle 名与 CFBundleName 用 ASCII（Yinghuo）；中文显示名由 InfoPlist.strings 提供。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
APP_NAME="Yinghuo"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
EXECUTABLE="Yinghuo"

LIB="${ROOT}/target/release/libime_ffi.a"
INCLUDE_DIR="${ROOT}/crates/ime-ffi/include"
GENERATED="${ROOT}/data/generated"
STRICT=false
case "${1:-}" in
  "") ;;
  --strict) STRICT=true ;;
  *) echo "用法：$0 [--strict]" >&2; exit 2 ;;
esac
if ${STRICT}; then
  for name in wubi86-core.tsv pinyin-chars.tsv pinyin-core.tsv; do
    [ -s "${GENERATED}/${name}" ] || { echo "发布构建缺少 ${name}" >&2; exit 1; }
  done
fi

echo "▶ 1/5 构建 ime-ffi（staticlib）"
( cd "${ROOT}" && CARGO_ENCODED_RUSTFLAGS="$(python3 "${ROOT}/tools/build-rust-flags.py" "${ROOT}")" cargo build --locked --release -p ime-ffi )
if [ ! -f "${LIB}" ]; then
  echo "❌ 找不到 staticlib：${LIB}"
  exit 1
fi

echo "▶ 2/5 重置 bundle 目录"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${SCRIPT_DIR}/Info.plist" "${APP_DIR}/Contents/Info.plist"
REPO_ROOT="$(git -C "${ROOT}" rev-parse --show-toplevel 2>/dev/null || true)"
if [ "${REPO_ROOT}" = "${ROOT}" ]; then
  git -C "${ROOT}" rev-parse HEAD > "${APP_DIR}/Contents/Resources/SOURCE-COMMIT"
elif [ -s "${ROOT}/SOURCE-COMMIT" ]; then
  cp "${ROOT}/SOURCE-COMMIT" "${APP_DIR}/Contents/Resources/SOURCE-COMMIT"
else
  echo "无法确定对应源码提交" >&2; exit 1
fi
# PkgInfo：IMK/LaunchServices 期望的 8 字节类型/签名
printf 'APPL????' > "${APP_DIR}/Contents/PkgInfo"
# 图标 + 本地化显示名
cp "${ROOT}/assets/icons/yinghuo-official-app.icns" "${APP_DIR}/Contents/Resources/Yinghuo.icns"
cp "${SCRIPT_DIR}/Resources/"*.png "${APP_DIR}/Contents/Resources/"
for lproj in "${SCRIPT_DIR}/Resources/"*.lproj; do
  [ -d "${lproj}" ] || continue
  cp -R "${lproj}" "${APP_DIR}/Contents/Resources/"
done

echo "▶ 3/5 复制数据文件（缺失的给出复现提示）"
copy_data() {
  local src="$1" name="$2"
  if [ -f "${src}" ]; then
    cp "${src}" "${APP_DIR}/Contents/Resources/${name}"
    printf '   ✅ %s\n' "${name}"
  else
    printf '   ⚠️  缺少 %s（宿主将回退到样本/降级）\n' "${src}"
  fi
}
copy_data "${GENERATED}/wubi86-core.tsv" "wubi86-core.tsv"
copy_data "${GENERATED}/pinyin-chars.tsv" "pinyin-chars.tsv"
copy_data "${GENERATED}/pinyin-core.tsv" "pinyin-core.tsv"
if [ ! -f "${GENERATED}/pinyin-core.tsv" ]; then
  echo "      （可由 data/sources/fetch-*.sh + 'cargo run -p ime-pinyin --example generate' 复现）"
fi

echo "▶ 4/5 编译 Swift 宿主（swiftc）"
( cd "${ROOT}" && swiftc -O -whole-module-optimization \
  -target "$(uname -m)-apple-macosx13.0" \
  -Xlinker -oso_prefix -Xlinker "${ROOT}/" -Xlinker -reproducible -Xlinker -S \
  -file-prefix-map "${ROOT}=/yinghuo-src" \
  -module-name Yinghuo \
  -I "crates/ime-ffi/include" \
  platforms/macos/Sources/*.swift \
  target/release/libime_ffi.a \
  -framework AppKit \
  -framework InputMethodKit \
  -framework CoreFoundation \
  -o "${APP_DIR}/Contents/MacOS/${EXECUTABLE}" )

echo "▶ 5/5 校验 Info.plist + ad-hoc 签名"
plutil -lint "${APP_DIR}/Contents/Info.plist"
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "${APP_DIR}" >/dev/null
  echo "   ✅ ad-hoc 签名完成"
else
  echo "   ⚠️  未找到 codesign，跳过签名（装载时可能被 Gatekeeper 拦截）"
fi

echo
echo "✅ 构建完成：${APP_DIR}"
echo "   此 ad-hoc 构建仅供开发验证；日常运行 make macos-preview。"
echo "   分发签名/公证及可信安装流程见 packaging/README.md。"
