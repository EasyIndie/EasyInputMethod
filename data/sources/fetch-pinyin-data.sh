#!/usr/bin/env bash
# 萤火虫输入法 — 下载单字拼音表（pinyin-data）并校验 SHA-256。
#
# 数据源（MIT，见 docs/数据来源与许可.md §1）：
#   D5  mozillazg/pinyin-data   pinyin.txt（版本 0.15.0；Copyright (c) 2016 mozillazg）
#
# 用途：字→拼音（带声调），供 T-M2-02 生成拼音兜底单字表（拼音反查也共用此数据）。
# 格式：`U+XXXX: pinyin1,pinyin2  # 字`。文件下载获取，不入库（见 .gitignore）。
# 用法: ./data/sources/fetch-pinyin-data.sh
# 校验和已固定在本脚本中；不匹配即报错退出（防止上游静默变更）。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEST="$ROOT/data/sources"

# D5: mozillazg/pinyin-data（MIT, Copyright (c) 2016 mozillazg）
D5_URL="https://raw.githubusercontent.com/mozillazg/pinyin-data/master/pinyin.txt"
D5_SHA="621f8ca9eff8519f47e2b17b564fd318161e13bca07eea8c8e04993cd5d3b52e"
D5_OUT="pinyin-data.txt"

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
download "$D5_URL" "$D5_SHA" "$D5_OUT"
echo "完成。下一步：cargo run -p ime-pinyin --example generate"
