#!/bin/sh
# 一键跑完可自动化的验收项（报告191）：热键与上屏 → 客户端矩阵 → 性能/网络。
# 输出每项 PASS/FAIL 与最终 JSON 摘要；任一项失败则非零退出。
# 前置：生产宿主已装、输入源已在系统里启用；结束把 mode 还原为 mixed、输入源还原为 ABC。
set -u
PROBE="$(cd "$(dirname "$0")" && pwd)"
BIN="$PROBE/bin"
SUPPORT="${SUPPORT:-$HOME/Library/Application Support/Lampyris}"
CONFIG="$SUPPORT/config.toml"
OUT="${OUT:-/tmp/lampyris-acceptance-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$OUT"
FAILED=0

field() { grep -m1 "^$1" "$CONFIG" | sed 's/.*= *//; s/ *#.*//; s/"//g'; }
report() { printf '%-24s %s\n' "$1" "$2"; }

# 谓词：exact:/endswith:/contains:/ascii:/unicode:
check() { python3 -c 'import sys;kind,_,value=sys.argv[1].partition(":");got=sys.argv[2];f={"exact":lambda:got==value,"endswith":lambda:got.endswith(value),"contains":lambda:value in got,"ascii":lambda:got==value and got.isascii(),"unicode":lambda:bool(got) and any(ord(c)>0x7E for c in got)};sys.exit(0 if f[kind]() else 1)' "$1" "$2"; }

run_text() { "$PROBE/type-session.sh" "$1" --settle 8 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin).get("text",""))' 2>/dev/null; }

# 中英状态不在 config 里，只能探测：打 `wq ` 出中文说明是中文态，出裸 ascii 说明是英文态，再按一次 Shift 还原。
ensure_cn() {
    for _ in 1 2 3; do
        if check 'unicode:' "$(run_text 'wq ')"; then return 0; fi
        "$PROBE/type-session.sh" 'shiftc' --settle 6 >/dev/null 2>&1
    done
    return 1
}

assert_text() { # name keys predicate
    got=$("$PROBE/type-session.sh" "$2" --settle 8 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin).get("text",""))' 2>/dev/null)
    if check "$3" "$got"; then report "$1" "PASS ($got)"; else report "$1" "FAIL (got '$got' want '$3')"; FAILED=1; fi
}

# 1. 前置：模式必须是 mixed；不是就用产品热键循环回来
mode=$(field mode)
for _ in 1 2 3; do
    [ "$mode" = "mixed" ] && break
    "$PROBE/type-session.sh" 'opt+m' --settle 6 >/dev/null 2>&1
    mode=$(field mode)
done
[ "$mode" = "mixed" ] || { report "前置 mode" "BLOCKED (mode=$mode)"; exit 1; }
report "前置 mode=mixed" "OK"

# 2. 热键与上屏
assert_text "混输+标点"       'wq nihao .'            'endswith:你好。'
ensure_cn && report "前置 中文态" "OK" || { report "前置 中文态" "FAIL"; FAILED=1; }
assert_text "Shift 切英文"    'shiftc;abc'            'ascii:abc'
ensure_cn && report "还原中文态" "OK" || { report "还原中文态" "FAIL"; FAILED=1; }
assert_text "Shift 切回中文"  'shiftc;shiftc;wq '     'unicode:'
assert_text "⌥P 标点切换"     'opt+p;.;opt+p;.'       'exact:.。'
assert_text "⌥F 全角切换"     'opt+f;12;opt+f;12'     'exact:１２12'
assert_text "⌥T 繁简切换"     'opt+t;xuexi '          'exact:學習'
assert_text "⌥T 切回简体"     'opt+t;xuexi '          'exact:学习'
assert_text "⌥M 模式循环"     'opt+m;opt+m;opt+m;wq ' 'unicode:'

# 3. 客户端矩阵
if KEYS='wq nihao .' OUT="$OUT/clients" "$PROBE/client-matrix.sh" > "$OUT/clients.log" 2>&1; then
    ok=0; attempted=0; skipped=0
    for f in "$OUT"/clients/*.json; do
        if grep -q 'SKIP' "$f"; then skipped=$((skipped + 1)); continue; fi
        attempted=$((attempted + 1))
        grep -q '你好。' "$f" && ok=$((ok + 1))
    done
    if [ "$attempted" -ge 4 ] && [ "$ok" -eq "$attempted" ]; then
        report "客户端矩阵" "PASS ($ok/$attempted，跳过 $skipped)"
    else
        report "客户端矩阵" "FAIL ($ok/$attempted，跳过 $skipped)"; FAILED=1
    fi
else
    report "客户端矩阵" "FAIL (见 $OUT/clients.log)"; FAILED=1
fi

# 4. 性能与网络
PERF=$(ROUNDS="${ROUNDS:-10}" SETTLE="${SETTLE:-20}" OUT="$OUT/perf" "$PROBE/perf-session.sh" 2>/dev/null | tail -1)
case "$PERF" in
    *'"result": "PASS"'*) report "性能/网络" "PASS $(printf '%s' "$PERF" | head -c 160)" ;;
    *) report "性能/网络" "FAIL $(printf '%s' "$PERF" | head -c 160)"; FAILED=1 ;;
esac

# 4b. 久用（可选）：SOAK_MINUTES>0 时追加
SOAK_MINUTES="${SOAK_MINUTES:-0}"
if [ "$SOAK_MINUTES" -gt 0 ]; then
    SOAK=$(MINUTES="$SOAK_MINUTES" OUT="$OUT/soak" "$PROBE/soak-session.sh" 2>/dev/null | tail -1)
    case "$SOAK" in
        *'"result": "PASS"'*) report "久用/持久化" "PASS $(printf '%s' "$SOAK" | head -c 160)" ;;
        *) report "久用/持久化" "FAIL $(printf '%s' "$SOAK" | head -c 160)"; FAILED=1 ;;
    esac
fi

# 5. 还原
"$BIN/tissrc" select com.apple.keylayout.ABC >/dev/null 2>&1
final_mode=$(field mode)
[ "$final_mode" = "mixed" ] || { report "还原 mode" "FAIL ($final_mode)"; FAILED=1; }

python3 -c 'import json,sys;print(json.dumps({"result":"PASS" if int(sys.argv[1])==0 else "FAIL","evidence_dir":sys.argv[2]},ensure_ascii=False))' "$FAILED" "$OUT"
[ "$FAILED" -eq 0 ]
