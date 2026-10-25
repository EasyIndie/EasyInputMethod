#!/bin/sh
# 生成测试用最小 .app（内含 imetype），供 imetype/keytopid 组合使用（报告188/191）。
# 输出固定为 /tmp/lampyris-imetype.app，可重复执行；不进入产品、不写系统目录。
set -eu
PROBE="$(cd "$(dirname "$0")" && pwd)"
APP="${APP:-/tmp/lampyris-imetype.app}"
BIN="$PROBE/bin/imetype"
[ -x "$BIN" ] || { echo "缺少 ${BIN}，先跑 make macos-probe-build" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/imetype"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>imetype</string>
<key>CFBundleIdentifier</key><string>cn.jokerhub.probe.imetype</string>
<key>CFBundleName</key><string>imetype</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.0.1</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "$APP"
