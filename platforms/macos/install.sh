#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="${SCRIPT_DIR}/build/Yinghuo.app"
DOMAIN="${HOME}/Library/Input Methods"
DRY=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --app) [ "$#" -ge 2 ] || exit 2; APP="$2"; shift 2 ;;
    --system) DOMAIN='/Library/Input Methods'; shift ;;
    --dry-run) DRY=true; shift ;;
    *) echo "用法：$0 [--app <Yinghuo.app>] [--system] [--dry-run]" >&2; exit 2 ;;
  esac
done
[ -d "${APP}" ] && [ ! -L "${APP}" ] || { echo "输入法 bundle 不存在或为符号链接" >&2; exit 1; }
APP="$(cd "$(dirname "${APP}")" && pwd)/$(basename "${APP}")"
IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "${APP}/Contents/Info.plist")"
[ "${IDENTIFIER}" = org.yinghuo.inputmethod.Yinghuo ] || { echo "输入法标识不符" >&2; exit 1; }
EXECUTABLE="${APP}/Contents/MacOS/Yinghuo"
[ -f "${EXECUTABLE}" ] && [ ! -L "${EXECUTABLE}" ] && [ -x "${EXECUTABLE}" ] || {
  echo "输入法程序缺少执行权限或不是普通文件；请用 Finder 或 ditto 重新解压原始发行 ZIP" >&2; exit 1
}
codesign --verify --strict "${APP}"
DETAILS="$(codesign -dv --verbose=4 "${APP}" 2>&1)"
[[ "${DETAILS}" == *"Authority=Developer ID Application:"* ]] || { echo "需要 Developer ID 签名的正式候选；ad-hoc 构建不可安装" >&2; exit 1; }
[[ "${DETAILS}" == *"runtime"* ]] || { echo "缺少 hardened runtime" >&2; exit 1; }
xcrun stapler validate "${APP}"
spctl --assess --type execute --verbose=2 "${APP}"
DEST="${DOMAIN}/Yinghuo.app"
[ ! -L "${DOMAIN}" ] && [ ! -L "${DEST}" ] || { echo "拒绝通过符号链接安装" >&2; exit 1; }
if [ -e "${DEST}" ]; then
  if [ -x "${DEST}/Contents/MacOS/Yinghuo" ] && [ ! -L "${DEST}/Contents/MacOS/Yinghuo" ] && diff -qr "${APP}" "${DEST}" >/dev/null; then echo "已安装相同版本"; exit 0; fi
  echo "已有不同版本，请先切换输入源并卸载备份" >&2; exit 1
fi
if ${DRY}; then echo "预检通过；将安装到 ${DEST}"; exit 0; fi
if [ "${DOMAIN}" = '/Library/Input Methods' ] && [ "$(id -u)" != 0 ]; then
  echo "系统域安装需要管理员运行；当前未写入" >&2; exit 1
fi
mkdir -p "${DOMAIN}"
# A hidden staging bundle cannot be discovered as an input method.
STAGE="$(mktemp -d "${DOMAIN}/.yinghuo-install.XXXXXX")"
trap 'rm -rf "${STAGE}"' EXIT
ditto "${APP}" "${STAGE}/Yinghuo.app"
[ -x "${STAGE}/Yinghuo.app/Contents/MacOS/Yinghuo" ] || { echo "安装副本缺少执行权限，未安装" >&2; exit 1; }
codesign --verify --strict "${STAGE}/Yinghuo.app"
mv -n "${STAGE}/Yinghuo.app" "${DEST}"
[ ! -e "${STAGE}/Yinghuo.app" ] || { echo "目标安装路径已被占用，未覆盖" >&2; exit 1; }
echo "安装完成。请注销/重新登录，再在系统设置 → 键盘 → 文字输入添加萤火虫。"
