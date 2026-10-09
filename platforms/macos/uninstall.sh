#!/usr/bin/env bash
# Keep user config and dictionary; never kill unrelated processes.
set -euo pipefail
DOMAIN="${HOME}/Library/Input Methods"
BACKUP="${HOME}/Library/Application Support/Lampyris/uninstalled"
DRY=false
REMOVED=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --system) DOMAIN='/Library/Input Methods'; BACKUP='/Library/Application Support/Lampyris/uninstalled'; shift ;;
    --dry-run) DRY=true; shift ;;
    --input-source-removed) REMOVED=true; shift ;;
    *) echo "用法：$0 [--system] [--dry-run] [--input-source-removed]" >&2; exit 2 ;;
  esac
done
APP="${DOMAIN}/Lampyris.app"
[ -e "${APP}" ] || { echo "该安装域中没有萤火虫输入法"; exit 0; }
[ ! -L "${DOMAIN}" ] && [ ! -L "${APP}" ] || { echo "拒绝移动符号链接" >&2; exit 1; }
IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "${APP}/Contents/Info.plist")"
[ "${IDENTIFIER}" = cn.jokerhub.inputmethod.Lampyris ] || { echo "输入法标识不符" >&2; exit 1; }
if pgrep -x Lampyris >/dev/null; then echo "请切换为 ABC，在系统设置移除萤火虫，然后注销使宿主退出" >&2; exit 1; fi
if ${DRY}; then echo "将备份至 ${BACKUP}；保留配置与词库。先在系统设置移除输入源。"; exit 0; fi
${REMOVED} || { echo "先移除输入源，确认后传入 --input-source-removed" >&2; exit 1; }
if [ "${DOMAIN}" = '/Library/Input Methods' ] && [ "$(id -u)" != 0 ]; then echo "系统域卸载需要管理员运行" >&2; exit 1; fi
mkdir -p "${BACKUP}"
TARGET="$(mktemp -d "${BACKUP}/bundle.XXXXXX")"
mv "${APP}" "${TARGET}/Lampyris.app"
echo "已移出输入法目录，备份在 ${TARGET}；请注销/重新登录。配置与词库保留。"
