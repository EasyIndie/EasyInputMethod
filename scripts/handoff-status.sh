#!/usr/bin/env bash
# 交接状态采集：一次性打印可粘贴到 HANDOFF / 交接提示词的当前状态。
# 只读：不安装、不改配置、不切输入源。
set -uo pipefail
SCENARIO=""
PROMPT=false
for arg in "$@"; do
  case "${arg}" in
    --for=*) SCENARIO="${arg#--for=}" ;;
    --prompt) PROMPT=true ;;
    -h|--help) echo "用法：$0 [--for=compact|session|agent|device] [--prompt]"; exit 0 ;;
    *) echo "未知参数：${arg}（支持 --for=… / --prompt / --help）" >&2; exit 2 ;;
  esac
done
case "${SCENARIO}" in
  ''|compact|session|agent|device) ;;
  *) echo "--for 只能是 compact / session / agent / device" >&2; exit 2 ;;
esac
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${HOME}/Library/Input Methods/Lampyris.app"
SUPPORT="${HOME}/Library/Application Support/Lampyris"
CONFIG="${SUPPORT}/config.toml"
DICT="${SUPPORT}/user-dictionary.tsv"
PROBE="${ROOT}/tools/macos-probe/bin"

row() { printf '| %s | %s |\n' "$1" "$2"; }
short() { shasum -a 256 "$1" 2>/dev/null | cut -c1-12; }

echo "## 交接状态（自动采集 $(date '+%Y-%m-%d %H:%M') · $(hostname -s) · $(uname -m) · macOS $(sw_vers -productVersion)）"
echo
echo "| 项 | 值 |"
echo "|---|---|"

branch="$(git -C "${ROOT}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '-')"
head="$(git -C "${ROOT}" rev-parse --short HEAD 2>/dev/null || echo '-')"
subject="$(git -C "${ROOT}" log -1 --format=%s 2>/dev/null || echo '-')"
row "分支 / HEAD" "\`${branch}\` @ \`${head}\` ${subject}"

if [ -z "$(git -C "${ROOT}" status --porcelain 2>/dev/null)" ]; then
  row "工作树" "clean"
else
  row "工作树" "**$(git -C "${ROOT}" status --porcelain | wc -l | tr -d ' ') 个改动未提交**"
fi

upstream="$(git -C "${ROOT}" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
if [ -n "${upstream}" ]; then
  ahead="$(git -C "${ROOT}" rev-list --count "${upstream}..HEAD" 2>/dev/null || echo '?')"
  behind="$(git -C "${ROOT}" rev-list --count "HEAD..${upstream}" 2>/dev/null || echo '?')"
  row "与远端" "${ahead} ahead / ${behind} behind（\`${upstream}\`）"
else
  row "与远端" "无 upstream"
fi

if [ -x "${APP}/Contents/MacOS/Lampyris" ]; then
  authority="$(codesign -dv --verbose=2 "${APP}" 2>&1 | awk -F'=' '/^Authority=/{print $2; exit}')"
  verdict="$(spctl -a -vvv -t install "${APP}" 2>&1 | head -1 || true)"
  row "已装包" "执行 SHA \`$(short "${APP}/Contents/MacOS/Lampyris")\`… · ${authority:-未签名} · ${verdict:-spctl 未通过}"
else
  row "已装包" "**未安装**（${APP} 不存在）"
fi

hostpid="$(pgrep -x Lampyris 2>/dev/null | head -1 || true)"
row "宿主 PID" "${hostpid:-未运行}"

if [ -f "${CONFIG}" ]; then
  state="$(grep -E '^(mode|punctuation|chinese_variant|full_width) *=' "${CONFIG}" \
    | sed -E 's/ *= */=/' | sed -E 's/ *#.*//' | tr -d '"' | tr '\n' ' ')"
  explicit="$(grep -cE '^(toggle_|open_)' "${CONFIG}" 2>/dev/null || true)"
  row "config" "SHA \`$(short "${CONFIG}")\` · ${state}· 显式 hotkey 项 ${explicit}"
else
  row "config" "**未生成**（首次启动按 Schema 默认值创建）"
fi

if [ -f "${DICT}" ]; then
  row "词库" "$(wc -l < "${DICT}" | tr -d ' ') 行 · SHA \`$(short "${DICT}")\`"
else
  row "词库" "未生成"
fi

if [ -x "${PROBE}/selsrc" ]; then
  row "输入源" "\`$("${PROBE}/selsrc" 2>/dev/null | awk '{print $2}')\`"
else
  selected="$(defaults read com.apple.HIToolbox AppleSelectedInputSources 2>/dev/null \
    | awk '/KeyboardLayout Name/{print $3}' | tr -d '"' | head -1)"
  row "输入源" "${selected:-未知}（探针未构建，读 HIToolbox）"
fi

if [ -d "${PROBE}" ]; then
  row "探针" "`ls "${PROBE}" | wc -l | tr -d ' '` 个二进制"
else
  row "探针" "未构建（\`make -C tools/macos-probe\`）"
fi

