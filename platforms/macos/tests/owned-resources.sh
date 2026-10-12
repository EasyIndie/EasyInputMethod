#!/usr/bin/env bash
# Only IDs returned by resource creation may enter this registry.
OWNED_APPS=()
OWNED_KINDS=()
OWNED_IDS=()
OWNED_FILES=()
OWNED_NAMES=()
OWNED_TEXTEDIT_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/owned-textedit.applescript"

owned_record() {
    local app="$1" kind="$2" id="$3"
    case "$app:$kind" in
        'TextEdit:window'|'Google Chrome:window'|'Safari:window'|'Terminal:window') ;;
        *) echo 'BLOCKED 未识别的测试资源类型' >&2; return 1 ;;
    esac
    case "$id" in ''|*[!0-9]*) echo 'BLOCKED 无法取得测试对象 ID；保留资源供人工检查' >&2; return 1 ;; esac
    if [ "$app" = TextEdit ] && { [ -z "${OWNED_FILE:-}" ] || [ -z "${OWNED_NAME:-}" ]; }; then
        echo 'BLOCKED TextEdit未绑定测试文件身份' >&2; return 1
    fi
    OWNED_FILES+=("${OWNED_FILE:-}")
    OWNED_NAMES+=("${OWNED_NAME:-}")
    OWNED_APPS+=("$app")
    OWNED_KINDS+=("$kind")
    OWNED_IDS+=("$id")
    OWNED_APP="$app"
    OWNED_KIND="$kind"
    OWNED_ID="$id"
}

owned_cleanup() {
    local i app kind id failed="${OWNED_CREATE_FAILED:-0}"
    for ((i = ${#OWNED_IDS[@]} - 1; i >= 0; i--)); do
        app="${OWNED_APPS[$i]}"; kind="${OWNED_KINDS[$i]}"; id="${OWNED_IDS[$i]}"
        # Closed/missing objects never fall back to the frontmost object.
        if [ "$app" = 'TextEdit' ]; then
            osascript "$OWNED_TEXTEDIT_SCRIPT" close "${OWNED_FILES[$i]}" "${OWNED_NAMES[$i]}" "$id" >/dev/null 2>&1 || failed=1
        else
            osascript -e "tell application \"$app\" to close $kind id $id" >/dev/null 2>&1 || true
        fi
    done
    [ "$failed" = 0 ] || { echo "BLOCKED TextEdit资源清理失败；保留临时文件" >&2; return 1; }
}

owned_textedit_create() {
    local id directory
    [ -d "${WORK:-}" ] || { echo 'BLOCKED 未提供测试工作目录' >&2; return 1; }
    directory="$(mktemp -d "$WORK/textedit.XXXXXX")" || return 1
    OWNED_NAME="$(basename "$directory").txt"
    OWNED_FILE="$directory/$OWNED_NAME"
    (umask 077; : > "$OWNED_FILE") || return 1
    id="$(osascript "$OWNED_TEXTEDIT_SCRIPT" create "$OWNED_FILE" "$OWNED_NAME")" || {
        OWNED_CREATE_FAILED=1
        echo "BLOCKED TextEdit创建未验证；保留：$directory" >&2
        return 1
    }
    owned_record TextEdit window "$id" || {
        OWNED_CREATE_FAILED=1
        echo "BLOCKED TextEdit身份登记失败；保留：$directory" >&2
        return 1
    }
}

# Guard and action share one AppleScript invocation. No automatic refocus.
owned_do() {
    local operation="$1" argument="${2:-}" statement text_guard="" role
    [ -n "${OWNED_ID:-}" ] || { echo 'BLOCKED 未登记输入目标' >&2; exit 1; }
    case "$OWNED_APP" in
        TextEdit|Terminal) role=AXTextArea ;;
        'Google Chrome'|Safari) role=AXTextField ;;
        *) echo 'BLOCKED 未识别输入目标' >&2; exit 1 ;;
    esac
    case "$operation" in
        char)
            case "$argument" in [a-z]) ;; *) echo 'BLOCKED 非测试字符' >&2; exit 1 ;; esac
            statement="tell application \"System Events\" to keystroke \"$argument\""
            ;;
        key)
            case "$argument" in 49|18|53|13|12) ;; *) echo 'BLOCKED 非测试键码' >&2; exit 1 ;; esac
            statement="tell application \"System Events\" to key code $argument"
            ;;
        undo|address|copy|select-all|mode|source)
            case "$operation" in
                undo) argument=z ;; address) argument=l ;; copy) argument=c ;;
                select-all) argument=a ;; mode) argument=m ;; source) argument=space ;;
            esac
            case "$operation" in
                mode) statement='tell application "System Events" to keystroke "m" using {control down, shift down}' ;;
                source) statement='tell application "System Events" to key code 49 using {control down}' ;;
                *) statement="tell application \"System Events\" to keystroke \"$argument\" using command down" ;;
            esac
            ;;
        marked-range)
            [ "$OWNED_APP" = TextEdit ] || { echo 'BLOCKED 非TextEdit范围查询' >&2; exit 1; }
            statement='tell application "System Events" to tell process "TextEdit"
set targetArea to value of attribute "AXFocusedUIElement"
return value of attribute "AXTextInputMarkedRange" of targetArea
end tell'
            ;;
        read|clear)
            [ "$OWNED_APP" = TextEdit ] || { echo 'BLOCKED 非TextEdit文档动作' >&2; exit 1; }
            osascript "$OWNED_TEXTEDIT_SCRIPT" "$operation" "$OWNED_FILE" "$OWNED_NAME" "$OWNED_ID" || {
                echo 'BLOCKED TextEdit文档动作失败' >&2; exit 1;
            }
            return
            ;;
        *) echo 'BLOCKED 未识别测试动作' >&2; exit 1 ;;
    esac
    case "$operation" in
        address|read|clear) ;;
        *) text_guard="tell application \"System Events\" to tell process \"$OWNED_APP\"
set focusedRole to role of (value of attribute \"AXFocusedUIElement\")
if focusedRole is not \"$role\" then error \"BLOCKED 聚焦控件不符\"
end tell" ;;
    esac
    local identity=""
    if [ "$OWNED_APP" = TextEdit ]; then
        identity='set fixtureFile to (POSIX file (item 1 of argv)) as alias
set fixtureName to item 2 of argv
tell application "TextEdit"
if name of window id '"$OWNED_ID"' is not fixtureName then error "BLOCKED 测试窗口名称不符"
set matches to documents whose name is fixtureName
if (count of matches) is not 1 then error "BLOCKED 测试文档身份不唯一"
set targetDocument to item 1 of matches
set documentPath to get path of targetDocument
end tell
set documentFile to (POSIX file documentPath) as alias
if documentFile is not fixtureFile then error "BLOCKED 测试文档路径不符"'
    fi
    osascript -e "on run argv
with timeout of 5 seconds
$identity
tell application \"$OWNED_APP\"
if not frontmost then error \"BLOCKED 应用焦点不符\"
if (id of front $OWNED_KIND) is not $OWNED_ID then error \"BLOCKED 测试对象焦点不符\"
end tell
$text_guard
$statement
end timeout
end run" "${OWNED_FILE:-}" "${OWNED_NAME:-}" || {
        [ "$operation" != read ] || echo 'BLOCKED 读取目标失败'
        echo 'BLOCKED 目标身份或动作验证失败；停止验收' >&2
        exit 1
    }
}

owned_type() {
    local text="$1" i
    for ((i = 0; i < ${#text}; i++)); do
        owned_do char "${text:$i:1}"
        sleep 0.13
    done
}
