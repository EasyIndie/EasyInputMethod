#!/usr/bin/env bash
# 萤火虫输入法 — 下载五笔86「字→字根拆分」数据并校验 SHA-256。
#
# 数据源（均为 MIT，见 docs/数据来源与许可.md §1）：
#   D2  aardio/wubi-lex        sepllingData/86.txt
#   D3  huanfeng/WindInput     data/schemas/wubi86/wubi86_chaizi.txt
#
# 文件较大，只下载到 data/sources/，不提交进仓库（见 .gitignore）。
# 用法: ./data/sources/fetch-wubi-chaizi.sh
# 校验和已固定在本脚本中；不匹配即报错退出（防止上游静默变更）。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEST="$ROOT/data/sources"

# D2: aardio/wubi-lex（MIT, Copyright (c) 2019 aardio）
D2_URL="https://raw.githubusercontent.com/aardio/wubi-lex/master/sepllingData/86.txt"
D2_SHA="da8a20e6af3446348d5d68a89ac71d5e3b9b17b00446d8204ac1e9529626697f"
D2_OUT="wubi-lex-86.txt"

# D3: huanfeng/WindInput（MIT, Copyright (c) 2026 WindInput Contributors）
D3_URL="https://raw.githubusercontent.com/huanfeng/WindInput/master/data/schemas/wubi86/wubi86_chaizi.txt"
D3_SHA="7c64e5846f2ed96a26da24abffaaa2d139a5efc7a0d6de336d13269b70095ac6"
D3_OUT="windinput-wubi86-chaizi.txt"

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
download "$D2_URL" "$D2_SHA" "$D2_OUT"
download "$D3_URL" "$D3_SHA" "$D3_OUT"
echo "完成。下一步：cargo run -p wubi-encoder --example crosscheck"