if command -v gh >/dev/null 2>&1; then
  ci="$(gh run list --limit 1 --json workflowName,status,conclusion,headSha -q \
    '.[0] | "\(.workflowName) \(.status)/\(.conclusion // "-") @ \(.headSha[0:7])"' 2>/dev/null || true)"
  row "最近 CI" "${ci:-查询失败}"
fi

row "最近报告" "$(ls "${ROOT}/docs/reviews" 2>/dev/null | grep -E '^[0-9]{3}-' | tail -3 | tr '\n' ' ')"
row "HANDOFF" "$(wc -l < "${ROOT}/HANDOFF.md" | tr -d ' ') 行 · 日志 $(grep -cE '^- 20[0-9]{2}-' "${ROOT}/HANDOFF.md" 2>/dev/null || echo 0) 条"
agent="未知"
if [ -n "${PI_SESSION_FILE:-}" ] || [ -n "${PI_CODING_AGENT:-}" ]; then
  agent="pi${PI_MODEL:+（${PI_MODEL}）}"
elif [ -n "${CLAUDECODE:-}" ] || [ -n "${CLAUDE_CODE_ENTRYPOINT:-}" ]; then
  agent="Claude Code"
elif [ -n "${CODEX_HOME:-}" ] || [ -n "${CODEX_SANDBOX:-}" ]; then
  agent="Codex"
fi
row "工具 / 会话" "${agent}${PI_SESSION_FILE:+ · 会话文件 \`$(basename "${PI_SESSION_FILE}")\`}"
echo
case "${SCENARIO}" in
  compact) cat <<'TEXT'
> **上下文压缩前**：先把「此刻在哪 / 下一步 / 有什么坑」写进 HANDOFF §0/§3/§4 + 一条 §9 日志，
> 压缩后第一件事是重读 HANDOFF（不要凭记忆继续），再按 §4 执行。
TEXT
  ;;
  session) cat <<'TEXT'
> **开新会话（同工具同设备）**：把上面的表 + HANDOFF §3/§4 粘进新会话的第一条消息；
> 新会话先 `git status`/`git log -1` 确认没有别人插进来的改动。
TEXT
  ;;
  agent) cat <<'TEXT'
> **跨 agent（pi / Codex / Claude Code）**：只依赖仓库文件（AGENTS.md → HANDOFF.md → docs/），
> 不依赖上一个 agent 的会话记忆；Skills 唯一来源是 `.agents/skills/`；提示词里点明你用的工具与门禁命令。
TEXT
  ;;
  device) cat <<'TEXT'
> **跨设备**：包必须同时给 **zip SHA 与执行 SHA**；记下目标机已装的旧包、config 是否有显式 `hotkey.*`、
> 输入源与词库行数；平台差异（如菜单索引/设置默认分区）要在报告里单列。
TEXT
  ;;
  *) cat <<'TEXT'
> 粘贴到 HANDOFF §0/§1 与交接提示词；日志条目、未决项、下一步仍需人工判断。
> 场景化清单：`--for=compact|session|agent|device`。
TEXT
  ;;
esac
echo "> 流程与反例见 \`.agents/skills/update-handoff/SKILL.md\`；提示词模板见 \`docs/交接提示词模板.md\`。"

if ${PROMPT}; then
  echo
  echo '```text'
  cat <<PROMPT_TEXT
项目：萤火虫输入法（macOS 中文输入法），仓库 ~/Documents/EasyInputMethod。
先完整阅读 AGENTS.md → HANDOFF.md（重点 §0/§1/§3/§4）。

当前状态（$(date '+%Y-%m-%d')）：
- 分支：main @ ${head}（${subject}）。
- 已装包：执行 SHA $( [ -x "${APP}/Contents/MacOS/Lampyris" ] && echo "\`$(short "${APP}/Contents/MacOS/Lampyris")…\`" || echo "未安装" )；
  待装包：$( zip="$(ls -t "${ROOT}"/packaging/out/*/*/*.zip 2>/dev/null | head -1)"; if [ -n "${zip}" ]; then echo "\`${zip#"${ROOT}/"}\`（SHA $(short "${zip}")…）"; else echo "需从 CI artifact 取（见 HANDOFF §1）"; fi )。
- 本机：$(hostname -s) / $(uname -m) / macOS $(sw_vers -productVersion)；
  config ${CONFIG}（$(short "${CONFIG}")…）；词库 $( [ -f "${DICT}" ] && wc -l < "${DICT}" | tr -d ' ' || echo 未生成 ) 行。
- 上一轮遗留：见 HANDOFF §3。

任务：{{一句话目标}}。结果写 docs/reviews/{{NNN}}-{{slug}}.md。

步骤：
1. git fetch origin && git checkout main && git pull --ff-only
2. {{构建或取包命令}}
3. 逐项验收（PASS/FAIL/BLOCKED + 证据）：{{a/b/c…}}
4. 还原 {{mode/输入源/窗口/文档}} 并核对 config 字节、宿主 PID、包 SHA。
5. 收尾：写报告；更新 HANDOFF（§1/§3/§4/§9）与 ROADMAP；make verify 后提交推送 main。

边界：
- {{本次禁止的动作}}
- 配置只经 ime-config；不手改 config.toml，不写 UserDefaults。
- 只用自建文档与自有会话；失败即停并保留证据。
- 系统菜单/AX 必须在图形会话执行；读菜单前先按键激活。
PROMPT_TEXT
  echo '```'
fi
