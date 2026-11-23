#!/usr/bin/env bash
# 把 DMG 的两个载荷（输入法本体 + 更新程序）装进安装器 bundle（ADR-391）。
#
# 为什么：DMG 顶层直接摆 Lampyris.app 时，用户只会去双击它——而它是
# LSBackgroundOnly + LSUIElement 的背景程序，双击本来就没有窗口，于是被当成"装坏了"。
# 现在 DMG 顶层只留「安装萤火虫」「卸载萤火虫」「安装与卸载说明.txt」，载荷放进
#   安装萤火虫.app/Contents/Resources/Payload/{Lampyris.app,LampyrisUpdateCheck.app}
# 仍然可审计：Finder「显示包内容」能看到同一份已签名/公证的 app。
#
# ⚠️ 必须在**签名安装器之前**执行：签名会封印 bundle 内的所有文件，签名后再塞载荷
# 会让安装器自己的签名失效（Gatekeeper 会在干净机器上直接拒绝启动）。
set -euo pipefail

INSTALLER=""
APP=""
UPDATER=""
OUT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --installer) [ "$#" -ge 2 ] || exit 2; INSTALLER="$2"; shift 2 ;;
    --app) [ "$#" -ge 2 ] || exit 2; APP="$2"; shift 2 ;;
    --updater) [ "$#" -ge 2 ] || exit 2; UPDATER="$2"; shift 2 ;;
    --out) [ "$#" -ge 2 ] || exit 2; OUT="$2"; shift 2 ;;
    *) echo "用法：$0 --installer <安装萤火虫.app> --app <Lampyris.app> --updater <LampyrisUpdateCheck.app> --out <安装萤火虫.app>" >&2; exit 2 ;;
  esac
done
[ -d "$INSTALLER" ] && [ ! -L "$INSTALLER" ] || { echo "安装器 app 不存在或为符号链接" >&2; exit 1; }
[ -d "$APP" ] && [ ! -L "$APP" ] || { echo "输入法 app 不存在或为符号链接" >&2; exit 1; }
[ -d "$UPDATER" ] && [ ! -L "$UPDATER" ] || { echo "更新程序 app 不存在或为符号链接（ADR-295 要求随包装载）" >&2; exit 1; }
[ -n "$OUT" ] || { echo "缺少 --out" >&2; exit 1; }
[ "$OUT" != "$INSTALLER" ] || { echo "--out 不能覆盖输入的安装器 app" >&2; exit 1; }

bundle_id() { /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist" 2>/dev/null || true; }
[ "$(bundle_id "$APP")" = cn.jokerhub.inputmethod.Lampyris ] || { echo "输入法标识不符" >&2; exit 1; }
[ "$(bundle_id "$UPDATER")" = cn.jokerhub.Lampyris.WebsiteUpdateCheck ] || { echo "更新程序标识不符" >&2; exit 1; }

PAYLOAD="$OUT/Contents/Resources/Payload"
rm -rf "$OUT"
ditto "$INSTALLER" "$OUT"
mkdir -p "$PAYLOAD"
ditto "$APP" "$PAYLOAD/Lampyris.app"
ditto "$UPDATER" "$PAYLOAD/LampyrisUpdateCheck.app"

# ditto 中途失败会留下半个载荷；读回一次再交付。
[ "$(bundle_id "$PAYLOAD/Lampyris.app")" = cn.jokerhub.inputmethod.Lampyris ] || {
  echo "载荷里的输入法不完整" >&2; exit 1; }
[ "$(bundle_id "$PAYLOAD/LampyrisUpdateCheck.app")" = cn.jokerhub.Lampyris.WebsiteUpdateCheck ] || {
  echo "载荷里的更新程序不完整" >&2; exit 1; }
[ -x "$PAYLOAD/Lampyris.app/Contents/MacOS/Lampyris" ] || { echo "载荷缺少可执行的输入法程序" >&2; exit 1; }
echo "$OUT"
