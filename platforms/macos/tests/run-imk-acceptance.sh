#!/usr/bin/env bash
# 萤火虫 macOS 实机自动验收（IMK 层）：打字 / 选字 / Esc / 来源标注 / 状态徽标 / 配置实时生效。
#
# 依赖与前提：
#   1) 图形登录会话；萤火虫已安装到 ~/Library/Input Methods/ 且已在系统输入源里启用；
#   2) 运行本脚本的**终端 App 已获「系统设置 → 隐私与安全性 → 辅助功能」授权**（发送按键所需）；
#   3) 只新建 TextEdit 空文档用于输入（结束**自动关闭**，不残留窗口），并会临时改 config.toml（结束自动还原）。
#
# 可选：IMK_ACCEPTANCE_CONFIG_ERROR=1 加测配置错误弹窗（模态，建议只跑一次）；
#       IMK_ACCEPTANCE_PERF=1 加测引擎按键时延（run-perf.sh，较慢）；
#       IMK_ACCEPTANCE_RESTART=1 加测重启后仍生效（会重启宿主，放最后）。
#
# 仍不覆盖（需人工/视觉）：面板词的增删导入导出（FFI 层已由 preview 冒烟覆盖）、
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
TE_BASE=0
DOC_OURS=0

te_docs() { osascript -e 'tell application "TextEdit" to count documents' 2>/dev/null; }

cleanup() {
  [ -f "$BAK" ] && cp "$BAK" "$CFG" 2>/dev/null || true
  # 关闭本脚本新建的 TextEdit 文档（不保存），避免验收后桌面堆积一大堆窗口。
  if [ "${DOC_OURS:-0}" = "1" ]; then
    for _ in 1 2 3 4 5; do
      now="$(te_docs)"
      case "$now" in '' | *[!0-9]*) break ;; esac
      [ "$now" -le "$TE_BASE" ] && break
      osascript -e 'tell application "TextEdit" to close front document saving no' >/dev/null 2>&1
      sleep 0.3
    done
  fi
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
alerttext() { cands; }
nwin() { osascript -e 'tell application "System Events" to tell process "Lampyris" to count windows' 2>/dev/null; }

echo "▶ 准备 TextEdit 空文档（只新建 1 个，结束时自动关闭）"
osascript -e 'tell application "TextEdit" to activate' >/dev/null 2>&1
sleep 0.6
now="$(te_docs)"
case "$now" in '' | *[!0-9]*) now=0 ;; esac
TE_BASE="$now"
osascript -e 'tell application "TextEdit" to make new document' >/dev/null 2>&1
DOC_OURS=1
sleep 1.2

echo "▶ 辅助功能权限自检"
if osascript -e 'tell application "System Events" to keystroke "x"' >/dev/null 2>&1; then
  ok "可发送按键（辅助功能已授权）"
  key 53  # 取消可能的组合
else
  echo "  ⚠️  发送按键被拒：请到 系统设置 → 隐私与安全性 → 辅助功能 勾选你的终端 App 后重试。" >&2
  exit 1
fi

# 统一初始状态为混输 + 每页 5 个候选（①-⑥ 依赖）；结束后由 BAK 还原
sed -i '' 's/^mode = "[a-z]*"/mode = "mixed"/' "$CFG" 2>/dev/null
sed -i '' 's/^count = [0-9]*/count = 5/' "$CFG" 2>/dev/null
sleep 1.0

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
sed -i '' 's/^count = [0-9]*/count = 5/' "$CFG"
sleep 0.6
check "⑥ 配置实时生效(改前)" "$n1" "5"
check "⑥ 配置实时生效(改后无按键)" "$n2" "3"

# DoD④ 模式持久化：用 hotkey.toggle_mode 切换并验证已写入 config（供重启读取）
echo "▶ DoD④ 模式持久化（写盘）"
begin
osascript -e 'tell application "System Events" to keystroke "m" using {control down, shift down}' >/dev/null 2>&1
sleep 0.9
mode="$(grep -oE 'mode = "[a-z]+"' "$CFG" | head -1)"
[ "$mode" = 'mode = "wubi"' ] && ok "模式切换已写入 config（${mode}）" || no "模式写盘失败（${mode}）"

