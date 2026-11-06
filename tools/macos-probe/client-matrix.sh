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
# 报告231：矩阵会开 TextEdit 文档、浏览器标签和 Xcode 窗口，结束（含失败）一律收掉。
# 「由我们启动」的应用在没有窗口时才退出；本来就开着的（用户可能在用）只关我们自己的窗口。
STARTED=""
for pair in "TextEdit:TextEdit" "Xcode:Xcode"; do
    app="${pair%%:*}"; binary="${pair##*:}"
    pgrep -x "$binary" >/dev/null 2>&1 || STARTED="$STARTED --quit-app $app"
done
cleanup_run() { "$PROBE/cleanup-windows.sh" --out "$OUT" --textedit $STARTED >&2 || true; }
trap cleanup_run EXIT INT TERM
"$BIN/tissrc" select "$SOURCE" >/dev/null || { echo "BLOCKED 无法选中输入源 $SOURCE"; exit 1; }

# 报告234：验收只依赖**系统自带**应用（TextEdit / Safari），它们在每台 macOS 上都有；
# Chrome / Xcode 这类"用户自己装的"一律 optional：装了才测，没装就 SKIP，且不计入必需的通过数。
required_json='{"required":true'
optional_json='{"required":false'

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
sleep 2
# 报告231：自己开一个空白文档，读完就关——不再借用（也可能污染）用户正在写的文档。
osascript -e 'tell application "TextEdit" to activate' -e 'tell application "TextEdit" to make new document' >/dev/null 2>&1
sleep 1.5
"$BIN/axtext" clear >/dev/null 2>&1
if type_into TextEdit; then
    # 报告232：回读必须绑定到 TextEdit 自己的 pid。之前用 `axfocus`（读"当前前台应用"），
    # 一旦焦点在我们自己的终端（pi 所在窗口）上，就会把终端的文本当成 TextEdit 的结果（实测踩到）。
    te_pid=$(pgrep -x TextEdit | head -1)
    got=""
    [ -n "$te_pid" ] && got=$("$BIN/axtext" read "$te_pid" 2>/dev/null | head -1)
    case "$got" in
        ""|NO_TEXT_AREA|NO_WINDOW)
            got=$("$BIN/axfocus" 2>/dev/null)
            ;;
    esac
    printf '%s,"app":"TextEdit","value":"%s"}\n' "$required_json" "$got" | tee "$OUT/textedit.json"
fi
# 关掉自己开的那个文档（front document 就是刚建的空白文档）
osascript -e 'tell application "TextEdit" to close front document saving no' >/dev/null 2>&1

# 报告198：macOS 13 的 LaunchServices 不接受 `open -a Safari 'data:…'`（Unable to interpret … as a path or URL），
# 改用临时 HTML 文件，两个版本都可用。
PAGE="$(cd "$OUT" && pwd)/page.html"
cat > "$PAGE" <<'HTML'
<meta charset=utf-8><textarea autofocus style="width:600px;height:200px;font-size:20px" oninput="document.title=this.value"></textarea>
HTML

echo "== Safari"
open -a Safari "$PAGE" >/dev/null 2>&1
if type_into Safari; then
    # 报告209：macOS 27 上页面标题不一定随输入更新（Safari 的 document.title 没有跟），
    # 先用 AX 读输入区，读不到再退回标题。
    sf_pid=$(pgrep -x Safari | head -1)
    [ -n "$sf_pid" ] || sf_pid=$(front_pid)
    got=$("$BIN/axtext" read "$sf_pid" 2>/dev/null | head -1)
    case "$got" in
        ""|NO_TEXT_AREA|NO_WINDOW)
            osascript -e 'tell application "Safari" to get name of front document' > "$OUT/safari.txt" 2>/dev/null
            got=$(cat "$OUT/safari.txt" 2>/dev/null)
            ;;
    esac
    printf '%s,"title":"%s"}\n' "$required_json" "$got" | tee "$OUT/safari.json"
fi

echo "== Chrome（可选：非系统自带）"
if has_app "Google Chrome"; then
    open -a "Google Chrome" "$PAGE" >/dev/null 2>&1
    if type_into "Google Chrome"; then
        osascript -e 'tell application "Google Chrome" to get title of active tab of front window' > "$OUT/chrome.txt" 2>/dev/null
        printf '%s,"title":"%s"}\n' "$optional_json" "$(cat "$OUT/chrome.txt")" | tee "$OUT/chrome.json"
    fi
else
    printf '%s,"status":"SKIP","reason":"未安装 Google Chrome（非系统自带）"}\n' "$optional_json" | tee "$OUT/chrome.json"
fi

# 报告229：终端项不做自动化。
# 原因一：往 Terminal.app 投递按键会落进**用户自己的** shell 会话（do script 的前台窗口不确定），
#        实测 `cat > 文件` 收不到字、按键可能污染用户终端；
# 原因二：用户设备偏好明确不用 Ghostty（旧实现在这里 example 用的就是 Ghostty 独立实例）。
# 终端路径仍由 IT-22 §3.5 人工走查覆盖，这里只留一条 SKIP 记录，不假装 PASS。
echo "== Terminal"
printf '%s,"status":"SKIP","reason":"终端项不在自动化矩阵内（会往用户 shell 打字）"}\n' "$optional_json" | tee "$OUT/terminal.json"

echo "== Xcode（可选：非系统自带）"
if ! has_app Xcode; then
    printf '%s,"status":"SKIP","reason":"未安装 Xcode（非系统自带）"}\n' "$optional_json" | tee "$OUT/xcode.json"
else
    XFILE="$OUT/xcode.txt"
    printf '' > "$XFILE"
    # 报告234：不写死版本路径（旧实现是 /Applications/Xcode-27.0.0.app），按应用名打开。
    open -a Xcode "$XFILE" >/dev/null 2>&1
    if type_into Xcode; then
        pid=$(front_pid)
        "$BIN/keytopid" "$pid" 'cmd+s' 200 500 --hid >/dev/null 2>&1
        sleep 3
        printf '%s,"file":"%s"}\n' "$optional_json" "$(cat "$XFILE" 2>/dev/null)" | tee "$OUT/xcode.json"
    else
        printf '%s,"status":"SKIP","reason":"前台未切到 Xcode（可选客户端）"}\n' "$optional_json" | tee "$OUT/xcode.json"
    fi
fi

echo "== restore"
"$BIN/tissrc" select com.apple.keylayout.ABC >/dev/null
"$BIN/tissrc" list | grep '^current'
