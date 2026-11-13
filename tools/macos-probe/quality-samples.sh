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
# 报告267：键入样本默认在私有数据根里跑（ADR-215），不再往用户的 config/词库/薄弱字清单留痕。
# 进出私有根各要重启一次宿主；ISOLATE=0 可退回旧行为（直接写真实数据目录）。
ISOLATE="${ISOLATE:-1}"
SUPPORT_DIR="$HOME/Library/Application Support/Lampyris"
PRIVATE_SUPPORT="$OUT/support"
HOST_APP="$HOME/Library/Input Methods/Lampyris.app"
host_pid() { pgrep -x Lampyris | head -1; }
restart_host() {
    # IMK 可能按客户端拉起多个宿主实例；只停第一个会留下没带私有根的旧进程（报告 270）。
    pkill -x Lampyris 2>/dev/null
    for _ in $(seq 1 15); do [ -z "$(host_pid)" ] && break; sleep 1; done
    [ -z "$(host_pid)" ] || return 1
    open "$HOST_APP" 2>/dev/null || return 1
    for _ in $(seq 1 20); do [ -n "$(host_pid)" ] && return 0; sleep 1; done
    return 1
}
start_isolation() {
    [ "$ISOLATE" = 1 ] || return 0
    [ -d "$HOST_APP" ] || { echo "BLOCKED 未安装宿主，无法进入私有数据根" >&2; return 1; }
    mkdir -p "$PRIVATE_SUPPORT"
    ORIGINAL_SUPPORT_ENV=$(launchctl getenv LAMPYRIS_SUPPORT_DIR 2>/dev/null || true)
    launchctl setenv LAMPYRIS_SUPPORT_DIR "$PRIVATE_SUPPORT" || return 1
    # 从这一刻起环境变量已改：无论后面哪一步失败，trap 都必须把它还原。
    ISOLATION_ON=1
    restart_host || return 1
    # 必须回读宿主环境：没带上私有根就宁可不跑，也不能把样本写进真实词库。
    for p in $(pgrep -x Lampyris); do
        if ! ps eww -o command= -p "$p" 2>/dev/null | grep -q "LAMPYRIS_SUPPORT_DIR=$PRIVATE_SUPPORT"; then
            echo "BLOCKED 宿主 $p 未接受 LAMPYRIS_SUPPORT_DIR（ps eww 里没有该变量）" >&2
            return 1
        fi
    done
    SUPPORT_DIR="$PRIVATE_SUPPORT"
}
stop_isolation() {
    [ "${ISOLATION_ON:-0}" = 1 ] || return 0
    if [ -n "${ORIGINAL_SUPPORT_ENV:-}" ]; then
        launchctl setenv LAMPYRIS_SUPPORT_DIR "$ORIGINAL_SUPPORT_ENV"
    else
        launchctl unsetenv LAMPYRIS_SUPPORT_DIR
    fi
    ISOLATION_ON=0
    # 让宿主回到真实数据根；失败只提示，不掩盖样本结果。
    restart_host || echo "WARN 退出私有根后宿主未重启，下一次启动才会切回真实数据" >&2
}
# 报告231：清场用过的 TextEdit 文档与浏览器标签，失败也清。
cleanup_run() { "$PROBE/cleanup-windows.sh" --out "$OUT" --textedit >&2 || true; }
# 报告232：记住用户状态，跑完还原；开始前归位到 mixed/chinese/half/simplified。
STATE_BEFORE="$OUT/state-before.txt"
restore_state() { [ -f "$STATE_BEFORE" ] && "$PROBE/ime-state.sh" --restore "$STATE_BEFORE" >&2 || true; }
finish() { restore_state; cleanup_run; stop_isolation; }
trap finish EXIT INT TERM
start_isolation || { echo "BLOCKED 无法进入私有数据根（见上）"; exit 78; }
"$PROBE/ime-state.sh" --snapshot "$STATE_BEFORE" 2>/dev/null || true
"$PROBE/ime-state.sh" --ensure >&2 || { echo "BLOCKED 输入法状态无法归位"; exit 78; }

