#!/usr/bin/env bash
# 安装本地 git hooks：pre-push → make verify。见 docs/开发工作流.md。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ ! -d "${ROOT}/.git" ]; then
  echo "不是 git 仓库（缺少 ${ROOT}/.git）" >&2
  exit 1
fi

for name in pre-push commit-msg; do
  dst="${ROOT}/.git/hooks/${name}"
  install -m 0755 "${ROOT}/scripts/hooks/${name}" "${dst}"
  echo "✅ 已安装 ${dst}"
done
echo "临时跳过：git push --no-verify / git commit --no-verify"
