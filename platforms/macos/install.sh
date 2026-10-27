#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="${SCRIPT_DIR}/build/Lampyris.app"
DOMAIN="${HOME}/Library/Input Methods"
DRY=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --app) [ "$#" -ge 2 ] || exit 2; APP="$2"; shift 2 ;;
    --system) DOMAIN='/Library/Input Methods'; shift ;;
    --dry-run) DRY=true; shift ;;
    *) echo "用法：$0 [--app <Lampyris.app>] [--system] [--dry-run]" >&2; exit 2 ;;
  esac
done
[ -d "${APP}" ] && [ ! -L "${APP}" ] || { echo "输入法 bundle 不存在或为符号链接" >&2; exit 1; }
APP="$(cd "$(dirname "${APP}")" && pwd)/$(basename "${APP}")"
IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "${APP}/Contents/Info.plist")"
[ "${IDENTIFIER}" = cn.jokerhub.inputmethod.Lampyris ] || { echo "输入法标识不符" >&2; exit 1; }
EXECUTABLE="${APP}/Contents/MacOS/Lampyris"
[ -f "${EXECUTABLE}" ] && [ ! -L "${EXECUTABLE}" ] && [ -x "${EXECUTABLE}" ] || {
  echo "输入法程序缺少执行权限或不是普通文件；请用 Finder 或 ditto 重新解压原始发行 ZIP" >&2; exit 1
}
codesign --verify --strict "${APP}"
DETAILS="$(codesign -dv --verbose=4 "${APP}" 2>&1)"
[[ "${DETAILS}" == *"Authority=Developer ID Application:"* ]] || { echo "需要 Developer ID 签名的正式候选；ad-hoc 构建不可安装" >&2; exit 1; }
[[ "${DETAILS}" == *"runtime"* ]] || { echo "缺少 hardened runtime" >&2; exit 1; }
xcrun stapler validate "${APP}"
spctl --assess --type execute --verbose=2 "${APP}"
DEST="${DOMAIN}/Lampyris.app"
[ ! -L "${DOMAIN}" ] && [ ! -L "${DEST}" ] || { echo "拒绝通过符号链接安装" >&2; exit 1; }
if [ -e "${DEST}" ]; then
  if [ -x "${DEST}/Contents/MacOS/Lampyris" ] && [ ! -L "${DEST}/Contents/MacOS/Lampyris" ] && diff -qr "${APP}" "${DEST}" >/dev/null; then echo "已安装相同版本"; exit 0; fi
  # ADR-295：与 DMG 安装器/更新器同一语义——允许覆盖，先备份，失败回滚。
  if pgrep -x Lampyris >/dev/null; then
    echo "宿主仍在运行；请切到 ABC、注销后再试，或用更新程序升级（不热替换）" >&2
    exit 1
  fi
fi
if ${DRY}; then
  if [ -e "${DEST}" ]; then echo "预检通过；将把现有版本备份后覆盖安装到 ${DEST}"; else echo "预检通过；将安装到 ${DEST}"; fi
  if [ -d "${SCRIPT_DIR}/../LampyrisUpdateCheck.app" ]; then
    echo "预检通过；包内自带更新程序，将同时安装到 ${HOME}/Applications/LampyrisUpdateCheck.app"
  fi
  exit 0
fi
if [ "${DOMAIN}" = '/Library/Input Methods' ] && [ "$(id -u)" != 0 ]; then
  echo "系统域安装需要管理员运行；当前未写入" >&2; exit 1
fi
mkdir -p "${DOMAIN}"
# A hidden staging bundle cannot be discovered as an input method.
STAGE="$(mktemp -d "${DOMAIN}/.lampyris-install.XXXXXX")"
BACKUP=""
trap 'rm -rf "${STAGE}"' EXIT
ditto "${APP}" "${STAGE}/Lampyris.app"
[ -x "${STAGE}/Lampyris.app/Contents/MacOS/Lampyris" ] || { echo "安装副本缺少执行权限，未安装" >&2; exit 1; }
codesign --verify --strict "${STAGE}/Lampyris.app"
if [ -e "${DEST}" ]; then
  if [ "${DOMAIN}" = '/Library/Input Methods' ]; then BACKUP_APP_SUPPORT='/Library/Application Support/Lampyris';
  else BACKUP_APP_SUPPORT="${HOME}/Library/Application Support/Lampyris"; fi
  BACKUP_ROOT="${BACKUP_APP_SUPPORT}/updates/install-backup-$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "${BACKUP_ROOT}" || { echo "无法创建备份目录 ${BACKUP_ROOT}" >&2; exit 1; }
  BACKUP="${BACKUP_ROOT}/Lampyris.app"
  mv "${DEST}" "${BACKUP}" || { echo "备份现有版本失败；未覆盖" >&2; exit 1; }
  echo "旧版本已备份：${BACKUP}"
fi
if ! mv -n "${STAGE}/Lampyris.app" "${DEST}"; then
  [ -n "${BACKUP}" ] && mv "${BACKUP}" "${DEST}"
  echo "写入输入法目录失败，已回滚" >&2; exit 1
fi
[ ! -e "${STAGE}/Lampyris.app" ] || {
  [ -n "${BACKUP}" ] && mv "${BACKUP}" "${DEST}"
  echo "目标安装路径已被占用，未覆盖" >&2; exit 1; }
if ! codesign --verify --strict "${DEST}"; then
  rm -rf "${DEST}"
  [ -n "${BACKUP}" ] && mv "${BACKUP}" "${DEST}"
  echo "安装后签名校验失败，已回滚" >&2; exit 1
