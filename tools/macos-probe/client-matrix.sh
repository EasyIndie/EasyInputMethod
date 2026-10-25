#!/bin/sh
# 目标客户端矩阵：同一输入源、同一投递通道，逐客户端上屏并回读文本（报告189）。
# 每个客户端发键前都必须先过 guard-focus.sh，避免按键落到用户正在用的窗口（报告099/189 事故）。
set -u
PROBE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$PROBE/../.." && pwd)"
BIN="$PROBE/bin"
KEYS="${KEYS:-wq nihao .}"
SOURCE="${SOURCE:-cn.jokerhub.inputmethod.Lampyris.default}"
OUT="${OUT:-/tmp/lampyris-client-matrix}"

mkdir -p "$OUT"
"$BIN/tissrc" select "$SOURCE" >/dev/null || { echo "BLOCKED 无法选中输入源 $SOURCE"; exit 1; }

type_into() {
    app="$1"
    expected="$2"
    "$PROBE/guard-focus.sh" "$expected" | tail -1
    "$PROBE/guard-focus.sh" "$expected" | grep -q ok || { echo "BLOCKED 前台不是 $expected"; return 1; }
    "$BIN/keytopid" 0 "$KEYS" 150 300 --hid >/dev/null
    sleep 2
}

echo "== TextEdit"
open -a TextEdit >/dev/null 2>&1
sleep 3
"$BIN/axtext" clear >/dev/null 2>&1
type_into TextEdit TextEdit && "$BIN/axfocus" | tee "$OUT/textedit.json"

echo "== Safari"
PAGE='data:text/html,<meta charset=utf-8><textarea autofocus style="width:600px;height:200px;font-size:20px" oninput="document.title=this.value"></textarea>'
open -a Safari "$PAGE" >/dev/null 2>&1
sleep 5
type_into Safari Safari >/dev/null
osascript -e 'tell application "Safari" to get name of front document' > "$OUT/safari.txt" 2>/dev/null
printf '{"title":"%s"}\n' "$(cat "$OUT/safari.txt")" | tee "$OUT/safari.json"

echo "== Chrome"
open -a "Google Chrome" "$PAGE" >/dev/null 2>&1
sleep 6
type_into Chrome "Google Chrome" >/dev/null
osascript -e 'tell application "Google Chrome" to get title of active tab of front window' > "$OUT/chrome.txt" 2>/dev/null
printf '{"title":"%s"}\n' "$(cat "$OUT/chrome.txt")" | tee "$OUT/chrome.json"

echo "== Ghostty"
CAT_FILE="$OUT/ghostty.txt"
rm -f "$CAT_FILE"
open -na Ghostty --args -e bash -c "cat > '$CAT_FILE'" >/dev/null 2>&1
sleep 5
type_into ghostty ghostty >/dev/null
"$BIN/keytopid" 0 'ctrl+d' 150 300 --hid >/dev/null
sleep 2
printf '{"file":"%s"}\n' "$(cat "$CAT_FILE" 2>/dev/null)" | tee "$OUT/ghostty.json"

echo "== restore"
"$BIN/tissrc" select com.apple.keylayout.ABC >/dev/null
"$BIN/tissrc" list | grep '^current'
