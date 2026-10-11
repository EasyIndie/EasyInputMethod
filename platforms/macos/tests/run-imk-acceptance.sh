#!/usr/bin/env bash
# 萤火虫 macOS 实机自动验收（IMK 层）：打字 / 选字 / Esc / 来源标注 / 状态徽标 / 配置实时生效。
#
# 依赖与前提：
#   1) 图形登录会话；萤火虫已安装到 ~/Library/Input Methods/ 且已在系统输入源里启用；
#   2) 运行本脚本的**终端 App 已获「系统设置 → 隐私与安全性 → 辅助功能」授权**（发送按键所需）；
#   3) 全程只在新开的空 TextEdit 文档里输入，并会临时改 config.toml（结束自动还原）。
#
# 不覆盖（需人工/视觉）：三模式重启持久化、配置错误弹窗、词库面板增删导入导出、反查面板、
# 五应用稳定性、亮/暗主题。见 docs/tasks/MVP-05.md。
#
# 用法：./platforms/macos/tests/run-imk-acceptance.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORK="$(mktemp -d)"
CFG="$HOME/Library/Application Support/Lampyris/config.toml"
BAK="$WORK/config.toml.bak"
pass=0
fail=0

cleanup() {
  [ -f "$BAK" ] && cp "$BAK" "$CFG" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

echo "▶ 编译输入源选择器"
swiftc -O "$ROOT/platforms/macos/tests/im-select.swift" -o "$WORK/im-select" || {
  echo "❌ 编译 im-select 失败（需命令行工具链 swiftc）" >&2
  exit 1
}

echo "▶ 前置检查：选择萤火虫输入源"
if ! "$WORK/im-select" >/dev/null 2>&1; then
  echo "❌ 未找到/无法选择萤火虫输入源。请先安装并在系统设置里添加「萤火虫」。" >&2
  exit 1
fi

[ -f "$CFG" ] && cp "$CFG" "$BAK"

# --- 报告辅助 ---
ok() { echo "  PASS  $1"; pass=$((pass + 1)); }
no() { echo "  FAIL  $1"; fail=$((fail + 1)); }
check() { [ "$2" = "$3" ] && ok "$1 -> '$3'" || no "$1 -> 期望'$3' 实际'$2'"; }
grep_ok() { echo "$2" | grep -q "$3" && ok "$1 (含 $3)" || no "$1 (缺 $3)：$2"; }

sel() { "$WORK/im-select" >/dev/null 2>&1; }
text() { osascript -e 'tell application "TextEdit" to get text of front document' 2>/dev/null; }
begin() {
  osascript -e 'tell application "TextEdit" to activate' >/dev/null 2>&1
  osascript -e 'tell application "TextEdit" to set text of front document to ""' >/dev/null 2>&1
  sleep 0.3
  sel
  sleep 0.4
}
type_() { local s="$1" i; for ((i = 0; i < ${#s}; i++)); do
  osascript -e "tell application \"System Events\" to keystroke \"${s:$i:1}\"" >/dev/null 2>&1
  sleep 0.13
done; }
key() { osascript -e "tell application \"System Events\" to key code $1" >/dev/null 2>&1; sleep 0.5; }
cands() {
  osascript <<'OSA' 2>/dev/null
tell application "System Events" to tell process "Lampyris"
  set out to ""
  repeat with w in windows
    repeat with t in (static texts of w)
      set out to out & (value of t) & " | "
    end repeat
  end repeat
  return out
end tell
OSA
}

echo "▶ 准备 TextEdit 空文档"
osascript -e 'tell application "TextEdit" to activate' \
  -e 'tell application "TextEdit" to make new document' >/dev/null 2>&1
sleep 1.2

echo "▶ 辅助功能权限自检"
if osascript -e 'tell application "System Events" to keystroke "x"' >/dev/null 2>&1; then
  ok "可发送按键（辅助功能已授权）"
  key 53  # 取消可能的组合
else
  echo "  ⚠️  发送按键被拒：请到 系统设置 → 隐私与安全性 → 辅助功能 勾选你的终端 App 后重试。" >&2
  exit 1
fi

echo "▶ 验收用例"
begin; type_ "wq"; sleep 0.25; key 49; check "① 五笔 wq+空格" "$(text)" "你"
begin; type_ "nihao"; sleep 0.25; key 49; check "② 拼音 nihao+空格" "$(text)" "你好"
begin; type_ "wq"; sleep 0.25; key 18; check "③ 五笔 wq+数字1" "$(text)" "你"
begin; type_ "wq"; sleep 0.25; key 53; check "④ 五笔 wq+Esc 取消" "$(text)" ""
begin; type_ "shi"; sleep 0.8; c="$(cands)"; key 53
grep_ok "⑤ 来源标注-五笔" "$c" "五笔"
grep_ok "⑤ 来源标注-拼" "$c" "拼"
grep_ok "⑤ 状态徽标" "$c" "混输"

# ⑥ 配置实时生效：外部改 candidate.count（5→3），不按任何键
begin; type_ "w"; sleep 0.8
n1="$(cands | grep -oE '[1-9]\.' | wc -l | tr -d ' ')"
sed 's/^count = 5/count = 3/' "$CFG" > "$WORK/c.new" && mv "$WORK/c.new" "$CFG"
sleep 1.3
n2="$(cands | grep -oE '[1-9]\.' | wc -l | tr -d ' ')"
key 53
[ -f "$BAK" ] && cp "$BAK" "$CFG"
sleep 0.6
check "⑥ 配置实时生效(改前)" "$n1" "5"
check "⑥ 配置实时生效(改后无按键)" "$n2" "3"

# ⑪ 内存 / ⑫ 零外联（宿主进程）
pid="$(pgrep -x Lampyris | head -1)"
if [ -n "$pid" ]; then
  fp="$(vmmap -summary "$pid" 2>/dev/null | awk -F: '/Physical footprint:/{print $2}' | head -1 | tr -d ' ')"
  mb="$(echo "$fp" | sed 's/M//' | cut -d. -f1)"
  echo "  物理足迹: ${fp:-未知}"
  [ -n "${mb:-}" ] && [ "$mb" -le 30 ] && ok "⑪ 内存物理足迹 ≤30MB ($fp)" || no "⑪ 内存物理足迹 >30MB ($fp)"
  bad=0
  for _ in 1 2 3 4 5 6; do
    [ -n "$(lsof -nP -a -p "$pid" -i 2>/dev/null)" ] && bad=$((bad + 1))
    sleep 1
  done
  [ "$bad" -eq 0 ] && ok "⑫ 零外联 6 次采样无连接" || no "⑫ 发现 $bad 次网络连接"
else
  no "未找到 Lampyris 进程（⑪⑫）"
fi

echo "SUMMARY pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
