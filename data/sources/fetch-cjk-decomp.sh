#!/usr/bin/env bash
# 萤火虫输入法 — 下载 cjk-decomp（Apache-2.0）完整拆字数据并校验 SHA-256。
# 文件较大，只下载到 data/sources/，不提交进仓库（见 .gitignore）。
# 用法: ./data/sources/fetch-cjk-decomp.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEST="$ROOT/data/sources/cjk-decomp.txt"
URL="https://raw.githubusercontent.com/amake/cjk-decomp/c29b391fd6267e7a3541387e03a3dd60b1cd34d1/cjk-decomp.txt"
SHA="5accf5661dd509d4bc5966afaeb7f763231a39f23b00acda89d6c040740b8ab6"
if [ -f "$DEST" ]; then
  if command -v sha256sum >/dev/null 2>&1; then got=$(sha256sum "$DEST" | awk '{print $1}'); else got=$(shasum -a 256 "$DEST" | awk '{print $1}'); fi
  [ "$got" = "$SHA" ] && { echo "已存在且校验通过：$DEST"; exit 0; }
fi
curl -fsSL "$URL" -o "$DEST"
if command -v sha256sum >/dev/null 2>&1; then got=$(sha256sum "$DEST" | awk '{print $1}'); else got=$(shasum -a 256 "$DEST" | awk '{print $1}'); fi
[ "$got" = "$SHA" ] || { echo "SHA-256 不匹配：$got != $SHA" >&2; exit 1; }
echo "已下载并校验：$DEST"
