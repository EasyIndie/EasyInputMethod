#!/usr/bin/env bash
# Local only. No credentials, upload, installation or deletion of prior artifacts.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"
SIGNED=false
case "${1:-}" in '') ;; --signed) SIGNED=true ;; *) echo "用法：$0 [--signed]" >&2; exit 2 ;; esac
[ -z "$(git status --porcelain)" ] || { echo "请先提交已验证的修改，确保源码与包一致" >&2; exit 1; }
COMMIT="$(git rev-parse HEAD)"
OUT="${ROOT}/packaging/out"
mkdir -p "${OUT}"
WORK="$(mktemp -d "${OUT}/candidate.XXXXXX")"
APP="${ROOT}/platforms/macos/build/Yinghuo.app"
if ${SIGNED}; then
  [ "$(cat "${APP}/Contents/Resources/SOURCE-COMMIT")" = "${COMMIT}" ] || { echo "签名应用与当前源码提交不符，请重新构建" >&2; exit 1; }
  for name in wubi86-core.tsv pinyin-chars.tsv pinyin-core.tsv; do
    cmp "data/generated/${name}" "${APP}/Contents/Resources/${name}"
  done
  cmp platforms/macos/Info.plist "${APP}/Contents/Info.plist"
  codesign --verify --strict "${APP}"
  xcrun stapler validate "${APP}"
  spctl --assess --type execute --verbose=2 "${APP}"
else
  CLANG_MODULE_CACHE_PATH="${WORK}/module-cache" ./platforms/macos/build.sh --strict --universal
fi
# 候选包按实际可执行文件标注架构（universal/arm64/x86_64），不依赖宿主 uname。
APP_ARCHS="$(lipo -archs "${APP}/Contents/MacOS/Yinghuo" 2>/dev/null || uname -m)"
case " ${APP_ARCHS} " in
  *" arm64 "*)
    case " ${APP_ARCHS} " in *" x86_64 "*) ARCH="universal" ;; *) ARCH="arm64" ;; esac ;;
  *" x86_64 "*) ARCH="x86_64" ;;
  *) ARCH="${APP_ARCHS// /-}" ;;
esac
STAGE="${WORK}/Yinghuo-0.1.0-${ARCH}"
mkdir -p "${STAGE}/SOURCE" "${STAGE}/scripts"
ditto "${APP}" "${STAGE}/Yinghuo.app"
# Include locked dependency source; third parties can build without registry access.
git archive HEAD | tar -x -C "${STAGE}/SOURCE"
printf '%s\n' "${COMMIT}" > "${STAGE}/SOURCE/SOURCE-COMMIT"
cargo vendor --locked --offline "${STAGE}/SOURCE/vendor" > "${WORK}/vendor-config.toml"
mkdir -p "${STAGE}/SOURCE/.cargo"
cp "${WORK}/vendor-config.toml" "${STAGE}/SOURCE/.cargo/config.toml"
# cargo vendor emits the supplied absolute path; make the archive relocatable.
python3 - "${STAGE}/SOURCE/.cargo/config.toml" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
s = p.read_text().splitlines()
p.write_text('\n'.join('directory = "vendor"' if line.startswith('directory = ') else line for line in s) + '\n')
PY
cp LICENSE "${STAGE}/LICENSE"
cp packaging/macos/RELEASE-README.md "${STAGE}/README.md"
cp platforms/macos/install.sh platforms/macos/uninstall.sh "${STAGE}/scripts/"
cp -R packaging/licenses "${STAGE}/DATA-LICENSES"
cp docs/数据来源与许可.md "${STAGE}/DATA-SOURCES.md"
cp data/sources.toml "${STAGE}/data-sources.toml"
cargo tree --locked --offline -p ime-ffi > "${STAGE}/cargo-tree.txt"
{
  printf 'commit=%s\narchitecture=%s\nlipo_archs=%s\nsigned_release=%s\n' "${COMMIT}" "${ARCH}" "${APP_ARCHS}" "${SIGNED}"
  rustc --version
  swiftc --version
  xcrun --show-sdk-version
  sw_vers
} > "${STAGE}/BUILD-INFO.txt"
python3 packaging/macos/manifest.py "${STAGE}"
ZIP="${WORK}/Yinghuo-0.1.0-${ARCH}.zip"
ditto -c -k --keepParent "${STAGE}" "${ZIP}"
BYTES="$(stat -f %z "${ZIP}")"
[ "${BYTES}" -le 15000000 ] || { echo "包超过 15MB：${BYTES}" >&2; exit 1; }
(cd "${WORK}" && shasum -a 256 "$(basename "${ZIP}")" > "$(basename "${ZIP}").sha256")
echo "本地候选包：${ZIP}（${BYTES} 字节，signed_release=${SIGNED}）"
if ! ${SIGNED}; then echo "仅供审核；尚未签名/公证，不可对外发布或安装。"; fi
