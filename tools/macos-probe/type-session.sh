#!/bin/sh
# 一次可复现的键入会话：起测试窗口 → 等它成为前台 → 投递按键（带前台校验与重试）→ 回读上屏文本。
# 报告188/189：`--hid` 投递面向"当前前台应用"，因此必须确认目标窗口就是前台，否则按键会落到别处。
# 用法：type-session.sh '<按键串>' [--settle 秒] [--source <输入源 id>]
set -u
PROBE="$(cd "$(dirname "$0")" && pwd)"
BIN="$PROBE/bin"
SOURCE="cn.jokerhub.inputmethod.Lampyris.default"
SETTLE=10
KEYS=""

while [ $# -gt 0 ]; do
    case "$1" in
        --settle) SETTLE="$2"; shift 2 ;;
        --source) SOURCE="$2"; shift 2 ;;
        *) KEYS="$1"; shift ;;
    esac
done
[ -n "$KEYS" ] || { echo "usage: type-session.sh '<keys>' [--settle N] [--source id]"; exit 2; }

OUT="$(mktemp -t imetype-out)"; rm -f "$OUT"
open -n /tmp/lampyris-imetype.app --args --source "$SOURCE" --keys "" --settle "$SETTLE" --delay 1.0 --out "$OUT"
PID=""
i=0
while [ $i -lt 20 ]; do
    PID=$(pgrep -f "out $OUT" | head -1)
    [ -n "$PID" ] && break
    i=$((i + 1)); sleep 0.5
done
[ -n "$PID" ] || { echo "BLOCKED 测试窗口未启动"; exit 1; }

# 首个按键会被窗口激活吞掉，先用一次纯修饰键"点一下"窗口
i=0
while [ $i -lt 15 ]; do
    "$BIN/keytopid" "$PID" 'ctrl' 150 400 --hid >/dev/null 2>&1 && break
    i=$((i + 1)); sleep 0.7
done
[ $i -lt 15 ] || { echo "BLOCKED 测试窗口未取得前台（激活键未投递）"; exit 1; }
sleep 0.6

i=0
while [ $i -lt 15 ]; do
    "$BIN/keytopid" "$PID" "$KEYS" 200 700 --hid >/dev/null 2>&1 && break
    i=$((i + 1)); sleep 0.7
done
[ $i -lt 15 ] || { echo "BLOCKED 测试窗口未取得前台（按键未投递）"; exit 1; }

j=0
while [ $j -lt 60 ]; do
    [ -s "$OUT" ] && break
    j=$((j + 1)); sleep 0.5
done
python3 - "$OUT" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    print("BLOCKED 无回读结果"); raise SystemExit(1)
print(json.dumps({"text": data.get("text"), "keys_seen": data.get("keys_seen"),
                  "current_source": data.get("current_source"),
                  "has_non_ascii": data.get("has_non_ascii")}, ensure_ascii=False))
PY
rm -f "$OUT"
