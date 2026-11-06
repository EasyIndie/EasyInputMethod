#!/usr/bin/env bash
# 萤火虫输入法 — 下载 IDS（汉字结构分解）数据并校验 SHA-256。
#
# 数据源：yi-bai/ids（MIT）ids_lv1.txt —— 汉字 → IDS 分解序列（⿰⿱⿴…），
# 用于 B0 结构事实库的"结构/分量"交叉校验（D19，ADR-309，报告 245）。
#
# 文件约 2 MB，只下载到 data/sources/，不提交进仓库（见 .gitignore）。
# 用法: ./data/sources/fetch-ids.sh
# 校验和已固定在脚本中；不匹配即退出（防止上游静默变更）。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEST="$ROOT/data/sources"

URL="https://raw.githubusercontent.com/yi-bai/ids/main/ids_lv1.txt"
SHA="aa9ba7e394d8fd5cf797b6b9bd6ae5b4546f5222d10f15158c656f099b35c0cf"
OUT="ids_lv1.txt"

if [[ -f "$DEST/$OUT" ]] && echo "$SHA  $DEST/$OUT" | shasum -a 256 -c - >/dev/null 2>&1; then
  echo "已存在且校验通过: $DEST/$OUT"
  exit 0
fi

echo "下载 $URL"
curl -fsSL --max-time 120 "$URL" -o "$DEST/$OUT"
echo "$SHA  $DEST/$OUT" | shasum -a 256 -c -
echo "完成: $DEST/$OUT"
