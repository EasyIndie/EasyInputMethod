#!/usr/bin/env bash
# 萤火虫输入法 — 下载第二个五笔86 验证 oracle（rime/rime-wubi）并校验 SHA-256。
#
# 数据源（LGPL-3.0，见 docs/数据来源与许可.md §1）：
#   D9  rime/rime-wubi   wubi86.dict.yaml
#
# ⚠️ 用途：仅作**验证 oracle**（ADR-016/ADR-019），**不进入发布产物、不打包分发**。
#    其表源自「极点五笔（Jidian）」→ provenance 风险中等（仅测试对照可接受）。
#
# 文件较大，只下载到 data/sources/，不提交进仓库（见 .gitignore）。
# 用法: ./data/sources/fetch-wubi-oracle2.sh
# 校验和已固定在本脚本中；不匹配即报错退出（防止上游静默变更）。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEST="$ROOT/data/sources"

# D9: rime/rime-wubi（LGPL-3.0；码表源自极点五笔）
D9_URL="https://raw.githubusercontent.com/rime/rime-wubi/master/wubi86.dict.yaml"
D9_SHA="f833d86b72341fe82e069a425b6625f29ef85f1bc0f34f6fb7975fe514888b5a"
D9_OUT="rime-wubi86.dict.yaml"

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

download() {
  local url="$1" expected="$2" name="$3"
  local out="$DEST/$name"

  if [ -f "$out" ]; then
    if [ "$(sha256_file "$out")" = "$expected" ]; then
      echo "✅ 已存在且校验通过：$out"
      return 0
    fi
    echo "⚠️  校验失败，将重新下载：$out" >&2
  fi

  local tmp="$out.tmp"
  echo "↓ 下载 $url"
  curl -fsSL --retry 3 --max-time 120 -o "$tmp" "$url"

  local actual
  actual="$(sha256_file "$tmp")"
  if [ "$actual" != "$expected" ]; then
    rm -f "$tmp"
    echo "❌ SHA-256 不匹配：$name" >&2
    echo "   期望 $expected" >&2
    echo "   实际 $actual" >&2
    exit 1
  fi
  mv "$tmp" "$out"
  echo "✅ 校验通过：$out"
}

mkdir -p "$DEST"
download "$D9_URL" "$D9_SHA" "$D9_OUT"
echo "完成。下一步：cargo run -p wubi-encoder --example oracle2"
