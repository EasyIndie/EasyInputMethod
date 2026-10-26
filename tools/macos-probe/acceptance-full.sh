#!/bin/sh
# 一条命令跑完单机验收（报告212 B）：preflight → 自动验收 → 质量样本 → 内存门禁 → 网络采样 → 汇总 JSON。
#
# 为什么要有它：之前一轮要记 4 条命令、各自判读输出，两台机器还要串行来回切；
# 报告207/209 都出现过「漏跑一项」「看错输出」的返工。这里把顺序、判读与汇总固化。
#
# 用法：acceptance-full.sh [OUT=/tmp/...] [SKIP_MEMORY=1] [SKIP_SOAK=1] [MINUTES=5]
#   SKIP_MEMORY=1  跳过 ADR-263 内存门禁（它会**重启宿主**，需单独授权）
#   SKIP_SOAK=1    跳过久用（默认就跳过；SOAK_MINUTES 显式设置时才跑，且会写用户词库）
# 退出码：0 全通过；1 有 FAIL；78 环境不具备（BLOCKED/SKIP，调用方不应记 FAIL）。
set -u
PROBE="$(cd "$(dirname "$0")" && pwd)"
BIN="$PROBE/bin"
OUT="${OUT:-/tmp/lampyris-acceptance-full-$(date -u +%Y%m%dT%H%M%SZ)}"
SKIP_MEMORY="${SKIP_MEMORY:-0}"
SKIP_SOAK="${SKIP_SOAK:-1}"
mkdir -p "$OUT"

say() { printf '%-22s %s\n' "$1" "$2"; }

# 1. 前置：装没装、宿主、锁屏、多实例、输入源、探针
"$PROBE/acceptance-preflight.sh" > "$OUT/00-preflight.json" 2>&1
preflight=$?
cat "$OUT/00-preflight.json"
if [ "$preflight" -eq 78 ]; then
    say "preflight" "BLOCKED（见 00-preflight.json）"
    printf '{"result":"BLOCKED","out":"%s"}\n' "$OUT"
    exit 78
fi
[ "$preflight" -eq 0 ] || { say "preflight" "FAIL rc=$preflight"; printf '{"result":"FAIL","out":"%s"}\n' "$OUT"; exit 1; }

failed=0
record() { # name status detail
    printf '%-22s %s\n' "$1" "$2"
    # TSV 而不是 JSON：各步骤自己输出 JSON，嵌进 JSON 里要转义，容易写坏（报告212 的实施笔记）。
    printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$OUT/steps.tsv"
}

# 2. 热键/上屏 + 客户端矩阵 + 性能/网络
acceptance_out=$(OUT="$OUT/auto" ROUNDS="${ROUNDS:-10}" "$PROBE/acceptance-auto.sh" 2>&1); auto_rc=$?
printf '%s\n' "$acceptance_out" > "$OUT/01-auto.log"
if [ "$auto_rc" -eq 0 ]; then
    record auto-acceptance PASS "$(printf '%s' "$acceptance_out" | tail -1)"
else
    record auto-acceptance FAIL "rc=${auto_rc} $(printf '%s' "$acceptance_out" | tail -1)"
    failed=1
fi

# 3. 质量样本（16 项）
quality_out=$(OUT="$OUT/quality" "$PROBE/quality-samples.sh" 2>&1); quality_rc=$?
printf '%s\n' "$quality_out" > "$OUT/02-quality.log"
if [ "$quality_rc" -eq 0 ]; then
    record quality-samples PASS "$(printf '%s' "$quality_out" | tail -1)"
elif [ "$quality_rc" -eq 78 ]; then
    record quality-samples BLOCKED "$(printf '%s' "$quality_out" | tail -1)"
    failed=1
else
    record quality-samples FAIL "$(printf '%s' "$quality_out" | tail -1)"
    failed=1
fi

# 4. 内存门禁（ADR-263/292，判定用私有已提交；会重启宿主）
if [ "$SKIP_MEMORY" = "1" ]; then
    record memory-gate SKIPPED "SKIP_MEMORY=1"
else
    memory_out=$(OUT="$OUT/memory" "$PROBE/memory-gate.sh" 2>&1); memory_rc=$?
    printf '%s\n' "$memory_out" > "$OUT/03-memory.log"
    verdict=$(printf '%s' "$memory_out" | grep -o '"result": *"[A-Z]*"' | tail -1)
    if [ "$memory_rc" -eq 0 ]; then
        record memory-gate PASS "$verdict"
    else
        record memory-gate FAIL "rc=${memory_rc} ${verdict}"
        failed=1
    fi
fi

# 5. 久用（默认跳过：会写真实用户词库，属需要单独决定是否跑的一项）
if [ "$SKIP_SOAK" = "1" ]; then
    record soak SKIPPED "默认跳过（MINUTES=… SOAK_MINUTES=… 才跑）"
else
    soak_out=$(MINUTES="${MINUTES:-5}" OUT="$OUT/soak" "$PROBE/soak-session.sh" 2>&1); soak_rc=$?
    printf '%s\n' "$soak_out" > "$OUT/04-soak.log"
    if [ "$soak_rc" -eq 0 ]; then
        record soak PASS "$(printf '%s' "$soak_out" | tail -1)"
    else
        record soak FAIL "rc=${soak_rc} $(printf '%s' "$soak_out" | tail -1)"
        failed=1
    fi
fi

# 6. 收尾状态：身份/配置/词库/输入源/连接数（写报告时直接引用）
host=$(pgrep -f 'Input Methods/Lampyris.app/Contents/MacOS/Lampyris' | head -1)
{
    echo "exec_sha=$(shasum -a 256 "${HOME}/Library/Input Methods/Lampyris.app/Contents/MacOS/Lampyris" 2>/dev/null | awk '{print $1}')"
    echo "build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "${HOME}/Library/Input Methods/Lampyris.app/Contents/Info.plist" 2>/dev/null)"
    echo "host_pid=${host:-none}"
    echo "config_sha=$(shasum -a 256 "${HOME}/Library/Application Support/Lampyris/config.toml" 2>/dev/null | awk '{print $1}')"
    echo "dict_lines=$(wc -l < "${HOME}/Library/Application Support/Lampyris/user-dictionary.tsv" 2>/dev/null | tr -d ' ')"
    echo "connections=$([ -n "${host}" ] && lsof -nP -p "${host}" 2>/dev/null | grep -cE 'TCP|UDP' || echo 0)"
    "$BIN/tissrc" list 2>/dev/null | tail -1
    echo "now=$(date -u +%FT%TZ)"
} > "$OUT/99-state.txt"

printf '\n'
if [ "$failed" -eq 0 ]; then
    say "总结果" "PASS"
    printf '{"result":"PASS","out":"%s"}\n' "$OUT"
    exit 0
fi
say "总结果" "FAIL（见 $OUT/steps.tsv）"
printf '{"result":"FAIL","out":"%s"}\n' "$OUT"
exit 1
