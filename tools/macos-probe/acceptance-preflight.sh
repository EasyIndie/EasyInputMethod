#!/bin/sh
# 自动化验收的前置检查（报告193）：判断当前机器能否跑 `acceptance-auto.sh`。
# 退出码：0 = 可以跑；78 = 环境不具备（例如 CI runner 没有图形会话/未装输入法），调用方应当 SKIP 而不是 FAIL。
# 输出一行 JSON，便于 CI 与脚本判读。
set -u
PROBE="$(cd "$(dirname "$0")" && pwd)"
BIN="$PROBE/bin"
APP="${HOME}/Library/Input Methods/Lampyris.app"
SOURCE="${SOURCE:-cn.jokerhub.inputmethod.Lampyris.default}"

ready=true
detail=""

check() { # name ok-message fail-message
    if [ "$2" = "ok" ]; then detail="$detail\"$1\":\"ok\","; else detail="$detail\"$1\":\"$3\","; ready=false; fi
}

[ -x "$APP/Contents/MacOS/Lampyris" ] && check installed ok "" || check installed fail "未安装输入法"
[ -n "$(pgrep -x Lampyris | head -1)" ] && check host ok "" || check host fail "宿主未运行"
"$BIN/tissrc" list 2>/dev/null | grep -qx "enabled ${SOURCE}" \
    && check input_source ok "" || check input_source fail "输入源未启用"
front=$(osascript -e 'tell application "System Events" to name of first application process whose frontmost is true' 2>/dev/null)
[ -n "$front" ] && check gui_session ok "" || check gui_session fail "无图形会话（无法取前台应用）"
[ -x "$BIN/imetype" ] && check probe_built ok "" || check probe_built fail "探针未构建"
if [ -x "$BIN/imetype" ] && [ ! -x "$BIN/axfocus" ]; then check ax_probe fail "缺少 axfocus"; fi
[ -d /tmp/lampyris-imetype.app ] || { [ -x "$BIN/imetype" ] && "$PROBE/build-imetype-app.sh" >/dev/null 2>&1; }
[ -d /tmp/lampyris-imetype.app ] && check test_app ok "" || check test_app fail "测试 App 未生成"

detail="${detail%,}"
if [ "$ready" = "true" ]; then
    printf '{"ready":true,"checks":{%s},"exec_sha":"%s"}\n' "$detail" \
        "$(shasum -a 256 "$APP/Contents/MacOS/Lampyris" | awk '{print $1}')"
    exit 0
fi
printf '{"ready":false,"checks":{%s}}\n' "$detail"
exit 78
