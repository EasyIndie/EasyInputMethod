#!/usr/bin/env bash
# 检查「萤火虫」是否还在已启用输入源里；不在就打开系统设置并给出恢复步骤。
#
# 覆盖安装后 macOS 常把输入源移出启用列表（实测多次）。TIS API 的后台启用不持久化，
# 所以这里只做"检测 + 把用户送到设置页"，不改系统偏好文件。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROBE="${ROOT}/tools/macos-probe/bin/tissrc"
SOURCE_ID="cn.jokerhub.inputmethod.Lampyris.default"

if [ ! -x "${PROBE}" ]; then
  echo "缺少探针 ${PROBE}（先跑 make macos-probe-build）" >&2
  exit 2
fi

if "${PROBE}" list | grep -qx "enabled ${SOURCE_ID}"; then
  echo "✅ 输入源已启用"
  if "${PROBE}" list | grep -qx "current ${SOURCE_ID}"; then
    echo "   当前也已在用"
  else
    echo "   当前不是它：${PROBE} select ${SOURCE_ID}"
  fi
  exit 0
fi

cat >&2 <<TEXT
⚠️  「萤火虫」不在已启用输入源里（覆盖安装后常见）。
   恢复：系统设置 → 键盘 → 文字输入 → 输入法 → 编辑 /「+」→ 中文（简体）→ 萤火虫 → 添加
   添加后切过去：${PROBE} select ${SOURCE_ID}
TEXT
open "x-apple.systempreferences:com.apple.Keyboard-Settings.extension" 2>/dev/null || true
exit 1
