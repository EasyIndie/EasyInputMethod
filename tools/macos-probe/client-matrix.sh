#!/bin/sh
# 目标客户端矩阵：同一输入源、同一投递通道，逐客户端上屏并回读文本（报告189）。
# 铁律：每一批发键前都必须 guard-focus 且确认前台 PID 一致，否则按键会落到用户正在用的窗口（报告099/189）。
set -u
PROBE="$(cd "$(dirname "$0")" && pwd)"
BIN="$PROBE/bin"
KEYS="${KEYS:-wq nihao .}"
SOURCE="${SOURCE:-cn.jokerhub.inputmethod.Lampyris.default}"
OUT="${OUT:-/tmp/lampyris-client-matrix}"

mkdir -p "$OUT"
"$BIN/tissrc" select "$SOURCE" >/dev/null || { echo "BLOCKED 无法选中输入源 $SOURCE"; exit 1; }

has_app() {
    [ -d "/Applications/$1.app" ] || [ -d "/System/Applications/$1.app" ] && return 0
    for candidate in /Applications/"$1"*.app; do [ -d "$candidate" ] && return 0; done
    return 1
}

front_name() { osascript -e 'tell application "System Events" to name of first application process whose frontmost is true' 2>/dev/null; }
front_pid() { osascript -e 'tell application "System Events" to unix id of first application process whose frontmost is true' 2>/dev/null; }

# 等到目标应用在前台，再用一次纯修饰键"点"窗口（首个键会被激活吞掉），最后发正文。
type_into() {
    expected="$1"
    i=0
    while [ $i -lt 20 ]; do
        name=$(front_name)
        [ "$name" = "$expected" ] && break
        i=$((i + 1)); sleep 1
    done
    if [ "$(front_name)" != "$expected" ]; then
        echo "BLOCKED 前台不是 ${expected}（当前：$(front_name)）"
        return 1
    fi
    pid=$(front_pid)
    "$BIN/keytopid" "$pid" 'ctrl' 150 400 --hid >/dev/null 2>&1 || { echo "BLOCKED 激活键未投递"; return 1; }
    sleep 0.7
    "$BIN/keytopid" "$pid" "$KEYS" 200 600 --hid >/dev/null 2>&1 || { echo "BLOCKED 正文未投递"; return 1; }
    sleep 2
    return 0
}

echo "== TextEdit"
open -a TextEdit >/dev/null 2>&1
sleep 3
"$BIN/axtext" clear >/dev/null 2>&1
type_into TextEdit && "$BIN/axfocus" | tee "$OUT/textedit.json"

echo "== Safari"
PAGE='data:text/html,<meta charset=utf-8><textarea autofocus style="width:600px;height:200px;font-size:20px" oninput="document.title=this.value"></textarea>'
open -a Safari "$PAGE" >/dev/null 2>&1
if type_into Safari; then
    osascript -e 'tell application "Safari" to get name of front document' > "$OUT/safari.txt" 2>/dev/null
    printf '{"title":"%s"}\n' "$(cat "$OUT/safari.txt")" | tee "$OUT/safari.json"
fi

echo "== Chrome"
open -a "Google Chrome" "$PAGE" >/dev/null 2>&1
if type_into "Google Chrome"; then
    osascript -e 'tell application "Google Chrome" to get title of active tab of front window' > "$OUT/chrome.txt" 2>/dev/null
    printf '{"title":"%s"}\n' "$(cat "$OUT/chrome.txt")" | tee "$OUT/chrome.json"
fi

echo "== Ghostty"
CAT_FILE="$OUT/ghostty.txt"
rm -f "$CAT_FILE"
open -na Ghostty --args -e bash -c "cat > '$CAT_FILE'" >/dev/null 2>&1
if type_into ghostty; then
    pid=$(front_pid)
    "$BIN/keytopid" "$pid" 'ctrl+d' 150 400 --hid >/dev/null 2>&1
    sleep 2
    printf '{"file":"%s"}\n' "$(cat "$CAT_FILE" 2>/dev/null)" | tee "$OUT/ghostty.json"
fi

echo "== Xcode"
if ! has_app Xcode; then
    echo '{"file":"SKIP 未安装 Xcode"}' | tee "$OUT/xcode.json"
    echo "== restore"
    "$BIN/tissrc" select com.apple.keylayout.ABC >/dev/null
    "$BIN/tissrc" list | grep '^current'
    exit 0
fi
XFILE="$OUT/xcode.txt"
printf '' > "$XFILE"
open -a "/Applications/Xcode-27.0.0.app" "$XFILE" >/dev/null 2>&1
if type_into Xcode; then
    pid=$(front_pid)
    "$BIN/keytopid" "$pid" 'cmd+s' 200 500 --hid >/dev/null 2>&1
    sleep 3
    printf '{"file":"%s"}\n' "$(cat "$XFILE" 2>/dev/null)" | tee "$OUT/xcode.json"
fi

echo "== restore"
"$BIN/tissrc" select com.apple.keylayout.ABC >/dev/null
"$BIN/tissrc" list | grep '^current'
