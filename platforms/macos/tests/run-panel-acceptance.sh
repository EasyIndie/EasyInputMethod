#!/usr/bin/env bash
# 萤火虫 macOS 面板验收（⑦用户词库 / ⑧导入导出 / ⑨拼音反查）—— 真机 AX 自动化。
#
# 前提：图形登录会话；萤火虫已安装并在输入源里启用；运行本脚本的终端已获「辅助功能」授权。
# 行为：打开「偏好设置」→ 词库 分区，逐项自动点击；结束恢复用户词库并重启宿主。
#
# 用法：./platforms/macos/tests/run-panel-acceptance.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORK="$(mktemp -d)"
DICT="$HOME/Library/Application Support/Lampyris/user-dictionary.tsv"
BAK="$WORK/user-dictionary.bak"
EXPORT="$HOME/Documents/lampyris-panel-export.tsv"
BADFILE="$HOME/Documents/lampyris-panel-bad.tsv"
PASS=0
FAIL=0

source "${ROOT}/platforms/macos/tests/lib-imk-auto.sh"

cleanup() {
    # 还原词库文件（热杀宿主风险高、不采用；内存中的测试词会在宿主下次自然重启后消失）。
    [ -f "$BAK" ] && cp "$BAK" "$DICT" 2>/dev/null
    rm -f "$EXPORT" "$BADFILE"
    close_panel_windows
    rm -rf "$WORK"
}
trap cleanup EXIT

wait_for() {
    local pat="$1" tries="${2:-25}" i
    for ((i = 1; i <= tries; i++)); do
        aui dump "$BUNDLE" 2>/dev/null | grep -q "$pat" && return 0
        sleep 0.3
    done
    return 1
}

echo "▶ 编译 imk-auto"
imk_auto_build || { echo "❌ 编译失败（需命令行工具链 swiftc）" >&2; exit 1; }

echo "▶ 前置检查：萤火虫输入源 + 宿主存活"
aui select >/dev/null 2>&1 || { echo "❌ 未找到萤火虫输入源（先在系统设置里添加）" >&2; exit 1; }
sleep 0.4
require_host || exit 1

[ -f "$DICT" ] && cp "$DICT" "$BAK"

echo "▶ 清理可能残留的面板/弹窗"
close_panel_windows
sleep 0.4

echo "▶ 打开偏好设置面板 → 词库 分区"
aui menu "偏好设置" >/dev/null 2>&1
wait_for "萤火虫 · 偏好设置" || { echo "❌ 设置面板未打开" >&2; exit 1; }
aui press-desc "$BUNDLE" "词库" >/dev/null 2>&1
sleep 0.6
aui dump "$BUNDLE" | grep -q "新增词条" || { echo "❌ 未进入词库分区" >&2; exit 1; }

echo "▶ ⑦ 新增词条"
before="$(wc -l < "$DICT" 2>/dev/null || echo 0)"
aui press "$BUNDLE" "新增词条…" >/dev/null 2>&1
wait_for "新增用户词条" || { echo "❌ 新增词条弹窗未出现" >&2; exit 1; }
aui set "$BUNDLE" "" "lpys" >/dev/null 2>&1
aui set "$BUNDLE" "" "面板验收词" >/dev/null 2>&1
sleep 0.3
aui press "$BUNDLE" "添加" >/dev/null 2>&1
sleep 1.2
after="$(wc -l < "$DICT" 2>/dev/null || echo 0)"
grep -q "面板验收词" "$DICT" && ok "用户词库新增落盘（$before → $after 行）" || no "新增词条未落盘"

echo "▶ ⑧ 导出 / 导入 / 坏文件"
rm -f "$EXPORT"
aui press "$BUNDLE" "导出用户词库…" >/dev/null 2>&1
wait_for "lampyris-user-dictionary" || { echo "❌ 保存面板未就绪" >&2; exit 1; }
# 保存框默认名可能带 .tsv 后缀，动态读当前值再改名。
cur="$(aui dump "$BUNDLE" | awk -F'\t' '$1 == "AXTextField" && $3 ~ /^lampyris-user-dictionary/ { print $3; exit }')"
if [ -n "$cur" ]; then
    aui set "$BUNDLE" "$cur" "lampyris-panel-export.tsv" >/dev/null 2>&1
else
    no "未找到导出文件名框"
fi
sleep 0.3
aui press "$BUNDLE" "保存" >/dev/null 2>&1
sleep 1.2
[ -s "$EXPORT" ] && ok "导出文件已生成（$(wc -l < "$EXPORT") 行）" || no "导出文件缺失"

aui press "$BUNDLE" "导入用户词库…" >/dev/null 2>&1
wait_for "打开" || { echo "❌ 打开面板未出现" >&2; exit 1; }
open_file_in_panel "lampyris-panel-export.tsv" && ok "打开面板已定位导出文件" || no "未找到导出文件行"
sleep 1.2
# 成功导入不应弹错误弹窗
aui dump "$BUNDLE" | grep -q "用户词库操作失败" && no "合法导入弹出了错误" || ok "合法导入无错误"

printf '这是一行胡说八道\n' > "$BADFILE"
lines_before="$(wc -l < "$DICT" 2>/dev/null || echo 0)"
aui press "$BUNDLE" "导入用户词库…" >/dev/null 2>&1
wait_for "打开" || { echo "❌ 打开面板未出现" >&2; exit 1; }
open_file_in_panel "lampyris-panel-bad.tsv" || true
sleep 1.2
if wait_for "用户词库操作失败" 10; then
    ok "坏文件被拒（弹「用户词库操作失败」）"
    aui press "$BUNDLE" "好" >/dev/null 2>&1 || true
    sleep 0.4
else
    no "坏文件未弹错误"
fi
lines_after="$(wc -l < "$DICT" 2>/dev/null || echo 0)"
check_eq "坏文件导入后原词库不变" "$lines_after" "$lines_before"

echo "▶ ⑨ 拼音反查"
aui press "$BUNDLE" "拼音反查…" >/dev/null 2>&1
wait_for "拼音反查" || { echo "❌ 反查弹窗未出现" >&2; exit 1; }
aui set "$BUNDLE" "" "你好" >/dev/null 2>&1
sleep 0.3
aui press "$BUNDLE" "查询" >/dev/null 2>&1
sleep 1.0
if aui dump "$BUNDLE" | grep -q "ni hao"; then
    ok "拼音反查 你好 -> ni hao"
else
    no "拼音反查未得到 ni hao"
fi
aui press "$BUNDLE" "好" >/dev/null 2>&1 || true

echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
