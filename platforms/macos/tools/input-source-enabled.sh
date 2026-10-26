#!/bin/sh
# 回读「输入源是否真的启用」：macOS 13 上 `TISEnableInputSource` 会返回 0 但源并未启用（报告201/207），
# 所以安装脚本不能用系统调用返回值宣布成功，必须回读一次。
# 用法：input-source-enabled.sh <LampyrisTIS> <bundleID>；启用返回 0，未启用返回 1，调用方式错误返回 2。
set -u
[ "$#" -eq 2 ] || { echo "用法：$0 <LampyrisTIS> <bundleID>" >&2; exit 2; }
HELPER="$1"
IDENTIFIER="$2"
[ -n "${IDENTIFIER}" ] || exit 2
[ -x "${HELPER}" ] || exit 2
# `LampyrisTIS status` 打印：enabled <id1>,<id2>
"${HELPER}" status "${IDENTIFIER}" 2>/dev/null |
    sed -n 's/^enabled //p' |
    tr ',' '\n' |
    grep -qxF "${IDENTIFIER}"
