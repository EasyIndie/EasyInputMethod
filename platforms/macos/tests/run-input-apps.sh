#!/usr/bin/env bash
# 萤火虫 macOS ⑩ 五应用输入验收（TextEdit / Safari / Chrome / Terminal / 微信）。
#
# 用合成按键在真实应用里输入「wq + 空格 → 你」，再用 AX 或剪贴板核验上屏。
# 浏览器地址栏用剪贴板读取；微信尚无安全隔离草稿，明确BLOCKED；绝不按回车。
#
# 前提：图形登录会话；萤火虫已安装并启用；终端已获「辅助功能」授权。
# 用法：./platforms/macos/tests/run-input-apps.sh
set -uo pipefail

# No live bypass until the installed host's learning state is isolated (IT-01).
echo 'BLOCKED：真实IMK学习数据隔离尚未完成；旧入口禁用，不能用通过数量替代最终包覆盖清单。' >&2
exit 3

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORK="$(mktemp -d)"
PASS=0
FAIL=0
ORIGINAL_SOURCE=""
CLIP_COUNT=""
STATE_READY=0
PASTEBOARD="${WORK}/pasteboard-state"
source "${ROOT}/platforms/macos/tests/owned-resources.sh"

source "${ROOT}/platforms/macos/tests/lib-imk-auto.sh"

cleanup() {
    local result=$? recovery=0
    owned_cleanup || recovery=1
    if [ "$STATE_READY" = 1 ]; then
        aui select-exact "$ORIGINAL_SOURCE" >/dev/null 2>&1 || recovery=1
        "$PASTEBOARD" restore "$WORK/clipboard.json" "$CLIP_COUNT" || recovery=1
    fi
    if [ "$recovery" = 0 ]; then
        rm -rf "$WORK"
    else
        echo "BLOCKED 状态恢复未完成；保留备份：$WORK" >&2
        result=1
    fi
    exit "$result"
}

clipboard_observe() { CLIP_COUNT="$("$PASTEBOARD" count)" || exit 1; }

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# 在聚焦的输入框里输入 wq + 空格，期望得到「你」。
type_phrase_and_verify() {
    local surface="$1" got before_copy
    select_ime
    owned_type "wq"
    sleep 0.2
    owned_do key 49
    sleep 0.6
    owned_do select-all
    sleep 0.25
    before_copy="$("$PASTEBOARD" count)" || exit 1
    owned_do copy
    sleep 0.35
    clipboard_observe
    if [ "$CLIP_COUNT" = "$before_copy" ]; then
        echo "BLOCKED 复制未产生新剪贴板内容，拒绝使用旧值验收" >&2
        exit 1
    fi
    got="$(pbpaste)"
    check_eq "$surface 输入 wq+空格" "$got" "你"
    # The owned browser window is closed on exit; do not send a destructive clear.
}

echo "▶ 编译 imk-auto"
imk_auto_build || { echo "❌ 编译失败（需 swiftc）" >&2; exit 1; }

swiftc -O -warnings-as-errors "$ROOT/platforms/macos/tests/pasteboard-state.swift" -o "$PASTEBOARD" || exit 1
ORIGINAL_SOURCE="$(aui current-source)" || exit 1
CLIP_COUNT="$("$PASTEBOARD" save "$WORK/clipboard.json")" || exit 1
STATE_READY=1

echo "▶ 前置检查"
aui select >/dev/null 2>&1 || { echo "❌ 未找到萤火虫输入源" >&2; exit 1; }
require_host || exit 1
sleep 0.4

echo "▶ ⑩-1 TextEdit"
owned_textedit_create || exit 1
aui activate com.apple.TextEdit >/dev/null 2>&1
sleep 1.0
select_ime
owned_type "wq"; sleep 0.2; owned_do key 49
sleep 0.6
got="$(owned_do read)" || exit 1
check_eq "TextEdit 输入 wq+空格" "$got" "你"
owned_do undo
sleep 0.6
got="$(owned_do read)" || exit 1
check_eq "TextEdit Cmd+Z 回退" "$got" ""

echo "▶ ⑩-2 Terminal（新窗口）"
id="$(osascript -e 'tell application "Terminal" to get id of window of (do script "")')" || exit 1
owned_record Terminal window "$id" || exit 1
sleep 1.5
aui activate com.apple.Terminal >/dev/null 2>&1
sleep 0.8
select_ime
owned_type "wq"; sleep 0.2; owned_do key 49
sleep 0.8
if aui dump "com.apple.Terminal" | grep -q "你"; then
    ok "Terminal 上屏含「你」"
else
    no "Terminal 未看到「你」"
fi

echo "▶ ⑩-3 Chrome 地址栏（新窗口）"
id="$(osascript -e 'tell application "Google Chrome" to get id of (make new window)')" || exit 1
owned_record "Google Chrome" window "$id" || exit 1
sleep 1.5
aui activate com.google.Chrome >/dev/null 2>&1
sleep 0.8
owned_do address
sleep 0.5
type_phrase_and_verify "Chrome 地址栏"

echo "▶ ⑩-4 Safari 地址栏（新窗口）"
id="$(osascript -e 'tell application "Safari"' -e 'set newDocument to make new document' -e 'get id of first window whose document is newDocument' -e 'end tell')" || exit 1
owned_record Safari window "$id" || exit 1 || exit 1
sleep 1.5
aui activate com.apple.Safari >/dev/null 2>&1
sleep 0.8
owned_do address
sleep 0.5
type_phrase_and_verify "Safari 地址栏"

echo "  BLOCKED 微信：尚无可验证所有权的隔离草稿，不向已有聊天投递按键"
FAIL=$((FAIL + 1))

echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
