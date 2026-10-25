#!/bin/sh
# 固定输入质量样本集（报告196）：把"典型输入 + 质量样本"固化成可复跑的表，逐条断言上屏结果。
# 在真实客户端（文本编辑）里键入并用 AX 回读：测试窗口对长拼音组合不可靠（报告196 §4）。
# 用法：./tools/macos-probe/quality-samples.sh [--settle N]
# 前置：已装输入法、输入源启用、图形会话可用（否则以 78 退出，交由 CI/local 判 SKIP）。
set -u
PROBE="$(cd "$(dirname "$0")" && pwd)"
BIN="$PROBE/bin"
SETTLE=1.5
[ "${1:-}" = "--settle" ] && SETTLE="${2:-1.5}"

OUT="${OUT:-/tmp/lampyris-quality-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$OUT"

"$PROBE/acceptance-preflight.sh" > "$OUT/preflight.json" 2>&1 || {
    code=$?
    cat "$OUT/preflight.json"
    [ "$code" -eq 78 ] && { echo "SKIP 环境不具备（见 preflight.json）"; exit 78; }
    exit 1
}
"$BIN/tissrc" select cn.jokerhub.inputmethod.Lampyris.default >/dev/null

check() { python3 -c 'import sys;kind,_,value=sys.argv[1].partition(":");got=sys.argv[2];f={"exact":lambda:got==value,"endswith":lambda:got.endswith(value),"contains":lambda:value in got,"ascii":lambda:got==value and got.isascii(),"unicode":lambda:bool(got) and any(ord(c)>0x7E for c in got),"empty":lambda:got==""};sys.exit(0 if f[kind]() else 1)' "$1" "$2"; }

front_pid() { osascript -e 'tell application "System Events" to unix id of first application process whose frontmost is true' 2>/dev/null; }

# 在文本编辑里清空、键入、回读。落键前先 guard，避免打错窗口（报告099/189）。
type_read() {
    keys="$1"
    open -a TextEdit >/dev/null 2>&1
    for _ in 1 2 3 4 5; do
        name=$(osascript -e 'tell application "System Events" to name of first application process whose frontmost is true' 2>/dev/null)
        [ "$name" = "TextEdit" ] || [ "$name" = "文本编辑" ] && break
        sleep 0.6
    done
    "$BIN/axtext" clear >/dev/null 2>&1
    pid=$(front_pid)
    "$BIN/keytopid" "$pid" 'ctrl' 150 400 --hid >/dev/null 2>&1
    sleep 0.6
    "$BIN/keytopid" "$pid" "$keys" 250 800 --hid >/dev/null 2>&1
    sleep "$SETTLE"
    "$BIN/axtext" 2>/dev/null | head -1
}

FAILED=0
TOTAL=0
run() { # 名称 按键 判定
    TOTAL=$((TOTAL + 1))
    got=$(type_read "$2")
    if check "$3" "$got"; then printf '%-26s PASS  %s\n' "$1" "$got"; else printf '%-26s FAIL  期望 %s，实得 %s\n' "$1" "$3" "$got"; FAILED=$((FAILED + 1)); fi
}

ensure_cn() {
    for _ in 1 2 3; do
        t=$(type_read 'wq ')
        check 'unicode:' "$t" && return 0
        pid=$(front_pid); "$BIN/keytopid" "$pid" 'shiftc' 200 600 --hid >/dev/null 2>&1 || return 1
    done
    return 1
}
ensure_cn || { echo "BLOCKED 无法归位到中文态"; exit 1; }

# —— 核心输入 ——
run "五笔四码自动上屏"        'wqiy'                                  'contains:你'
run "五笔一级简码"            'r '                                    'unicode:'
run "混输拼音兜底（两字）"     'nihao '                                'endswith:你好'
run "全拼双字词"              'zhongguo '                             'exact:中国'
run "拼音长词"                'zhonghuarenmingongheguo '              'exact:中华人民共和国'

# —— 标点与形态 ——
run "中文标点句号"            'nihao .'                               'endswith:。'
run "中文标点逗号"            'nihao ,'                               'endswith:，'
run "成对引号（交替）"        "';'"                                    'exact:‘’'
run "全角数字往返"            'opt+f;1;opt+f;1'                       'exact:１1'
run "简繁往返"                'opt+t;xuexi ;opt+t;xuexi '              'contains:學習'