"$PROBE/acceptance-preflight.sh" > "$OUT/preflight.json" 2>&1 || {
    code=$?
    cat "$OUT/preflight.json"
    [ "$code" -eq 78 ] && { echo "SKIP 环境不具备（见 preflight.json）"; exit 78; }
    exit 1
}
# 多实例 TextEdit 会让 AppleScript 建文档（打到其中一个实例）与 axtext 读前台窗口（另一个实例）错位，
# 使「切输入源不丢字」「失焦再回来不丢字」误判（报告207 §3.1）。
instances=$(pgrep -x TextEdit | wc -l | tr -d ' ')
if [ "${instances}" -gt 1 ]; then
    echo "BLOCKED TextEdit 有 ${instances} 个实例：先退出多余实例再跑（否则建文档/读窗口可能不是同一个）" >&2
    exit 78
fi
"$BIN/tissrc" select cn.jokerhub.inputmethod.Lampyris.default >/dev/null

check() { python3 -c 'import sys;kind,_,value=sys.argv[1].partition(":");got=sys.argv[2];f={"exact":lambda:got==value,"endswith":lambda:got.endswith(value),"contains":lambda:value in got,"ascii":lambda:got==value and got.isascii(),"unicode":lambda:bool(got) and any(ord(c)>0x7E for c in got),"empty":lambda:got==""};sys.exit(0 if f[kind]() else 1)' "$1" "$2"; }

front_pid() { osascript -e 'tell application "System Events" to unix id of first application process whose frontmost is true' 2>/dev/null; }

# 新建一个**确认是空的**文档：报告230 之前用 axtext clear 清场，但本机同时存在多个 TextEdit
# 文档时 clear 清的不是落键的那个窗口，残留文本会让后面用例连环 FAIL（实测 5/13 假失败）。
new_doc() { osascript -e 'tell application "TextEdit" to activate' -e 'tell application "TextEdit" to make new document' >/dev/null 2>&1; sleep 1.2; }
fresh_doc() {
    for _ in 1 2 3 4; do
        new_doc
        [ -z "$("$BIN/axtext" 2>/dev/null | head -1)" ] && return 0
    done
    return 1
}
BLOCKED_CASES=0
blocked() { BLOCKED_CASES=$((BLOCKED_CASES + 1)); printf '%-26s BLOCKED  %s\n' "$1" "$2"; }

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
    sleep 0.2
    [ -z "$("$BIN/axtext" 2>/dev/null | head -1)" ] || new_doc
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
    # 私有根失效时立刻停：宁可 BLOCKED，也不能把样本写进用户真实词库/练习进度。
    if [ "${ISOLATION_ON:-0}" = 1 ]; then
        for p in $(pgrep -x Lampyris); do
            if ! ps eww -o command= -p "$p" 2>/dev/null | grep -q "LAMPYRIS_SUPPORT_DIR=$PRIVATE_SUPPORT"; then
                echo "BLOCKED 私有数据根失效（宿主 $p 没有 LAMPYRIS_SUPPORT_DIR），已停止后续样本" >&2
                exit 78
            fi
        done
    fi
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
# 归一化：新建一个空白文档，避免历史残留文本污染第一项（报告230 实测）。
new_doc

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
# 报告230：全角/简繁往返已由 acceptance-auto.sh 的 ⌥F/⌥T 状态往返覆盖，这里不再重复
# （同一行为只留一处断言，避免两边判定漂移）。

# —— 中英与健壮性 ——
# 报告230：单 Shift 切英文由 acceptance-auto.sh 的「Shift 切英文/切回中文」覆盖。
ensure_cn >/dev/null 2>&1
run "翻页键不破坏输入"         'nihao ,,,'                             'unicode:'
run "撤销回到空态"            'wqiy;cmd+z'                            'empty:'
run "长文本不丢字"            'nihao nihao nihao nihao wqiy '         'contains:你好你好'

