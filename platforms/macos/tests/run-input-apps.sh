#!/usr/bin/env bash
# 萤火虫 macOS ⑩ 五应用输入验收（TextEdit / Safari / Chrome / Terminal / 微信）。
#
# 用合成按键在真实应用里输入「wq + 空格 → 你」，再用 AX 或剪贴板核验上屏。
# 不暴露 AX 的 App（微信、浏览器地址栏）改用「剪贴板」读取聚焦文本框；**绝不按回车**。
#
# 前提：图形登录会话；萤火虫已安装并启用；终端已获「辅助功能」授权。
# 用法：./platforms/macos/tests/run-input-apps.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORK="$(mktemp -d)"
PASS=0
FAIL=0
CREATE_CHROME=0
CREATE_SAFARI=0
CREATE_TERMINAL=0

source "${ROOT}/platforms/macos/tests/lib-imk-auto.sh"

cleanup() {
    field_clear >/dev/null 2>&1 || true
    close_panel_windows
    if [ "$CREATE_CHROME" = "1" ]; then
        osascript -e 'tell application "Google Chrome" to close front window' >/dev/null 2>&1
    fi
    if [ "$CREATE_SAFARI" = "1" ]; then
        osascript -e 'tell application "Safari" to close front window' >/dev/null 2>&1
    fi
    if [ "$CREATE_TERMINAL" = "1" ]; then
        osascript -e 'tell application "Terminal" to close front window' >/dev/null 2>&1
    fi
    osascript -e 'tell application "TextEdit" to close every document saving no' >/dev/null 2>&1
    printf '' | pbcopy
    rm -rf "$WORK"
}
trap cleanup EXIT

# 在聚焦的输入框里输入 wq + 空格，期望得到「你」。
type_phrase_and_verify() {
    local surface="$1" got
    select_ime
    type_text "wq"
    sleep 0.2
    keycode 49
    sleep 0.6
    got="$(field_read_clipboard)"
    check_eq "$surface 输入 wq+空格" "$got" "你"
    field_clear
}

echo "▶ 编译 imk-auto"
imk_auto_build || { echo "❌ 编译失败（需 swiftc）" >&2; exit 1; }

echo "▶ 前置检查"
aui select >/dev/null 2>&1 || { echo "❌ 未找到萤火虫输入源" >&2; exit 1; }
require_host || exit 1
sleep 0.4

echo "▶ ⑩-1 TextEdit"
osascript -e 'tell application "TextEdit" to make new document' >/dev/null 2>&1
aui activate com.apple.TextEdit >/dev/null 2>&1
sleep 1.0
select_ime
type_text "wq"; sleep 0.2; keycode 49
sleep 0.6
got="$(osascript -e 'tell application "TextEdit" to get text of front document' 2>/dev/null)"
check_eq "TextEdit 输入 wq+空格" "$got" "你"
osascript -e 'tell application "System Events" to keystroke "z" using command down' >/dev/null 2>&1
sleep 0.6
got="$(osascript -e 'tell application "TextEdit" to get text of front document' 2>/dev/null)"
check_eq "TextEdit Cmd+Z 回退" "$got" ""

echo "▶ ⑩-2 Terminal（新窗口）"
osascript -e 'tell application "Terminal" to do script ""' >/dev/null 2>&1
CREATE_TERMINAL=1
sleep 1.5
aui activate com.apple.Terminal >/dev/null 2>&1
sleep 0.8
select_ime
type_text "wq"; sleep 0.2; keycode 49
sleep 0.8
if aui dump "com.apple.Terminal" | grep -q "你"; then
    ok "Terminal 上屏含「你」"
else
    no "Terminal 未看到「你」"
fi

echo "▶ ⑩-3 Chrome 地址栏（新窗口）"
osascript -e 'tell application "Google Chrome" to make new window' >/dev/null 2>&1
CREATE_CHROME=1
sleep 1.5
aui activate com.google.Chrome >/dev/null 2>&1
sleep 0.8
osascript -e 'tell application "System Events" to keystroke "l" using command down' >/dev/null 2>&1
sleep 0.5
type_phrase_and_verify "Chrome 地址栏"

echo "▶ ⑩-4 Safari 地址栏（新窗口）"
osascript -e 'tell application "Safari" to make new document' >/dev/null 2>&1
CREATE_SAFARI=1
sleep 1.5
aui activate com.apple.Safari >/dev/null 2>&1
sleep 0.8
osascript -e 'tell application "System Events" to keystroke "l" using command down' >/dev/null 2>&1
sleep 0.5
type_phrase_and_verify "Safari 地址栏"

echo "▶ ⑩-5 微信（需已登录且有会话；无 AX，用剪贴板）"
if pgrep -x WeChat >/dev/null; then
    aui activate com.tencent.xinWeChat >/dev/null 2>&1
    sleep 1.2
    if frontmost_name | grep -q "微信\|WeChat"; then
        pos="$(osascript -e 'tell application "System Events" to tell process "WeChat" to get position of window 1' 2>/dev/null | tr -d ' ')"
        size="$(osascript -e 'tell application "System Events" to tell process "WeChat" to get size of window 1' 2>/dev/null | tr -d ' ')"
        if [ -n "$pos" ] && [ -n "$size" ]; then
            wx="$(printf '%s' "$pos" | cut -d, -f1)"
            wy="$(printf '%s' "$pos" | cut -d, -f2)"
            ww="$(printf '%s' "$size" | cut -d, -f1)"
            wh="$(printf '%s' "$size" | cut -d, -f2)"
            aui click $(( wx + ww / 2 )) $(( wy + wh - 60 )) >/dev/null
            sleep 0.8
            type_phrase_and_verify "微信输入框"
        else
            no "微信窗口不可读（跳过）"
        fi
    else
        echo "  SKIP  微信未能前置（实际：$(frontmost_name)）"
    fi
else
    echo "  SKIP  微信未运行（先登录再跑本项）"
fi

echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
