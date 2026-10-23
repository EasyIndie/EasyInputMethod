#!/usr/bin/env bash
# Build the user-facing DMG around an already signed app and installer app.
set -euo pipefail
APP=""
INSTALLER=""
OUT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --app) [ "$#" -ge 2 ] || exit 2; APP="$2"; shift 2 ;;
    --installer) [ "$#" -ge 2 ] || exit 2; INSTALLER="$2"; shift 2 ;;
    --out) [ "$#" -ge 2 ] || exit 2; OUT="$2"; shift 2 ;;
    *) echo "用法：$0 --app <Lampyris.app> --installer <安装萤火虫.app> --out <x.dmg>" >&2; exit 2 ;;
  esac
done
[ -d "$APP" ] && [ ! -L "$APP" ] || { echo "输入法 app 不存在或为符号链接" >&2; exit 1; }
[ -d "$INSTALLER" ] && [ ! -L "$INSTALLER" ] || { echo "安装器 app 不存在或为符号链接" >&2; exit 1; }
[ -n "$OUT" ] || { echo "缺少 --out" >&2; exit 1; }
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/lampyris-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Lampyris.app"
ditto "$INSTALLER" "$STAGE/安装萤火虫.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
cat > "$STAGE/安装说明.txt" <<TEXT
萤火虫 ${VERSION}（构建 ${BUILD}）

1. 双击「安装萤火虫」。
2. 在窗口中点「安装」。安装器会写入当前用户目录并保留配置与词库。
3. 按 ⌃Space，或在输入法菜单中选择「萤火虫」。

如果安装后菜单里暂时没有出现，注销并重新登录一次即可。
TEXT
mkdir -p "$(dirname "$OUT")"
hdiutil create -volname "萤火虫" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov -quiet "$OUT"
[ -s "$OUT" ] || { echo "DMG 生成失败" >&2; exit 1; }
echo "$OUT"