# —— 中英与健壮性 ——
run "单 Shift 切英文直通"      'shiftc;abc'                            'ascii:abc'
ensure_cn >/dev/null 2>&1
run "翻页键不破坏输入"         'nihao ,,,'                             'unicode:'
run "撤销回到空态"            'wqiy;cmd+z'                            'empty:'
run "长文本不丢字"            'nihao nihao nihao nihao wqiy '         'contains:你好你好'

# —— 切换与焦点（MVP「日常可用」条目） ——
# 注意：用 TIS 切回输入源后，已开文档的输入上下文不会立即跟随；新建文档才会取到当前源。
new_doc() { osascript -e 'tell application "TextEdit" to activate' -e 'tell application "TextEdit" to make new document' >/dev/null 2>&1; sleep 1.5; }

case_switch_source() {
    TOTAL=$((TOTAL + 1))
    "$BIN/tissrc" select cn.jokerhub.inputmethod.Lampyris.default >/dev/null; sleep 0.8
    open -a TextEdit >/dev/null 2>&1; sleep 1
    "$BIN/axtext" clear >/dev/null 2>&1
    pid=$(front_pid)
    "$BIN/keytopid" "$pid" 'ctrl' 150 400 --hid >/dev/null 2>&1; sleep 0.5
    "$BIN/keytopid" "$pid" 'wqiy' 250 800 --hid >/dev/null 2>&1; sleep 1
    part1=$("$BIN/axtext" 2>/dev/null | head -1)
    "$BIN/tissrc" select com.apple.keylayout.ABC >/dev/null; sleep 1
    "$BIN/keytopid" "$pid" 'abc' 250 800 --hid >/dev/null 2>&1; sleep 1
    part2=$("$BIN/axtext" 2>/dev/null | head -1)
    "$BIN/tissrc" select cn.jokerhub.inputmethod.Lampyris.default >/dev/null; sleep 0.8
    new_doc
    pid=$(front_pid)
    "$BIN/keytopid" "$pid" 'ctrl' 150 400 --hid >/dev/null 2>&1; sleep 0.5
    "$BIN/keytopid" "$pid" 'nihao ' 250 800 --hid >/dev/null 2>&1; sleep 1.5
    part3=$("$BIN/axtext" 2>/dev/null | head -1)
    if check 'exact:你abc' "$part2" && check 'exact:你好' "$part3"; then
        printf '%-26s PASS  %s | %s\n' "切输入源不丢字" "$part2" "$part3"
    else
        printf '%-26s FAIL  期望 你abc / 你好，实得 %s / %s（首段 %s）\n' "切输入源不丢字" "$part2" "$part3" "$part1"
        FAILED=$((FAILED + 1))
    fi
}

case_refocus() {
    TOTAL=$((TOTAL + 1))
    "$BIN/tissrc" select cn.jokerhub.inputmethod.Lampyris.default >/dev/null; sleep 0.8
    new_doc
    pid=$(front_pid)
    "$BIN/keytopid" "$pid" 'ctrl' 150 400 --hid >/dev/null 2>&1; sleep 0.5
    "$BIN/keytopid" "$pid" 'nihao ' 250 800 --hid >/dev/null 2>&1; sleep 1.2
    open -a Safari >/dev/null 2>&1; sleep 2
    open -a TextEdit >/dev/null 2>&1; sleep 2
    got=$("$BIN/axtext" 2>/dev/null | head -1)
    if check 'exact:你好' "$got"; then printf '%-26s PASS  %s\n' "失焦再回来不丢字" "$got"; else printf '%-26s FAIL  期望 你好，实得 %s\n' "失焦再回来不丢字" "$got"; FAILED=$((FAILED + 1)); fi
}

case_switch_source
case_refocus
osascript -e 'tell application "TextEdit" to close every document saving no' >/dev/null 2>&1

python3 -c 'import json,sys;print(json.dumps({"total":int(sys.argv[1]),"failed":int(sys.argv[2]),"evidence":sys.argv[3],"result":"PASS" if int(sys.argv[2])==0 else "FAIL"},ensure_ascii=False))' "$TOTAL" "$FAILED" "$OUT"
[ "$FAILED" -eq 0 ]
