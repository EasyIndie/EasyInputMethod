#!/bin/sh
# 多屏 / 全屏下的候选窗落点验收（报告202）：逐显示器把文本编辑窗口摆到屏内，键入触发候选窗，
# 用 AX 几何断言候选窗落在同一块屏幕内（不跑屏外），再在同一个窗口的全屏模式下重复一次。
# 前置：输入法已装且输入源已启用、图形会话可用（否则 78 = 环境不具备）。
# 不会改动配置/词库；结束关闭自建文档、退出全屏、输入源还原成 ABC。
set -u
PROBE="$(cd "$(dirname "$0")" && pwd)"
BIN="$PROBE/bin"
SOURCE="${SOURCE:-cn.jokerhub.inputmethod.Lampyris.default}"
OUT="${OUT:-/tmp/lampyris-multidisplay-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$OUT"

"$PROBE/acceptance-preflight.sh" > "$OUT/preflight.json" 2>&1 || {
    code=$?
    cat "$OUT/preflight.json"
    [ "$code" -eq 78 ] && { echo "SKIP 环境不具备（见 preflight.json）"; exit 78; }
    exit 1
}

front_name() { osascript -e 'tell application "System Events" to name of first application process whose frontmost is true' 2>/dev/null; }
front_pid() { osascript -e 'tell application "System Events" to unix id of first application process whose frontmost is true' 2>/dev/null; }
report() { printf '%-34s %s\n' "$1" "$2"; }

# AX/AppleScript 坐标以**主屏左上角**为原点、y 向下（其他屏可为负）。换算用主屏高度，不是包围盒高度（报告202）。
"$BIN/screens" > "$OUT/screens.json"

set_window() { # x y_tl w h
    osascript -e "tell application \"TextEdit\" to set bounds of front window to {$1, $2, $(($1 + $3)), $(($2 + $4))}" >/dev/null 2>&1
}

candidate_rect() { # 输出候选窗 "x y w h"（AX 坐标）；没有则输出空
    "$BIN/axwins" | python3 -c '
import json, sys
try:
    windows = json.load(sys.stdin)["windows"]
except Exception:
    print(""); raise SystemExit(0)
for window in windows:
    if window.get("subrole") == "AXSystemDialog" and all(key in window for key in ("x", "y", "w", "h")):
        print("%.0f %.0f %.0f %.0f" % (window["x"], window["y"], window["w"], window["h"]))
        break
else:
    print("")
'
}

type_keys() { "$BIN/keytopid" "$(front_pid)" "$1" 250 700 --hid >/dev/null 2>&1; }

# 在给定 AX 矩形里跑一次「键入→候选窗落点」检查。
check_placement() { # label screen_x screen_y_tl screen_w screen_h window_x window_y_tl window_w window_h
    label="$1"; sx="$2"; sy="$3"; sw="$4"; sh="$5"; wx="$6"; wy="$7"; ww="$8"; wh="$9"
    "$BIN/axtext" clear >/dev/null 2>&1
    type_keys 'ctrl'
    sleep 0.6
    type_keys 'wq'
    sleep 1.2
    rect=$(candidate_rect)
    # 换过显示模式/刚切源时首轮可能还没接上 IME（报告202）：重选源再试一次，不直接判失败。
    if [ -z "$rect" ]; then
        "$BIN/tissrc" select "$SOURCE" >/dev/null 2>&1
        "$BIN/axtext" clear >/dev/null 2>&1
        type_keys 'ctrl'
        sleep 0.8
        type_keys 'wq'
        sleep 1.5
        rect=$(candidate_rect)
    fi
    if [ -z "$rect" ]; then
        report "$label" "FAIL 未观察到候选窗（axwins 为空）"
        return 1
    fi
    set -- $rect; cx=$1; cy=$2; cw=$3; ch=$4
    if python3 - "$sx" "$sy" "$sw" "$sh" "$cx" "$cy" "$cw" "$ch" "$wx" "$wy" "$ww" "$wh" <<'PY'
import sys
sx, sy, sw, sh, cx, cy, cw, ch, wx, wy, ww, wh = map(float, sys.argv[1:13])
inside = cx >= sx - 2 and cy >= sy - 2 and cx + cw <= sx + sw + 2 and cy + ch <= sy + sh + 2
overlaps_window = cx < wx + ww and cx + cw > wx and cy < wy + wh and cy + ch > wy
near_window = abs(cx - wx) <= ww and cy >= wy - 4
raise SystemExit(0 if inside and overlaps_window and near_window else 1)
PY
    then
        report "$label" "PASS 候选窗 ${cx},${cy} ${cw}x${ch}（屏 ${sx},${sy} ${sw}x${sh}）"
        return 0
    else
        report "$label" "FAIL 候选窗 ${cx},${cy} ${cw}x${ch} 不在屏 ${sx},${sy} ${sw}x${sh} / 文本窗 ${wx},${wy} ${ww}x${wh} 附近"
        return 1
    fi
}

# 报告202：显示模式切换/反复全屏后，已运行 App 的输入上下文可能变成裸 ASCII（实测），
# 所以每块屏开始前重置一次 TextEdit（仅当它的文档全是空未命名时才退，避免碰到用户文档）。
reset_textedit() {
    if osascript -e 'tell application "TextEdit"
        repeat with d in documents
            if (path of d is not missing value) or ((text of d) is not "") then return 1
        end repeat
        return 0
    end tell' 2>/dev/null; then
        osascript -e 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1
        sleep 1.5
    fi
    open -a TextEdit >/dev/null 2>&1
    sleep 2
    osascript -e 'tell application "TextEdit" to activate' >/dev/null 2>&1
    osascript -e 'tell application "TextEdit" to make new document' >/dev/null 2>&1
    CREATED_DOCS=$((CREATED_DOCS + 1))
    sleep 1
}

