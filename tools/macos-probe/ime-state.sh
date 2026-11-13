#!/bin/sh
# 验收前的输入法状态归位与验收后的还原（报告232）。
#
# 为什么需要它：验收里会按 ⌥P/⌥F/⌥T/⌥M 切换状态。一旦某一项因为时序没切回来（实测踩到），
# 后面的用例全部连锁失败（"简化字期望、实得繁体"、甚至整个脚本跑在 ABC 上），
# 而且用户的真实偏好会被留在测试态。这个脚本负责：
#   --snapshot FILE   记录当前四项状态（供 --restore 使用）
#   --ensure          归位到验收需要的状态：mixed / chinese / half / simplified
#   --restore FILE    还原到快照里的值
# 任何一步收敛不了就退出 78（BLOCKED），不冒充 PASS/FAIL。
set -u
PROBE="$(cd "$(dirname "$0")" && pwd)"
BIN="$PROBE/bin"
SUPPORT="${SUPPORT:-$HOME/Library/Application Support/Lampyris}"
CONFIG="$SUPPORT/config.toml"
SOURCE="${SOURCE:-cn.jokerhub.inputmethod.Lampyris.default}"
TRIES="${TRIES:-4}"

field() { [ -f "$CONFIG" ] && grep -m1 "^$1" "$CONFIG" | sed 's/.*= *//; s/ *#.*//; s/"//g' || echo ""; }
state() { printf 'mode=%s punctuation=%s full_width=%s chinese_variant=%s\n' "$(field mode)" "$(field punctuation)" "$(field full_width)" "$(field chinese_variant)"; }

# 热键要落在一个真正在用输入法的窗口上：复用 type-session 的独立测试窗口（报告188/229）。
toggle() { "$PROBE/type-session.sh" "$1" --settle 3 >/dev/null 2>&1; }

ensure_source() {
    "$BIN/tissrc" select "$SOURCE" >/dev/null 2>&1
    sleep 0.6
    "$BIN/tissrc" list 2>/dev/null | grep '^current' | grep -q Lampyris
}

# 把某个字段切到目标值；模式是循环，所以允许最多 TRIES 次"切到目标为止"。
converge() { # field hotkey target
    name="$1"; hotkey="$2"; want="$3"
    n=0
    while [ "$(field "$name")" != "$want" ] && [ "$n" -lt "$TRIES" ]; do
        toggle "$hotkey"
        n=$((n + 1))
    done
    got=$(field "$name")
    if [ "$got" != "$want" ]; then
        echo "BLOCKED $name=$got（目标 ${want}，试了 ${n} 次）" >&2
        return 1
    fi
    return 0
}

case "${1:---ensure}" in
    --snapshot) state > "${2:?snapshot 需要一个输出文件}" ;;
    --restore)
        file="${2:?restore 需要快照文件}"
        [ -f "$file" ] || { echo "BLOCKED 快照文件不存在: $file" >&2; exit 78; }
        ensure_source || { echo "BLOCKED 无法选中输入源" >&2; exit 78; }
        for pair in "punctuation:opt+p" "full_width:opt+f" "chinese_variant:opt+t" "mode:opt+m"; do
            name="${pair%%:*}"; hotkey="${pair##*:}"
            want=$(sed -n "s/.*$name=\([^ ]*\).*/\1/p" "$file" | head -1)
            [ -n "$want" ] || continue
            converge "$name" "$hotkey" "$want" || exit 78
        done
        echo "RESTORED $(state)"
        ;;
    --ensure|*)
        ensure_source || { echo "BLOCKED 无法选中输入源（${SOURCE}）" >&2; exit 78; }
        converge punctuation opt+p chinese || exit 78
        converge full_width opt+f half || exit 78
        converge chinese_variant opt+t simplified || exit 78
        converge mode opt+m mixed || exit 78
        echo "ENSURED $(state)"
        ;;
esac
