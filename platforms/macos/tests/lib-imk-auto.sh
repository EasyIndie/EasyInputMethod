#!/usr/bin/env bash
# 萤火虫 macOS 自动化测试共享库。
#
# 被 `run-panel-acceptance.sh`（⑦⑧⑨）与 `run-input-apps.sh`（⑩）source。
# 调用方需先定义 ROOT（仓库根）与 WORK（临时目录）；本库负责编译并调用 `imk-auto`。
#
# 依赖：图形登录会话、终端已授权「辅助功能」、萤火虫已安装并启用。

: "${ROOT:?ROOT 未设置（请在 source 前定义仓库根）}"
: "${WORK:?WORK 未设置（请在 source 前定义临时目录）}"

BUNDLE="cn.jokerhub.inputmethod.Lampyris"
IMK_AUTO="${WORK}/imk-auto"

# 编译一次性辅助工具（-warnings-as-errors 对齐零诊断门禁）。
imk_auto_build() {
    swiftc -O -warnings-as-errors "${ROOT}/platforms/macos/tests/imk-auto.swift" -o "${IMK_AUTO}"
}

# 调用辅助工具：aui <subcommand> ...
aui() { "${IMK_AUTO}" "$@"; }

# 发送物理键码，默认等 0.4s。
keycode() {
    osascript -e "tell application \"System Events\" to key code $1" >/dev/null 2>&1
    sleep "${2:-0.4}"
}

# 逐字符发送按键（仅 ASCII；中文由输入法组合产生）。
type_text() {
    local text="$1" i
    for ((i = 0; i < ${#text}; i++)); do
        osascript -e "tell application \"System Events\" to keystroke \"${text:$i:1}\"" >/dev/null 2>&1
        sleep 0.13
    done
}

# 选中萤火虫输入源。
select_ime() {
    aui select >/dev/null 2>&1
    sleep 0.4
}

# 前台 App 名（本地化）。
frontmost_name() { aui frontmost; }

# 把指定 bundle 的 App 前置并等待。
activate_app() {
    aui activate "$1" >/dev/null 2>&1
    sleep "${2:-1.0}"
}

# 通过剪贴板读取当前聚焦文本框内容（适用于不暴露 AX 的 App，如微信）。
# 先清空剪贴板，再 Cmd+A / Cmd+C，避免读到旧值。
field_read_clipboard() {
    printf '' | pbcopy
    osascript -e 'tell application "System Events" to keystroke "a" using command down' >/dev/null 2>&1
    sleep 0.25
    osascript -e 'tell application "System Events" to keystroke "c" using command down' >/dev/null 2>&1
    sleep 0.35
    pbpaste
}

# 清空当前聚焦文本框（Cmd+A + Delete），不触发发送。
field_clear() {
    osascript -e 'tell application "System Events" to keystroke "a" using command down' >/dev/null 2>&1
    sleep 0.2
    keycode 51 0.2
}

# 宿主是否存活。
host_running() { pgrep -x Lampyris >/dev/null; }

# 前置：宿主必须已加载（否则 IME 菜单与输入都不可用）。
# 热杀宿主后需重新激活输入源/重启客户端才能恢复（HANDOFF 已知坑），故本库不提供重启。
require_host() {
    host_running && return 0
    echo "❌ 宿主未运行：请先在一次文本输入中激活「萤火虫」（或在系统设置里重选输入源）后重试。" >&2
    return 1
}

# 关闭萤火虫打开的弹窗/面板（常见按钮 + AX 关闭按钮兜底）；保留其它窗口。
close_panel_windows() {
    local i
    for ((i = 0; i < 4; i++)); do
        aui press "$BUNDLE" "取消" >/dev/null 2>&1
        aui press "$BUNDLE" "好" >/dev/null 2>&1
        aui press "$BUNDLE" "确定" >/dev/null 2>&1
    done
    aui close-windows "$BUNDLE" >/dev/null 2>&1
}

# 在已打开的「打开」面板里双击选中文件名对应的行（AX 坐标定位）。
# 用法：open_file_in_panel <文件名>
open_file_in_panel() {
    local name="$1" line pos x y
    line="$(aui dump "$BUNDLE" | awk -F'\t' -v n="$name" '$3 == n { print; exit }')"
    [ -n "$line" ] || return 1
    pos="$(printf '%s' "$line" | awk -F'\t' '{ print $5 }')"
    x=$(( ${pos%,*} + 60 ))
    y=$(( ${pos#*,} + 8 ))
    aui click "$x" "$y" >/dev/null
    sleep 0.12
    aui click "$x" "$y" >/dev/null
}

# 断言辅助：ok/no 计数。
ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
no() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); }
check_eq() { [ "$2" = "$3" ] && ok "$1 -> '$3'" || no "$1 -> 期望'$3' 实际'$2'"; }
check_contains() { printf '%s' "$2" | grep -q "$3" && ok "$1 (含 $3)" || no "$1 (缺 $3)：$2"; }
