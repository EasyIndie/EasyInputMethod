#!/usr/bin/env bash
# Build the user-facing DMG around an already signed app and installer app.
set -euo pipefail
APP=""
INSTALLER=""
UNINSTALLER=""
UPDATER=""
OUT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --app) [ "$#" -ge 2 ] || exit 2; APP="$2"; shift 2 ;;
    --installer) [ "$#" -ge 2 ] || exit 2; INSTALLER="$2"; shift 2 ;;
    --uninstaller) [ "$#" -ge 2 ] || exit 2; UNINSTALLER="$2"; shift 2 ;;
    --updater) [ "$#" -ge 2 ] || exit 2; UPDATER="$2"; shift 2 ;;
    --out) [ "$#" -ge 2 ] || exit 2; OUT="$2"; shift 2 ;;
    *) echo "用法：$0 --app <Lampyris.app> --installer <安装萤火虫.app> --uninstaller <卸载萤火虫.app> --updater <LampyrisUpdateCheck.app> --out <x.dmg>" >&2; exit 2 ;;
  esac
done
[ -d "$APP" ] && [ ! -L "$APP" ] || { echo "输入法 app 不存在或为符号链接" >&2; exit 1; }
[ -d "$INSTALLER" ] && [ ! -L "$INSTALLER" ] || { echo "安装器 app 不存在或为符号链接" >&2; exit 1; }
[ -d "$UNINSTALLER" ] && [ ! -L "$UNINSTALLER" ] || { echo "卸载器 app 不存在或为符号链接" >&2; exit 1; }
# ADR-295：更新程序随 DMG 分发，安装器会把它装到 ~/Applications；缺它就不出包。
[ -d "$UPDATER" ] && [ ! -L "$UPDATER" ] || { echo "更新程序 app 不存在或为符号链接（ADR-295 要求随 DMG 分发）" >&2; exit 1; }
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$UPDATER/Contents/Info.plist")" = cn.jokerhub.Lampyris.WebsiteUpdateCheck ] || {
  echo "更新程序标识不符" >&2; exit 1; }
[ -n "$OUT" ] || { echo "缺少 --out" >&2; exit 1; }
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/lampyris-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Lampyris.app"
ditto "$INSTALLER" "$STAGE/安装萤火虫.app"
ditto "$UNINSTALLER" "$STAGE/卸载萤火虫.app"
ditto "$UPDATER" "$STAGE/LampyrisUpdateCheck.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
cat > "$STAGE/安装与卸载说明.txt" <<TEXT
萤火虫 Lampyris ${VERSION}（构建 ${BUILD}）
默认离线的中文输入法 · 五笔优先，拼音兜底 · GPL-3.0-or-later
系统要求：macOS 13 Ventura 或更高；universal（Apple Silicon / Intel）

────────────────────────────────
安装
────────────────────────────────
1. 双击「安装萤火虫」。
2. 点「安装」。不需要 sudo，也不会联网。
   安装器会校验签名，把应用写入当前用户的输入法目录；
   如已有旧版，会先备份，失败会自动回滚。
   同时安装「萤火虫更新」更新程序（~/Applications/LampyrisUpdateCheck.app），
   装完后输入法菜单的「检查更新…」直接打开它的窗口。
3. 按 ⌃Space，或在输入法菜单中选择「萤火虫」。
   第三方输入源需要你手动选择一次，安装器不能代为切换。

安装位置：
  ~/Library/Input Methods/Lampyris.app
  ~/Applications/LampyrisUpdateCheck.app（更新程序；不随系统启动，不会后台检查）

────────────────────────────────
更新
────────────────────────────────
菜单「检查更新…」或 ⌥G → 更新窗口 → 检查 → 下载 → 验签 → 确认安装。
下载包由项目 Ed25519 私钥签名，公钥固定在更新程序里；
换更新源（设置 → 更新）不会降低验签强度。
更新只替换输入法本体，不会更新更新程序自身。

────────────────────────────────
卸载
────────────────────────────────
双击「卸载萤火虫」，然后选择一种方式：

A. 保留配置与词库（推荐用于重装）
   移除：输入法应用、更新程序、更新备份、缓存、偏好设置、诊断日志。
   保留：
     ~/Library/Application Support/Lampyris/config.toml
     ~/Library/Application Support/Lampyris/user-dictionary.tsv
   重新安装后可以继续使用原来的设置和个人词库。

B. 彻底清理全部数据
   额外移除配置、个人词库和整个数据目录；删除后无法恢复。
   适用于不再使用萤火虫，或要把机器交给别人。

两种方式都会：
  · 切回 ABC 并禁用萤火虫输入源；
  · 退出输入法宿主和更新程序；
  · 清理缓存、偏好设置、保存状态和诊断日志。

卸载完成后请注销并重新登录一次，让系统输入法菜单移除残留条目。

────────────────────────────────
数据位置
────────────────────────────────
配置与词库：
  ~/Library/Application Support/Lampyris/
更新备份与安装回执：
  ~/Library/Application Support/Lampyris/updates/
更新程序：
  ~/Applications/LampyrisUpdateCheck.app

保留用户数据时，只保留 config.toml 和 user-dictionary.tsv；
更新备份、安装回执、旧卸载备份都会删除。

────────────────────────────────
常见问题
────────────────────────────────
· 输入法菜单里没有「萤火虫」：注销并重新登录，再到
  「系统设置 → 键盘 → 文字输入」添加。
· 提示应用已损坏：请重新下载本 DMG，不要用第三方解压工具修改内容。
· macOS 阻止打开：本安装包已签名并公证；如仍被拦截，请在
  「系统设置 → 隐私与安全性」中允许本次打开。
· 想验证下载：对照 Release 页面的 .sha256 文件。

隐私：输入法与更新程序不会收集输入内容；输入法核心零网络、零遥测。
源码与许可：GPL-3.0-or-later，源码与二进制在同一 Release 页面发布。
TEXT
mkdir -p "$(dirname "$OUT")"
hdiutil create -volname "萤火虫" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov -quiet "$OUT"
[ -s "$OUT" ] || { echo "DMG 生成失败" >&2; exit 1; }
echo "$OUT"