# —— 1.2.1 之后的输入体验（ADR-325…336） ——
# 字面的 `;` 用命名键 semicolon，冒号是 shift+semicolon（按键串本身以分号分段）。
ensure_cn >/dev/null 2>&1
run "数字后句点保持半角"       '3.14'                                  'exact:3.14'
run "数字后逗号仍是中文"       '3,'                                    'exact:3，'
run "拼音没打完给补全"         'nih '                                  'exact:你好'
run "以词定字取首字"           'nihao['                                'exact:你'
run "以词定字取末字"           'nihao]'                                'exact:好'
# 选走前半段（第二候选「你好」只覆盖 nihao）后回车：已选文字 + 余码原文一起上屏。
run "分段选词后回车"           'nihaoshijie2;return'                   'exact:你好shijie'
# 带 Shift 的标点（ADR-337）：宿主按键码 + Shift 重新计算字符，合成事件与真实按键走同一条路。
run "数字后冒号保持半角"       '12;shift+semicolon;30'                 'exact:12:30'
run "Shift 标点（问号）"        'shift+/'                               'exact:？'
run "Shift 标点（冒号）"        'shift+semicolon'                       'exact:：'
# `;` 选第二候选：第二候选是什么取决于用户词库（学过的词会排上来），所以只断言「不是首选、也不是首选+；」。
case_semicolon_second() {
    TOTAL=$((TOTAL + 1))
    got=$(type_read 'nihao;semicolon;return')
    if [ -n "$got" ] && [ "$got" != "你好" ] && [ "$got" != "你好；" ] && check 'unicode:' "$got"; then
        printf '%-26s PASS  %s\n' "分号选第二候选" "$got"
    else printf '%-26s FAIL  应是第二候选，实得 %s\n' "分号选第二候选" "$got"; FAILED=$((FAILED + 1)); fi
}
case_semicolon_second

# —— 1.3.0 批次 B：日期候选与三级简码（ADR-342/345） ——
ensure_cn >/dev/null 2>&1
run "日期候选"                 'riqi '                                 'contains:年'
run "时间候选"                 'shijian '                              'contains::'
run "星期候选"                 'xingqi '                               'contains:星期'
run "三级简码"                 'aah '                                  'exact:芽'

# 改配置只走 ime-config 的写路径（ime-cli :set），用完还原；缺 ime-cli 就记 BLOCKED，不手改 config.toml。
ROOT="$(cd "$PROBE/../.." && pwd)"
IME_CLI="$ROOT/target/release/ime-cli"
CONFIG_FILE="$SUPPORT_DIR/config.toml"
cfg_set() { printf ':set %s %s\n:quit\n' "$1" "$2" | "$IME_CLI" --config "$CONFIG_FILE" >/dev/null 2>&1; sleep 1.2; }

case_double_pinyin() {
    TOTAL=$((TOTAL + 1))
    [ -x "$IME_CLI" ] || { blocked "双拼（小鹤）" "缺 target/release/ime-cli（先 cargo build --release -p ime-cli）"; return; }
    cfg_set mode '"pinyin"'; cfg_set pinyin.scheme '"xiaohe"'
    # 两次配置写入后宿主需要一拍才重建双拼引擎；太紧会测到全拼（报告 270）。
    sleep 1.5
    got=$(type_read 'nihc ')
    cfg_set pinyin.scheme '"full"'; cfg_set mode '"mixed"'
    if check 'exact:你好' "$got"; then printf '%-26s PASS  %s\n' "双拼（小鹤）" "$got"
    else printf '%-26s FAIL  期望 你好，实得 %s\n' "双拼（小鹤）" "$got"; FAILED=$((FAILED + 1)); fi
}

case_weak_chars() {
    TOTAL=$((TOTAL + 1))
    [ -x "$IME_CLI" ] || { blocked "薄弱字清单" "缺 target/release/ime-cli"; return; }
    weak="$SUPPORT_DIR/weak-chars.tsv"
    existed=0; [ -f "$weak" ] && { existed=1; cp "$weak" "$OUT/weak-chars.before.tsv"; }
    cfg_set practice.collect_weak_chars true
    # 配置写入到宿主重建引擎有一拍延迟（报告 270）。
    sleep 1.5
    # zhuang 超过 4 码，五笔不参与；首选是拼音单字。
    got=$(type_read 'zhuang ')
    sleep 0.5
    recorded=0
    [ -n "$got" ] && [ -f "$weak" ] && grep -q "^${got}	" "$weak" && recorded=1
    cfg_set practice.collect_weak_chars false
    # 还原：本用例造出来的文件删掉；原来就有的恢复原样。
    if [ "$existed" -eq 1 ]; then cp "$OUT/weak-chars.before.tsv" "$weak"; else rm -f "$weak"; fi
    if [ "$recorded" -eq 1 ]; then printf '%-26s PASS  %s 已记入\n' "薄弱字清单" "$got"
    else printf '%-26s FAIL  上屏 %s，未见于 weak-chars.tsv\n' "薄弱字清单" "$got"; FAILED=$((FAILED + 1)); fi
}

