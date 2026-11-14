#!/bin/sh
# 一键跑完可自动化的验收项（报告191；2026-11-14 收敛）：热键与上屏 → 性能/网络。
# Safari / Chrome / Xcode 客户端矩阵已移除；真实客户端只保留系统自带 TextEdit（质量样本覆盖）。
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
BLOCKED=0
# 报告231：跑完（含中断、失败）都把本轮开出来的窗口/进程收掉，保证"再跑一遍还是干净的"。
cleanup_run() { "$PROBE/cleanup-windows.sh" --out "$OUT" --textedit >&2 || true; }
# 报告232：先记下用户当前的四项状态，跑完（含失败）还原；再归位到验收需要的状态。
STATE_BEFORE="$OUT/state-before.txt"
restore_state() { [ -f "$STATE_BEFORE" ] && "$PROBE/ime-state.sh" --restore "$STATE_BEFORE" >&2 || true; }
finish() { restore_state; cleanup_run; }
trap finish EXIT INT TERM
"$PROBE/ime-state.sh" --snapshot "$STATE_BEFORE" 2>/dev/null || true
"$PROBE/ime-state.sh" --ensure >&2 || { echo "BLOCKED 输入法状态无法归位（见 ime-state.sh 输出）"; exit 78; }
# 报告230：FAST=1 用于开发迭代（轮数与静置都降一档，约省一半时间）；发布门禁用默认值。
if [ "${FAST:-0}" = "1" ]; then
    # 热键项不能压太狠：⌥M/⌥T 要等配置落盘，settle 4 会读到空文本（实测一次 FAIL）。
    ROUNDS="${ROUNDS:-4}"; SETTLE="${SETTLE:-8}"; KEY_SETTLE="${KEY_SETTLE:-6}"
fi

field() { grep -m1 "^$1" "$CONFIG" | sed 's/.*= *//; s/ *#.*//; s/"//g'; }
report() { printf '%-24s %s\n' "$1" "$2"; }

# 谓词：exact:/endswith:/contains:/ascii:/unicode:
check() { python3 -c 'import sys;kind,_,value=sys.argv[1].partition(":");got=sys.argv[2];f={"exact":lambda:got==value,"endswith":lambda:got.endswith(value),"contains":lambda:value in got,"ascii":lambda:got==value and got.isascii(),"unicode":lambda:bool(got) and any(ord(c)>0x7E for c in got)};sys.exit(0 if f[kind]() else 1)' "$1" "$2"; }

KEY_SETTLE="${KEY_SETTLE:-8}"

run_text() { "$PROBE/type-session.sh" "$1" --settle "$KEY_SETTLE" 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin).get("text",""))' 2>/dev/null; }

# 中英状态不在 config 里，只能探测：打 `wq ` 出中文说明是中文态，出裸 ascii 说明是英文态，再按一次 Shift 还原。
ensure_cn() {
    for _ in 1 2 3; do
        if check 'unicode:' "$(run_text 'wq ')"; then return 0; fi
        "$PROBE/type-session.sh" 'shiftc' --settle 6 >/dev/null 2>&1
    done
    return 1
}

assert_text() { # name keys predicate
    got=$("$PROBE/type-session.sh" "$2" --settle "$KEY_SETTLE" 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin).get("text",""))' 2>/dev/null)
    if check "$3" "$got"; then report "$1" "PASS ($got)"; else report "$1" "FAIL (got '$got' want '$3')"; FAILED=1; fi
}

# 1. 前置：模式必须是 mixed；不是就用产品热键循环回来
mode=$(field mode)
for _ in 1 2 3; do
    [ "$mode" = "mixed" ] && break
    "$PROBE/type-session.sh" 'opt+m' --settle "$KEY_SETTLE" >/dev/null 2>&1
    mode=$(field mode)
done
[ "$mode" = "mixed" ] || { report "前置 mode" "BLOCKED (mode=$mode)"; exit 1; }
report "前置 mode=mixed" "OK"

# 2. 热键与上屏
# 报告230：「混输+标点」与 quality-samples.sh 的兜底/句号/引号用例重复，已移出本脚本；
# 中文态由下面的 ensure_cn 把关，热键项只看状态语义。
ensure_cn && report "前置 中文态" "OK" || { report "前置 中文态" "FAIL"; FAILED=1; }
assert_text "Shift 切英文"    'shiftc;abc'            'ascii:abc'
ensure_cn && report "还原中文态" "OK" || { report "还原中文态" "FAIL"; FAILED=1; }
assert_text "Shift 切回中文"  'shiftc;shiftc;wq '     'unicode:'
assert_text "⌥P 标点切换"     'opt+p;.;opt+p;.'       'exact:.。'
assert_text "⌥F 全角切换"     'opt+f;12;opt+f;12'     'exact:１２12'
assert_text "⌥T 繁简切换"     'opt+t;xuexi '          'exact:學習'
assert_text "⌥T 切回简体"     'opt+t;xuexi '          'exact:学习'
assert_text "⌥M 模式循环"     'opt+m;opt+m;opt+m;wq ' 'unicode:'

# 3. 性能与网络（不再依赖客户端矩阵；矩阵已移除）
PERF=$(ROUNDS="${ROUNDS:-10}" SETTLE="${SETTLE:-20}" OUT="$OUT/perf" "$PROBE/perf-session.sh" 2>/dev/null | tail -1)
case "$PERF" in
    *'"result": "PASS"'*) report "性能/网络" "PASS $(printf '%s' "$PERF" | head -c 160)" ;;
    *'"result": "BLOCKED"'*) report "性能/网络" "BLOCKED $(printf '%s' "$PERF" | head -c 160)"; BLOCKED=1 ;;
    *) report "性能/网络" "FAIL $(printf '%s' "$PERF" | head -c 160)"; FAILED=1 ;;
esac

# 4. 久用（可选）：SOAK_MINUTES>0 时追加
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

python3 -c 'import json,sys
failed, blocked = int(sys.argv[1]), int(sys.argv[2])
result = "FAIL" if failed else ("SKIP" if blocked else "PASS")
print(json.dumps({"result": result, "evidence_dir": sys.argv[3]}, ensure_ascii=False))' "$FAILED" "$BLOCKED" "$OUT"
[ "$FAILED" -ne 0 ] && exit 1
[ "$BLOCKED" -ne 0 ] && exit 78
exit 0