CREATED_DOCS=0
open -a TextEdit >/dev/null 2>&1
sleep 2
osascript -e 'tell application "TextEdit" to activate' >/dev/null 2>&1
osascript -e 'tell application "TextEdit" to make new document' >/dev/null 2>&1
CREATED_DOCS=$((CREATED_DOCS + 1))
sleep 1
"$BIN/tissrc" select "$SOURCE" >/dev/null 2>&1

FAILED=0
python3 - "$OUT/screens.json" > "$OUT/plan.txt" <<'PY'
import json, sys
screens = json.load(open(sys.argv[1], encoding="utf-8"))["screens"]
main = next((screen for screen in screens if screen["is_main"]), screens[0])
height = int(main["frame"][1] + main["frame"][3])
for screen in screens:
    x, y, w, h = screen["frame"]
    # 名字里的空格会让 POSIX read 拆错字段（报告202），先换成下划线。
    print(screen["index"], screen["name"].replace(" ", "_"), int(x), int(height - y - h), int(w), int(h), int(screen["scale"]))
PY

while read -r index name x y_tl w h scale; do
    # 窗口摆在屏内一块稳定区域（避开菜单栏与底边），左右各留 60。
    wx=$((x + 60)); wy=$((y_tl + 60)); ww=$((w - 120)); wh=$((h - 220))
    [ "$ww" -gt 300 ] || { report "屏 $index（$name）" "SKIP 屏太小"; continue; }
    # 键盘焦点只给 TextEdit：每批发键前都过 guard-focus（报告099/189）。
    reset_textedit
    osascript -e "tell application \"TextEdit\" to activate" >/dev/null 2>&1
    set_window "$wx" "$wy" "$ww" "$wh"
    sleep 0.8
    if ! "$PROBE/guard-focus.sh" TextEdit >/dev/null 2>&1; then
        report "屏 $index（$name）" "BLOCKED 前台不是文本编辑（当前：$(front_name)）"
        FAILED=1
        continue
    fi
    "$BIN/axtext" clear >/dev/null 2>&1
    "$BIN/tissrc" select "$SOURCE" >/dev/null 2>&1
    tag=$(printf '%s' "$name" | tr ' ' '_')
    if check_placement "屏 $index 窗口内候选（${tag}）" "$x" "$y_tl" "$w" "$h" "$wx" "$wy" "$ww" "$wh"; then :; else FAILED=1; fi
    screenshot="$(printf '%s/display-%d-window.png' "$OUT" "$index")"
    /usr/sbin/screencapture -x -R"${wx},${wy},${ww},${wh}" "$screenshot" 2>/dev/null
    type_keys "esc"
    sleep 0.4
    "$BIN/axtext" clear >/dev/null 2>&1

    # 全屏：同一个窗口进全屏后再查一次（全屏 Space 的坐标原点可能与桌面不同）。
    if osascript -e 'tell application "System Events" to tell process "TextEdit" to set value of attribute "AXFullScreen" of window 1 to true' >/dev/null 2>&1; then
        sleep 2
        # 确认真的进了全屏，否则这条断言只是把窗口模式又测一遍（报告202）。
        if [ "$(osascript -e 'tell application "System Events" to tell process "TextEdit" to get value of attribute "AXFullScreen" of window 1' 2>/dev/null)" != "true" ]; then
            report "屏 $index 全屏" "SKIP AXFullScreen 未生效"
            continue
        fi
        if "$PROBE/guard-focus.sh" TextEdit >/dev/null 2>&1; then
            if check_placement "屏 $index 全屏候选（${tag}）" "$x" "$y_tl" "$w" "$h" "$x" "$y_tl" "$w" "$h"; then :; else FAILED=1; fi
            /usr/sbin/screencapture -x "$OUT/fullscreen-display-$index.png" 2>/dev/null
            type_keys "esc"
            sleep 0.4
            "$BIN/axtext" clear >/dev/null 2>&1
        else
            report "屏 $index 全屏" "BLOCKED 前台不是文本编辑"
            FAILED=1
        fi
        osascript -e 'tell application "System Events" to tell process "TextEdit" to set value of attribute "AXFullScreen" of window 1 to false' >/dev/null 2>&1
        sleep 2
    else
        report "屏 $index 全屏" "SKIP 无法设置 AXFullScreen"
    fi
done < "$OUT/plan.txt"

# 收尾：关掉本次产生的空未命名文档，并把 TextEdit 退出（全屏/换模式后它的输入上下文会变旧，
# 留着会让后续验收打到裸 ASCII，报告202）。只处理空且未命名的文档，用户文档不动。
# 我们自建的文档都是空的，逐个关掉；遇到有内容的（用户的）就停手（报告202）。
closed=0
while [ "$closed" -lt "$CREATED_DOCS" ]; do
    [ -z "$(osascript -e 'tell application "TextEdit" to get text of front document' 2>/dev/null)" ] || break
    osascript -e 'tell application "TextEdit" to close front window saving no' >/dev/null 2>&1 || break
    closed=$((closed + 1))
    sleep 0.3
done
"$BIN/tissrc" select com.apple.keylayout.ABC >/dev/null 2>&1
python3 -c 'import json,sys;print(json.dumps({"result":"PASS" if int(sys.argv[1])==0 else "FAIL","evidence":sys.argv[2]},ensure_ascii=False))' "$FAILED" "$OUT"
[ "$FAILED" -eq 0 ]
