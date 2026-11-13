#!/bin/sh
# 下载 Unicode Emoji 全量数据与 CLDR 中英文标注（U3-5 / ADR-349）。
# 固定版本与 SHA-256；不匹配即失败。运行期不联网，只有本脚本显式执行时下载。
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="${ROOT}/data/sources"

fetch() { # url sha path
    url="$1"; sha="$2"; path="$3"
    [ -f "$path" ] && actual="$(shasum -a 256 "$path" | awk '{print $1}')" || actual=""
    if [ "$actual" = "$sha" ]; then
        echo "✅ 已存在且校验通过：$path"
        return 0
    fi
    echo "↓ 下载 $url"
    curl -fsSL --retry 3 --max-time 120 -o "$path.tmp" "$url"
    actual="$(shasum -a 256 "$path.tmp" | awk '{print $1}')"
    [ "$actual" = "$sha" ] || { rm -f "$path.tmp"; echo "❌ SHA 不匹配：$path（期望 $sha，实际 $actual）" >&2; exit 1; }
    mv "$path.tmp" "$path"
    echo "✅ 校验通过：$path"
}

fetch "https://unicode.org/Public/emoji/16.0/emoji-test.txt" \
      24f0c534e86cf142e2496953e8f0e46a3e702392911eddcd29c6cced85139697 \
      "${DEST}/emoji-test-16.0.txt"
fetch "https://raw.githubusercontent.com/unicode-org/cldr/release-47/common/annotations/zh.xml" \
      06b289e1b563199df2e2c51ab93ca8a3780a57a7ee82f4600828936c8323af0d \
      "${DEST}/cldr-annotations-zh.xml"
fetch "https://raw.githubusercontent.com/unicode-org/cldr/release-47/common/annotations/en.xml" \
      b33e2e88ed2fb8c438c1efa9747b9d845e8d7d74ef0c32342a805c0f46fdd7ec \
      "${DEST}/cldr-annotations-en.xml"
# 旗帜 emoji 的英文名在 emoji-test，中文地区名来自 CLDR main/zh.xml。
fetch "https://raw.githubusercontent.com/unicode-org/cldr/release-47/common/main/zh.xml" \
      97fea2cfdb7bfe59a4e0ce712ca2e6ccba67ef211957296f60365c9f84b24d52 \
      "${DEST}/cldr-main-zh.xml"

echo "完成。下一步：python3 tools/prepare-emoji.py"
