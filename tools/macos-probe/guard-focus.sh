#!/bin/bash
# 发键前的焦点闸门：前台应用不是目标就立刻退出（报告 099 的教训——验收中别的前台应用抢焦点会把按键送进真实会话）。
# 用法：guard-focus.sh "TextEdit" [更多可接受名字...]
set -u
[ "$#" -ge 1 ] || { echo "用法：$0 <期望前台应用名> [...]" >&2; exit 2; }
front=$(/usr/bin/osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null)
for want in "$@"; do
  [ "$front" = "$want" ] && { echo "focus=$front ok"; exit 0; }
done
echo "BLOCKED 前台是「${front}」，期望：$*" >&2
exit 3
