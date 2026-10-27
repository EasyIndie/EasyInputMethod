#!/usr/bin/env bash
# Keep user config and dictionary by default; never kill unrelated processes.
# --purge-data moves config.toml / user-dictionary.tsv aside too, so the next
# install starts from Schema defaults (fresh behaviour), without deleting them.
set -euo pipefail
DOMAIN="${HOME}/Library/Input Methods"
BACKUP="${HOME}/Library/Application Support/Lampyris/uninstalled"
APP_SUPPORT="${HOME}/Library/Application Support/Lampyris"
DRY=false
REMOVED=false
PURGE=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --system) DOMAIN='/Library/Input Methods'; BACKUP='/Library/Application Support/Lampyris/uninstalled'; APP_SUPPORT='/Library/Application Support/Lampyris'; shift ;;
    --dry-run) DRY=true; shift ;;
    --input-source-removed) REMOVED=true; shift ;;
    --purge-data) PURGE=true; shift ;;
    *) echo "用法：$0 [--system] [--dry-run] [--input-source-removed] [--purge-data]" >&2; exit 2 ;;
  esac
done
APP="${DOMAIN}/Lampyris.app"
[ -e "${APP}" ] || { echo "该安装域中没有萤火虫输入法"; exit 0; }
[ ! -L "${DOMAIN}" ] && [ ! -L "${APP}" ] || { echo "拒绝移动符号链接" >&2; exit 1; }
IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "${APP}/Contents/Info.plist")"
[ "${IDENTIFIER}" = cn.jokerhub.inputmethod.Lampyris ] || { echo "输入法标识不符" >&2; exit 1; }
if [ -L "${APP_SUPPORT}" ]; then echo "拒绝通过符号链接访问用户数据目录" >&2; exit 1; fi

DATA_FILES=()
if ${PURGE}; then
  for name in config.toml user-dictionary.tsv; do
    [ -e "${APP_SUPPORT}/${name}" ] || continue
    [ -L "${APP_SUPPORT}/${name}" ] && { echo "拒绝移动符号链接 ${name}" >&2; exit 1; }
    DATA_FILES+=("${name}")
  done
fi

# 预检只打印计划，不要求先退出宿主（切换前先看清会动什么）。
if ${DRY}; then
  echo "将把 ${APP} 移到 ${BACKUP}/bundle.XXXXXX/"
  echo "更新程序（~/Applications/LampyrisUpdateCheck.app，旧名 Lampyris Update.app）按 bundle id 一并移入备份"
  if ${PURGE}; then
    if [ "${#DATA_FILES[@]}" -eq 0 ]; then
      echo "用户数据目录里没有 config.toml / user-dictionary.tsv，无需清理"
    else
      echo "将把用户数据移到 ${BACKUP}/data.XXXXXX/：${DATA_FILES[*]}"
      echo "之后首次启动按 Schema 默认值全新开始（不删除，只是移出活动目录）"
    fi
  else
    echo "保留配置与词库；若要全新安装（以默认行为为起点），再加 --purge-data"
  fi
  echo "执行前：切换到 ABC，在「系统设置 → 键盘 → 文字输入」移除萤火虫，注销使宿主退出。"
  exit 0
fi

HELPER="${APP}/Contents/Helpers/LampyrisTIS"
AUTO_REMOVED=false
if [ -x "${HELPER}" ]; then
  "${HELPER}" switch-abc >/dev/null 2>&1 || true
  if "${HELPER}" disable "${IDENTIFIER}" >/dev/null 2>&1; then
    AUTO_REMOVED=true
    sleep 1
  fi
fi
if pgrep -x Lampyris >/dev/null; then echo "宿主仍在运行；请注销后重试，或手动移除输入源" >&2; exit 1; fi
if ! ${REMOVED}; then
  ${AUTO_REMOVED} || { echo "先移除输入源，确认后传入 --input-source-removed" >&2; exit 1; }
fi
if [ "${DOMAIN}" = '/Library/Input Methods' ] && [ "$(id -u)" != 0 ]; then echo "系统域卸载需要管理员运行" >&2; exit 1; fi
mkdir -p "${BACKUP}"
TARGET="$(mktemp -d "${BACKUP}/bundle.XXXXXX")"
mv "${APP}" "${TARGET}/Lampyris.app"
echo "已移出输入法目录，备份在 ${TARGET}"
# ADR-294/295：更新程序按 bundle id 清理（正式名与历史改名都算），同样移入备份而不是删除。
if pgrep -x LampyrisUpdateCheck >/dev/null; then
  pkill -x LampyrisUpdateCheck || true
  sleep 1
fi
for updater_dir in "${HOME}/Applications" /Applications; do
  [ -d "${updater_dir}" ] || continue
  for candidate in "${updater_dir}"/*.app; do
    [ -d "${candidate}" ] && [ ! -L "${candidate}" ] || continue
    candidate_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "${candidate}/Contents/Info.plist" 2>/dev/null || true)"
    [ "${candidate_id}" = cn.jokerhub.Lampyris.WebsiteUpdateCheck ] || continue
    mv "${candidate}" "${TARGET}/$(basename "${candidate}")"
    echo "更新程序已移入备份：${TARGET}/$(basename "${candidate}")"
  done
done
if ${PURGE}; then
  if [ "${#DATA_FILES[@]}" -eq 0 ]; then
    echo "用户数据目录里没有 config.toml / user-dictionary.tsv，无需清理"
  else
    DATA_DIR="$(mktemp -d "${BACKUP}/data.XXXXXX")"
    for name in "${DATA_FILES[@]}"; do
      mv "${APP_SUPPORT}/${name}" "${DATA_DIR}/${name}"
    done
    echo "用户数据已移到 ${DATA_DIR}；首次启动将按 Schema 默认值全新开始"
  fi
else
  echo "配置与词库保留"
fi
echo "请注销/重新登录，再安装新包并重新添加输入源。"