# DoD⑥ 配置错误弹窗（可选，默认不跑）：弹窗是模态，会使当前实例短暂降级，
# 故单独用 IMK_ACCEPTANCE_CONFIG_ERROR=1 触发，且建议仅跑一次/跑完注销重登。
if [ "${IMK_ACCEPTANCE_CONFIG_ERROR:-0}" = "1" ]; then
echo "▶ DoD⑥ 配置错误弹窗（一次性）"
printf 'mode = [oops\n' > "$WORK/bad.toml" && cp "$WORK/bad.toml" "$CFG"
a=""
for _ in $(seq 1 12); do a="$(alerttext)"; echo "$a" | grep -q "配置文件有误" && break; sleep 0.4; done
grep_ok "弹窗出现" "$a" "配置文件有误"
grep_ok "弹窗含行号" "$a" "第 1 行"
osascript -e 'tell application "System Events" to tell process "Lampyris" to click button 1 of window 1' >/dev/null 2>&1
sleep 0.6
cp "$WORK/bad.toml" "$CFG"; sleep 1.2
check "同一错误不重复弹窗" "$(nwin)" "0"
# 弹窗是模态，当前实例会短暂降级，故开一个新文档重建输入上下文（结束统一关闭）。
osascript -e 'tell application "TextEdit" to activate' -e 'tell application "TextEdit" to make new document' >/dev/null 2>&1
sleep 1.5; sel; sleep 0.6
type_ "wq"; sleep 0.4; key 49
check "坏配置下仍可输入" "$(text)" "你"
[ -f "$BAK" ] && cp "$BAK" "$CFG"; sleep 1.0
fi

# ⑪ 引擎按键时延（可选：IMK_ACCEPTANCE_PERF=1；会跑 release 构建，较慢）
if [ "${IMK_ACCEPTANCE_PERF:-0}" = "1" ]; then
  echo "▶ ⑪ 引擎按键时延（run-perf.sh）"
  perf="$("$ROOT/platforms/macos/tests/run-perf.sh" 2>/dev/null | grep -E '^keys=' | tail -1)"
  echo "  ${perf:-未取到}"
  p95="$(echo "$perf" | grep -oE 'p95_ms=[0-9.]+' | cut -d= -f2)"
  if [ -n "$p95" ] && awk "BEGIN{exit !($p95 < 16)}"; then
    ok "⑪ 按键 p95 <16ms（${p95}ms）"
  else
    no "⑪ 按键 p95 ≥16ms（${p95:-未知}）"
  fi
fi

# ⑫ 零外联（输入期间）：边输入边采样，证明确实无连接
pid="$(pgrep -x Lampyris | head -1)"
if [ -n "$pid" ]; then
  : > "$WORK/net-input.log"
  ( for _ in $(seq 1 8); do lsof -nP -a -p "$pid" -i >>"$WORK/net-input.log" 2>/dev/null; sleep 0.35; done ) &
  sampler=$!
  begin
  type_ "nihao"; key 49; type_ "wq"; key 49; type_ "zhongguo"; key 53
  wait "$sampler" 2>/dev/null
  hits="$(grep -c . "$WORK/net-input.log")"
  [ "$hits" -eq 0 ] && ok "⑫ 零外联（输入期间 8 次采样）" || no "⑫ 输入期间发现连接：$(head -1 "$WORK/net-input.log")"
else
  no "未找到 Lampyris 进程（⑫）"
fi

# ⑪ 内存 / ⑫ 空闲零外联（宿主进程）
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

# DoD④ 重启后持久化（可选：IMK_ACCEPTANCE_RESTART=1）：会重启宿主，放在最后。
if [ "${IMK_ACCEPTANCE_RESTART:-0}" = "1" ]; then
  echo "▶ DoD④ 重启后仍生效（重启宿主）"
  sed -i '' 's/^mode = "[a-z]*"/mode = "wubi"/' "$CFG" 2>/dev/null; sleep 1
  killall Lampyris 2>/dev/null; sleep 1.5
  for _ in $(seq 1 10); do
    osascript -e 'tell application "System Events" to key code 49 using {control down}' >/dev/null 2>&1
    sleep 1
    pgrep -x Lampyris >/dev/null && break
  done
  sleep 2
  c=""
  for _ in 1 2 3; do
    # 宿主重启后**旧文档的输入上下文已失效**，必须新建文档才能重新绑定。
    osascript -e 'tell application "TextEdit" to activate' -e 'tell application "TextEdit" to make new document' >/dev/null 2>&1
    sleep 0.8
    sel; sleep 1.2
    type_ "wq"; sleep 1.0; c="$(cands)"; key 53
    echo "$c" | grep -q "五笔" && break
    sleep 1
  done
  grep_ok "④ 重启后仍为五笔（状态徽标）" "$c" "五笔"
fi

echo "SUMMARY pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
