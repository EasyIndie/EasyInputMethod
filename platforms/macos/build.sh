#!/usr/bin/env bash
# 萤火虫输入法 · macOS 宿主构建脚本
#
# 纯命令行构建（本机无 Xcode 亦可）：
#   cargo 构建 ime-ffi staticlib → swiftc 编译 Swift 宿主 → 拼装 .app bundle。
#
# 用法：./platforms/macos/build.sh
#
# 产物：platforms/macos/build/萤火虫.app
#
# ⚠️ 必须是 .app：macOS 13 的 LaunchServices 无法扫描 .inputmethod（实测 -10811）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
APP_NAME="萤火虫"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
EXECUTABLE="Yinghuo"

LIB="${ROOT}/target/release/libime_ffi.a"
INCLUDE_DIR="${ROOT}/crates/ime-ffi/include"
GENERATED="${ROOT}/data/generated"

echo "▶ 1/5 构建 ime-ffi（staticlib）"
( cd "${ROOT}" && cargo build --release -p ime-ffi )
if [ ! -f "${LIB}" ]; then
  echo "❌ 找不到 staticlib：${LIB}"
  exit 1
fi

echo "▶ 2/5 重置 bundle 目录"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${SCRIPT_DIR}/Info.plist" "${APP_DIR}/Contents/Info.plist"
# PkgInfo：IMK/LaunchServices 期望的 8 字节类型/签名
printf 'APPL????' > "${APP_DIR}/Contents/PkgInfo"
# 图标 + 本地化显示名
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
copy_data "${GENERATED}/pinyin-words.tsv" "pinyin-words.tsv"
if [ ! -f "${GENERATED}/pinyin-words.tsv" ]; then
  echo "      （可由 data/sources/fetch-*.sh + 'cargo run -p ime-pinyin --example generate' 复现）"
fi

echo "▶ 4/5 编译 Swift 宿主（swiftc）"
swiftc -O \
  -module-name Yinghuo \
  -I "${INCLUDE_DIR}" \
  "${SCRIPT_DIR}"/Sources/*.swift \
  "${LIB}" \
  -framework AppKit \
  -framework InputMethodKit \
  -framework CoreFoundation \
  -o "${APP_DIR}/Contents/MacOS/${EXECUTABLE}"

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
echo "   装载：cp -R \"${APP_DIR}\" ~/Library/Input\\ Methods/ 然后【注销/重登】（必须）"
echo "   然后在 系统设置 → 键盘 → 文字输入 → 输入法 添加「萤火虫」。详见 platforms/macos/README.md。"
