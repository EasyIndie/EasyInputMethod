#!/bin/sh
# 验收收尾清理（报告231；2026-11-14 收敛）：只回收**探针自己开出来**的窗口/进程，绝不动用户的文档。
#
# 归属判定（宁可留一个窗口，也不误关用户的东西）：
#   - TextEdit：只关"无路径（未保存）+ 内容命中探针输出"的文档；用户若有未保存文档，内容不会命中
#   - 进程：`lampyris-imetype.app` 测速窗口、残留 `keytopid`
#
# Safari / Chrome / Xcode 自动化验收已在 2026-11-14 移除：它们不是系统自带、依赖第三方安装，
# 且清理需要按 URL/标题认领窗口，收益不足以抵消维护成本。现在验收只依赖系统自带 TextEdit
# 与自建 imetype 测试窗口。
#
# 用法：cleanup-windows.sh [--out DIR] [--textedit] [--quit-app NAME]... [--processes-only] [--dry-run]
#   --textedit 才会清理未保存的 TextEdit 文档（按内容签名认领），默认不动 TextEdit。
#   --quit-app 只对"本轮由我们启动、且已没有任何窗口"的 TextEdit/Terminal 使用。
set -u
PROBE="$(cd "$(dirname "$0")" && pwd)"
BIN="$PROBE/bin"
OUT=""
DRY=0
TEXTEDIT=0
QUIT_APPS=""
PROCESSES_ONLY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --out) OUT="$2"; shift 2 ;;
        --dry-run) DRY=1; shift ;;
        --textedit) TEXTEDIT=1; shift ;;
        --quit-app) QUIT_APPS="$QUIT_APPS $2"; shift 2 ;;
        --processes-only) PROCESSES_ONLY=1; shift ;;
        *) shift ;;
    esac
done

run() { [ "$DRY" = "1" ] && { echo "DRY $*"; return 0; }; "$@"; }

# 只在应用已经在跑时才发 AppleScript：`tell application "X"` 对未启动的应用是"启动它"。
is_running() { pgrep -x "$1" >/dev/null 2>&1; }
say() { printf '%-22s %s\n' "$1" "$2"; }

# —— TextEdit：只关未保存且内容命中探针输出的文档 ——
TE_SIGNATURES="你你好。 你 你好 中华人民共和国 你好。 你好， ‘ 的 中国 abc 你你好学习。 你好世界。 你学习你好。 人民。 时间。 你好你好你好你好你 你好，，， １２12 學習 学习 你abc"
clean_textedit() {
    is_running TextEdit || { say "TextEdit" "skipped (not running)"; return 0; }
    if [ "$DRY" = "1" ]; then
        echo "DRY close untitled TextEdit documents whose text matches probe signatures"
        return 0
    fi
    closed=$(osascript -e '
on run argv
    set sigs to argv
    set closedCount to 0
    tell application "TextEdit"
        repeat with d in (every document)
            try
                set p to ""
                try
                    set p to (path of d) as text
                end try
                if p is "" then
                    set bodyText to (text of d) as text
                    if sigs contains bodyText then
                        close d saving no
                        set closedCount to closedCount + 1
                    end if
                end if
            end try
        end repeat
    end tell
    return closedCount
end run' $TE_SIGNATURES 2>/dev/null | tr -d -c '0-9')
    say "TextEdit" "closed_docs=${closed:-0}"
    # 关掉最后一个文档后 TextEdit 会再开一个空白窗口；若剩下的全是"空且未保存"的文档，
    # 说明本轮没留下任何内容，直接退出 TextEdit（不含任何用户内容，代价只是窗口消失）。
    remain=$(osascript -e 'tell application "TextEdit"
set dirty to 0
set total to 0
repeat with d in (every document)
    set total to total + 1
    try
        set p to ""
        try
            set p to (path of d) as text
        end try
        set bodyText to (text of d) as text
        if (p is not "") or (bodyText is not "") then set dirty to dirty + 1
    on error
        set dirty to dirty + 1
    end try
end repeat
if total is 0 then return "none"
if dirty is 0 then
    quit saving no
    return "quit:" & total
end if
return "kept:" & (total - dirty)
end tell' 2>/dev/null)
    say "TextEdit" "leftover=${remain:-unknown}"
}

# —— 进程：本轮由我们启动且已无窗口的 TextEdit/Terminal ——
quit_started_apps() {
    for app in $QUIT_APPS; do
        [ -n "$app" ] || continue
        case "$app" in TextEdit|Terminal) ;; *) say "$app" "not-managed"; continue ;; esac
        is_running "$app" || { say "$app" "already gone"; continue; }
        windows=$("$BIN/axclose" "$app" 2>/dev/null | grep -c '^WINDOW' || true)
        if [ "${windows:-0}" -gt 0 ]; then
            say "$app" "kept ($windows window(s))"
            continue
        fi
        if [ "$DRY" = "1" ]; then
            echo "DRY quit $app (no windows left)"
        else
            osascript -e "tell application \"$app\" to quit saving no" >/dev/null 2>&1
            say "$app" "quit"
        fi
    done
}

kill_probes() {
    if [ "$DRY" = "1" ]; then
        echo "DRY pkill lampyris-imetype.app / keytopid leftovers"
        return 0
    fi
    n=0
    for pattern in 'lampyris-imetype.app/Contents/MacOS/imetype' "$BIN/keytopid"; do
        pids=$(pgrep -f "$pattern" 2>/dev/null | tr '\n' ' ')
        [ -z "$pids" ] && continue
        kill $pids 2>/dev/null
        n=$((n + $(echo "$pids" | wc -w | tr -d ' ')))
    done
    say "processes" "killed=$n"
}

say "cleanup" "out=${OUT:-<none>} dry_run=$DRY processes_only=$PROCESSES_ONLY"
if [ "$PROCESSES_ONLY" = "1" ]; then
    kill_probes
    say "cleanup" "done (processes only)"
    exit 0
fi
[ "$TEXTEDIT" = "1" ] && clean_textedit
quit_started_apps
kill_probes
say "cleanup" "done"
