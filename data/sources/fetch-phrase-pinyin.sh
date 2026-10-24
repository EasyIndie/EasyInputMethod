#!/usr/bin/env bash
# 萤火虫输入法 — 下载词组表（phrase-pinyin-data）并校验 SHA-256。
#
# 数据源（MIT，见 docs/数据来源与许可.md §1）：
#   D4  mozillazg/phrase-pinyin-data   pinyin.txt（版本 0.19.0）
#
# 用途：仅取中文词（`词: 拼音` 的第一列），供 T-M1-06 按五笔86 词组规则生成词组码表。
# 文件较大（≈1.2 MB），只下载到 data/sources/，不提交进仓库（见 .gitignore）。
# 用法: ./data/sources/fetch-phrase-pinyin.sh
# 校验和已固定在本脚本中；不匹配即报错退出（防止上游静默变更）。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEST="$ROOT/data/sources"

# D4: mozillazg/phrase-pinyin-data（MIT, Copyright (c) 2017 mozillazg）
# v0.19.0 的不可变提交；与登记的原始 SHA-256 一致，不跟随 master 漂移。
D4_URL="https://raw.githubusercontent.com/mozillazg/phrase-pinyin-data/cee0ed6e6e4898580cafd2bd5e3723e20b214aa0/pinyin.txt"
D4_SHA="dcc769607c220b312fea3e71cb63421298b4b891b1f7356a95ab58f2c96fff81"
D4_OUT="phrase-pinyin-data-pinyin.txt"

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
download "$D4_URL" "$D4_SHA" "$D4_OUT"
echo "完成。下一步：cargo run -p wubi-encoder --example generate_phrases"
