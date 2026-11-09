#!/usr/bin/env bash
# Install cargo-deny at the pinned version.
#
# CI 里 `taiki-e/install-action` 会从 GitHub Release 资产下载预编译包，该路径偶发 504
# （2026-11-09 连续两次让 main 的 macOS 任务红掉，代码其实全绿）。这里自己下载并重试，
# 失败时退回 crates.io 源码编译；两条路都固定同一版本，避免"工具版本漂移"变成假结论。
set -euo pipefail

VERSION="${CARGO_DENY_VERSION:-0.20.2}"
export PATH="${HOME}/.cargo/bin:${PATH}"

if command -v cargo-deny >/dev/null 2>&1 && cargo-deny --version 2>/dev/null | grep -q " ${VERSION}$"; then
  echo "cargo-deny ${VERSION} 已就绪"
  exit 0
fi

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) TARGET="aarch64-apple-darwin" ;;
  Darwin-x86_64) TARGET="x86_64-apple-darwin" ;;
  Linux-x86_64) TARGET="x86_64-unknown-linux-musl" ;;
  Linux-aarch64) TARGET="aarch64-unknown-linux-musl" ;;
  *) TARGET="" ;;
esac

asset_install() {
  [ -n "${TARGET}" ] || return 1
  local url="https://github.com/EmbarkStudios/cargo-deny/releases/download/${VERSION}/cargo-deny-${VERSION}-${TARGET}.tar.gz"
  local tmp
  tmp="$(mktemp -d)"
  for attempt in 1 2 3 4 5; do
    if curl -fsSL --retry 3 --retry-all-errors --connect-timeout 20 --max-time 300 \
      -o "${tmp}/cargo-deny.tar.gz" "${url}"; then
      tar -xzf "${tmp}/cargo-deny.tar.gz" -C "${tmp}" --strip-components=1 \
        "cargo-deny-${VERSION}-${TARGET}/cargo-deny" 2>/dev/null ||
        tar -xzf "${tmp}/cargo-deny.tar.gz" -C "${tmp}" --strip-components=1
      mkdir -p "${HOME}/.cargo/bin"
      install -m 0755 "${tmp}/cargo-deny" "${HOME}/.cargo/bin/cargo-deny"
      rm -rf "${tmp}"
      return 0
    fi
    echo "下载 ${TARGET} 资产失败（第 ${attempt} 次），重试…" >&2
    sleep $((attempt * 10))
  done
  rm -rf "${tmp}"
  return 1
}

if asset_install && cargo-deny --version | grep -q " ${VERSION}$"; then
  echo "cargo-deny ${VERSION} 已从 Release 资产安装"
  exit 0
fi

echo "Release 资产不可用，改用 crates.io 源码编译（较慢但可靠）" >&2
cargo install cargo-deny --version "${VERSION}" --locked --force
cargo-deny --version
