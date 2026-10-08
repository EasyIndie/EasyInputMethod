#!/usr/bin/env bash
# 萤火虫输入法 · macOS 装载诊断（一次性收集所有关键信息）。
#
# 用法：./platforms/macos/tools/diagnose.sh [关键字，默认 yinghuo]
# 重启后运行本脚本，把输出整段贴回即可。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
KEY="${1:-yinghuo}"
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

hr() { printf '\n======== %s ========\n' "$1"; }

hr "1) 输入法目录内容"
echo "--- ~/Library/Input Methods ---"; ls -la ~/Library/"Input Methods"/ 2>/dev/null
echo "--- /Library/Input Methods ---"; ls -la "/Library/Input Methods/" 2>/dev/null

hr "2) 已安装 bundle 的签名"
for d in ~/Library/"Input Methods"/*.app "/Library/Input Methods"/*.app; do
  [ -d "$d" ] || continue
  printf '\n-- %s\n' "$d"
  codesign -dvv "$d" 2>&1 | grep -iE "Identifier|Signature|TeamIdentifier|Authority" | head
done

hr "3) 系统识别到的输入源（筛选：${KEY}）"
( cd "$ROOT" && ./platforms/macos/tools/list-input-sources.sh "$KEY" 2>/dev/null ) | tail -8

hr "4) 把第三方/苹果输入模式全列一遍（前 60 行）"
( cd "$ROOT" && ./platforms/macos/tools/list-input-sources.sh 2>/dev/null ) | grep -iE "已启用|未启用" | head -60

hr "5) TIS 缓存日志（最近 20 分钟）"
log show --last 20m 2>/dev/null | grep -i "TISFileInterrogator" | tail -6 || echo "(无)"

hr "6) 用户偏好里的第三方输入源"
defaults read com.apple.inputsources 2>/dev/null || echo "(无 com.apple.inputsources)"

hr "7) 本项目 bundle 的 plist 关键键"
if [ -f ~/Documents/EasyInputMethod/platforms/macos/build/Yinghuo.app/Contents/Info.plist ]; then
  plutil -p ~/Documents/EasyInputMethod/platforms/macos/build/Yinghuo.app/Contents/Info.plist \
    | grep -E "CFBundleIdentifier|CFBundleName|tsInputModeListKey|ComponentInputModeDict|LSBackgroundOnly"
fi

hr "8) 重启时间 / 登录"
sysctl -n kern.boottime; who
echo
