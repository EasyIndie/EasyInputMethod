#!/usr/bin/env bash
# 下载 OpenCC 简→繁（s2t）词典：STCharacters + STPhrases。
#
# 许可：Apache-2.0（与 GPL-3 兼容），见 docs/数据来源与许可.md（D11）。
# 固定 OpenCC commit 以保证可复现；产物由 tools/prepare-variant.py 编译。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEST="${ROOT}/data/sources"
OPENCC_SHA="8cf737a4e193db27d675b2ce9867d84aace33745"
BASE="https://raw.githubusercontent.com/BYVoid/OpenCC/${OPENCC_SHA}/data/dictionary"
for name in STCharacters STPhrases; do
  curl -fsSL "${BASE}/${name}.txt" -o "${DEST}/opencc-${name}.txt"
done
echo "已下载 opencc-STCharacters.txt / opencc-STPhrases.txt（OpenCC ${OPENCC_SHA}）"
