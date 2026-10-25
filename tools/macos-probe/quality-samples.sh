#!/bin/sh
# 固定输入质量样本集（报告196）：把"典型输入 + 质量样本"固化成可复跑的表，逐条断言上屏结果。
# 用法：./tools/macos-probe/quality-samples.sh [--settle N]
# 前置：已装输入法、输入源启用、图形会话可用（否则以 78 退出，交由 CI/local 判 SKIP）。
set -u
PROBE="$(cd "$(dirname "$0")" && pwd)"
SETTLE=8
[ "${1:-}" = "--settle" ] && SETTLE="${2:-8}"

OUT="${OUT:-/tmp/lampyris-quality-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$OUT"

"$PROBE/acceptance-preflight.sh" > "$OUT/preflight.json" 2>&1 || {
    code=$?
    cat "$OUT/preflight.json"
    [ "$code" -eq 78 ] && { echo "SKIP 环境不具备（见 preflight.json）"; exit 78; }
    exit 1
}

check() { python3 -c 'import sys;kind,_,value=sys.argv[1].partition(":");got=sys.argv[2];f={"exact":lambda:got==value,"endswith":lambda:got.endswith(value),"contains":lambda:value in got,"ascii":lambda:got==value and got.isascii(),"unicode":lambda:bool(got) and any(ord(c)>0x7E for c in got),"empty":lambda:got==""};sys.exit(0 if f[kind]() else 1)' "$1" "$2"; }

FAILED=0
TOTAL=0
run() { # 名称 按键 判定
    TOTAL=$((TOTAL + 1))
    got=$("$PROBE/type-session.sh" "$2" --settle "$SETTLE" 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin).get("text",""))' 2>/dev/null)
    if check "$3" "$got"; then printf '%-26s PASS  %s\n' "$1" "$got"; else printf '%-26s FAIL  期望 %s，实得 %s\n' "$1" "$3" "$got"; FAILED=$((FAILED + 1)); fi
}

# 中英状态归位：本脚本按"混输 + 中文态"设计
ensure_cn() {
    for _ in 1 2 3; do
        t=$("$PROBE/type-session.sh" 'wq ' --settle 6 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin).get("text",""))' 2>/dev/null)
        check 'unicode:' "$t" && return 0
        "$PROBE/type-session.sh" 'shiftc' --settle 6 >/dev/null 2>&1
    done
    return 1
}

ensure_cn || { echo "BLOCKED 无法归位到中文态"; exit 1; }

# —— 核心输入 ——
run "五笔四码自动上屏"        'wqiy'                     'contains:你'
run "五笔一级简码"            'r '                       'unicode:'
run "混输拼音兜底（两字）"     'nihao '                   'endswith:你好'
run "全拼双字词"              'zhongguo '                'exact:中国'
run "拼音长词"                'zhonghuarenmingongheguo ' 'exact:中华人民共和国'

# —— 标点与形态 ——
run "中文标点句号"            'nihao .'                  'endswith:。'
run "中文标点逗号"            'nihao ,'                  'endswith:，'
run "成对引号"                '"'                        'unicode:'
run "全角数字往返"            'opt+f;1;opt+f;1'          'exact:１1'
run "简繁往返"                'opt+t;xuexi ;opt+t;xuexi ' 'contains:學習'

# —— 中英与健壮性 ——
run "单 Shift 切英文直通"      'shiftc;abc'               'ascii:abc'
"$PROBE/type-session.sh" 'shiftc' --settle 6 >/dev/null 2>&1
run "翻页键不破坏输入"         'nihao ,,,'                'unicode:'
run "撤销回到空态"            'wqiy;cmd+z'               'empty:'

python3 -c 'import json,sys;print(json.dumps({"total":int(sys.argv[1]),"failed":int(sys.argv[2]),"evidence":sys.argv[3],"result":"PASS" if int(sys.argv[2])==0 else "FAIL"},ensure_ascii=False))' "$TOTAL" "$FAILED" "$OUT"
[ "$FAILED" -eq 0 ]
