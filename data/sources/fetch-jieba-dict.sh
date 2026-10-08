#!/usr/bin/env bash
# 萤火虫输入法 — 下载 jieba 词表（dict.txt）并校验 SHA-256。
#
# 数据源（MIT，见 docs/数据来源与许可.md §1）：
#   D10  fxsjy/jieba   dict.txt（词表 + 词频；Copyright (c) 2013 Sun Junyi）
#
# 用途：通用词表 + 词频，供 T-M1-06b 生成词组码表并给单字/词组赋权（ADR-013）。
# 格式：`词 频次 词性`（空格分隔）。文件较大（≈5 MB），只下载到 data/sources/，
# 不提交进仓库（见 .gitignore）。
# 用法: ./data/sources/fetch-jieba-dict.sh
# 校验和已固定在本脚本中；不匹配即报错退出（防止上游静默变更）。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEST="$ROOT/data/sources"

# D10: fxsjy/jieba（MIT, Copyright (c) 2013 Sun Junyi）
D10_URL="https://raw.githubusercontent.com/fxsjy/jieba/master/jieba/dict.txt"
D10_SHA="7197c3211ddd98962b036cdf40324d1ea2bfaa12bd028e68faa70111a88e12a8"
D10_OUT="jieba-dict.txt"

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
  curl -fsSL --retry 3 --max-time 300 -o "$tmp" "$url"

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
download "$D10_URL" "$D10_SHA" "$D10_OUT"
echo "完成。下一步：cargo run -p wubi-encoder --example generate"
echo "然后：cargo run -p wubi-encoder --example generate_phrases"