case_remember_english() {
    TOTAL=$((TOTAL + 1))
    ensure_cn >/dev/null 2>&1
    pid=$(front_pid); "$BIN/keytopid" "$pid" 'shiftc' 200 600 --hid >/dev/null 2>&1
    # 同一应用里新建文档（新的输入上下文）：应仍是英文，字母原样上屏。
    new_doc
    got=$(type_read 'nihao')
    ensure_cn >/dev/null 2>&1
    if check 'exact:nihao' "$got"; then printf '%-26s PASS  %s\n' "按应用记住英文状态" "$got"
    else printf '%-26s FAIL  期望 nihao，实得 %s\n' "按应用记住英文状态" "$got"; FAILED=$((FAILED + 1)); fi
}

# 五笔码浮层（ADR-331）没有样本：浮层不在 AX 树里，窗口列表也看不到它是否可见（报告265），需目视。

case_double_pinyin
case_weak_chars
case_remember_english
ensure_cn >/dev/null 2>&1

# —— 切换与焦点（MVP「日常可用」条目） ——
# 注意：用 TIS 切回输入源后，已开文档的输入上下文不会立即跟随；新建文档才会取到当前源。

# 切输入源用 type-session 的独立测试窗口，不再依赖 TextEdit 的文档状态（报告230）：
# 本机同时开着多个文档时，AX 读到的可能是旧窗口，导致「残留文本」被误判成丢字。
ts_text() { "$PROBE/type-session.sh" "$1" --settle "${TS_SETTLE:-4}" 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin).get("text",""))' 2>/dev/null; }

case_switch_source() {
    TOTAL=$((TOTAL + 1))
    "$BIN/tissrc" select cn.jokerhub.inputmethod.Lampyris.default >/dev/null; sleep 0.8
    part1=$(ts_text 'wqiy')
    "$BIN/tissrc" select com.apple.keylayout.ABC >/dev/null; sleep 0.8
    part2=$(ts_text 'abc')
    "$BIN/tissrc" select cn.jokerhub.inputmethod.Lampyris.default >/dev/null; sleep 0.8
    part3=$(ts_text 'nihao ')
    if check 'exact:你abc' "x$part2" && check 'exact:你好' "$part3"; then
        printf '%-26s PASS  %s | %s\n' "切输入源不丢字" "$part2" "$part3"
    elif check 'exact:abc' "$part2" && check 'exact:你好' "$part3" && check 'contains:你' "$part1"; then
        printf '%-26s PASS  %s | %s\n' "切输入源不丢字" "$part2" "$part3"
    else
        printf '%-26s FAIL  期望 abc / 你好，实得 %s / %s（首段 %s）\n' "切输入源不丢字" "$part2" "$part3" "$part1"
        FAILED=$((FAILED + 1))
    fi
}

case_refocus() {
    TOTAL=$((TOTAL + 1))
    "$BIN/tissrc" select cn.jokerhub.inputmethod.Lampyris.default >/dev/null; sleep 0.8
    fresh_doc || { blocked "失焦再回来不丢字" "拿不到空白 TextEdit 文档"; return; }
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

python3 -c 'import json,sys
total,failed,blocked = int(sys.argv[1]),int(sys.argv[2]),int(sys.argv[3])
result = "FAIL" if failed else ("BLOCKED" if blocked else "PASS")
print(json.dumps({"total": total, "failed": failed, "blocked": blocked, "evidence": sys.argv[4], "result": result}, ensure_ascii=False))
raise SystemExit(1 if failed else (78 if blocked else 0))' "$TOTAL" "$FAILED" "$BLOCKED_CASES" "$OUT"
