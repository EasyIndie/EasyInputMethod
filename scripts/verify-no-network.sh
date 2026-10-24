#!/usr/bin/env bash
# 萤火虫输入法 — 静态隐私门禁（不做进程外联/抓包验证）。
#
# 两重检查：
#   1) 源码级：核心 crate 的 Cargo.toml 是否依赖已知网络/遥测库；
#   2) 产物级：本地 target/ 下可枚举产物是否含已知未定义网络符号。
#
# 退出码：0 = 上述静态检查通过（允许尚无产物），1 = 断言失败。
# 最终候选仍需单独记录宿主进程动态外联核验（docs/隐私与安全.md §4）。
# 见 AGENTS.md 铁律 1、docs/隐私与安全.md。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CORE_CRATES=(ime-core ime-table ime-pinyin ime-dict ime-config)
NET_CRATES='reqwest|hyper|ureq|isahc|curl|surf|awc|tonic|sentry|opentelemetry|mixpanel'
NET_SYMBOLS='socket$|connect$|getaddrinfo|gethostbyname|getnameinfo|sendto$|recvfrom$|inet_addr|inet_pton|curl_easy|SSL_connect'

fail=0

echo "▶ 1/2 源码级检查：核心 crate 依赖"
if [ ! -f Cargo.toml ]; then
  echo "  ℹ️  尚无 Cargo workspace（P1-M0 创建），跳过。"
else
  for c in "${CORE_CRATES[@]}"; do
    manifest="crates/$c/Cargo.toml"
    [ -f "$manifest" ] || continue
    if grep -Eq "$NET_CRATES" "$manifest"; then
      echo "  ❌ $manifest 依赖了网络/遥测库："
      grep -En "$NET_CRATES" "$manifest" | sed 's/^/     /'
      fail=1
    else
      echo "  ✅ $c"
    fi
  done
fi

echo "▶ 2/2 产物级检查：符号表"
checked=0
if [ -d target ]; then
  while IFS= read -r -d '' f; do
    checked=$((checked + 1))
    if command -v nm >/dev/null 2>&1; then
      hits="$(nm -u "$f" 2>/dev/null | grep -E "$NET_SYMBOLS" || true)"
      if [ -n "$hits" ]; then
        echo "  ❌ 发现网络符号: $f"
        echo "$hits" | sed 's/^/     /'
        fail=1
      fi
    fi
  done < <(find target -type f \( -name '*.dylib' -o -name '*.so' -o -perm -u+x \) -print0 2>/dev/null)
fi

if [ "$checked" -eq 0 ]; then
  echo "  ℹ️  尚无产物可检查（首次构建后自动覆盖 dylib/so/可执行文件）。"
else
  echo "  已检查 $checked 个产物。"
fi

if [ "$fail" -eq 0 ]; then
  echo "✅ 静态隐私断言通过；未执行最终候选的进程外联核验。"
else
  echo "❌ 隐私断言失败：见上方条目（AGENTS.md 铁律 1）。"
  exit 1
fi