fi
# ADR-295：包内自带更新程序时一并安装（与 DMG 安装器、更新器同一套校验与备份语义）。
install_updater() {
  local source="${SCRIPT_DIR}/../LampyrisUpdateCheck.app"
  local apps="${HOME}/Applications"
  local destination="${apps}/LampyrisUpdateCheck.app"
  local legacy="${apps}/Lampyris Update.app"
  if [ "${DOMAIN}" = '/Library/Input Methods' ]; then
    echo "系统域安装不改动个人 ~/Applications；需要时以普通用户把 LampyrisUpdateCheck.app 放进自己的 ~/Applications。"
    return 0
  fi
  if [ ! -d "${source}" ] || [ -L "${source}" ]; then
    echo "本包未自带更新程序；可从同一 Release 下载 LampyrisUpdateCheck-<版本>.zip，解压后把 LampyrisUpdateCheck.app 放进 ~/Applications。"
    return 0
  fi
  [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${source}/Contents/Info.plist")" = cn.jokerhub.Lampyris.WebsiteUpdateCheck ] || {
    echo "更新程序标识不符，未安装更新程序" >&2; exit 1; }
  codesign --verify --strict "${source}"
  local details
  details="$(codesign -dv --verbose=4 "${source}" 2>&1)"
  [[ "${details}" == *"Authority=Developer ID Application:"* ]] || { echo "更新程序需要 Developer ID 签名" >&2; exit 1; }
  [[ "${details}" == *"runtime"* ]] || { echo "更新程序缺少 hardened runtime" >&2; exit 1; }
  xcrun stapler validate "${source}"
  spctl --assess --type execute --verbose=2 "${source}"
  [ ! -L "${apps}" ] || { echo "~/Applications 是符号链接，已停止安装更新程序" >&2; exit 1; }
  mkdir -p "${apps}"
  if [ -e "${destination}" ] && diff -qr "${source}" "${destination}" >/dev/null 2>&1; then
    echo "更新程序已是最新；未改动"
    return 0
  fi
  if [ "${DOMAIN}" = '/Library/Input Methods' ]; then BACKUP_UPDATER_ROOT='/Library/Application Support/Lampyris/updates';
  else BACKUP_UPDATER_ROOT="${HOME}/Library/Application Support/Lampyris/updates"; fi
  BACKUP_UPDATER_ROOT="${BACKUP_UPDATER_ROOT}/install-backup-$(date -u +%Y%m%dT%H%M%SZ)"
  if pgrep -x LampyrisUpdateCheck >/dev/null; then pkill -x LampyrisUpdateCheck || true; sleep 1; fi
  local staging
  staging="$(mktemp -d "${apps}/.lampyris-updater.XXXXXX")"
  ditto "${source}" "${staging}/LampyrisUpdateCheck.app"
  codesign --verify --strict "${staging}/LampyrisUpdateCheck.app"
  local previous=""
  if [ -e "${destination}" ]; then
    mkdir -p "${BACKUP_UPDATER_ROOT}"
    mv "${destination}" "${BACKUP_UPDATER_ROOT}/LampyrisUpdateCheck.app"
    previous="${BACKUP_UPDATER_ROOT}/LampyrisUpdateCheck.app"
  fi
  if [ -e "${legacy}" ]; then
    mkdir -p "${BACKUP_UPDATER_ROOT}"
    mv "${legacy}" "${BACKUP_UPDATER_ROOT}/Lampyris Update.app"
    echo "旧版更新程序已迁移到 ${BACKUP_UPDATER_ROOT}"
  fi
  if ! mv "${staging}/LampyrisUpdateCheck.app" "${destination}" || ! codesign --verify --strict "${destination}"; then
    rm -rf "${destination}"
    [ -n "${previous}" ] && mv "${previous}" "${destination}"
    rm -rf "${staging}"
    echo "安装更新程序失败，已回滚" >&2; exit 1
  fi
  rm -rf "${staging}"
  echo "更新程序已安装：${destination}"
}
install_updater

HELPER="${DEST}/Contents/Helpers/LampyrisTIS"
# 不能只看 `enable` 的返回值：macOS 13 上 `TISEnableInputSource` 会返回 0 但源并未进入启用列表
# （报告201/207 两次实测），所以回读一次再决定措辞。
READBACK="${SCRIPT_DIR}/tools/input-source-enabled.sh"
if [ -x "${HELPER}" ]; then
  "${HELPER}" register "${DEST}" >/dev/null 2>&1 || true
  "${HELPER}" enable "${IDENTIFIER}" >/dev/null 2>&1 || true
  if [ ! -x "${READBACK}" ]; then
    echo "安装完成。请用 ⌃Space 或输入法菜单确认「萤火虫」；若菜单里还没有，重新登录一次或手动添加。"
  elif "${READBACK}" "${HELPER}" "${IDENTIFIER}"; then
    echo "安装完成，已注册到输入源。"
    echo "现在用 ⌃Space 或输入法菜单选中「萤火虫」即可；若菜单里还没出现，重启登录一次。"
  else
    echo "安装完成，但系统没有接受自动注册（macOS 13 上的已知行为）。"
    echo "请在系统设置 → 键盘 → 文字输入 → ＋ → 中文（简体）添加「萤火虫」。"
  fi
else
  echo "安装完成。请注销/重新登录，再在系统设置 → 键盘 → 文字输入添加萤火虫。"
fi
