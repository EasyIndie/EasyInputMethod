#!/usr/bin/env bash
# Local only. No credentials, upload, installation or deletion of prior artifacts.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"
SIGNED=false
case "${1:-}" in '') ;; --signed) SIGNED=true ;; *) echo "用法：$0 [--signed]" >&2; exit 2 ;; esac
[ -z "$(git status --porcelain)" ] || { echo "请先提交已验证的修改，确保源码与包一致" >&2; exit 1; }
COMMIT="$(git rev-parse HEAD)"
VERSION="$(python3 tools/release_version.py version)"
BUILD_NUMBER="$(python3 tools/release_version.py build)"
OUT="${ROOT}/packaging/out"
mkdir -p "${OUT}"
WORK="$(mktemp -d "${OUT}/candidate-XXXXXX")"
APP="${ROOT}/platforms/macos/build/Lampyris.app"
if ${SIGNED}; then
  [ "$(cat "${APP}/Contents/Resources/SOURCE-COMMIT")" = "${COMMIT}" ] || { echo "签名应用与当前源码提交不符，请重新构建" >&2; exit 1; }
  for name in wubi86-core.tsv pinyin-chars.tsv pinyin-core.tsv variant-s2t.tsv; do
    cmp "data/generated/${name}" "${APP}/Contents/Resources/${name}"
  done
  python3 tools/macos-build-metadata.py check-contract platforms/macos/Info.plist "${APP}/Contents/Info.plist"
  codesign --verify --strict "${APP}"
  xcrun stapler validate "${APP}"
  spctl --assess --type execute --verbose=2 "${APP}"
else
  CLANG_MODULE_CACHE_PATH="${WORK}/module-cache" ./platforms/macos/build.sh --strict --universal
fi
# 候选包按实际可执行文件标注架构（universal/arm64/x86_64），不依赖宿主 uname。
APP_ARCHS="$(lipo -archs "${APP}/Contents/MacOS/Lampyris" 2>/dev/null || uname -m)"
case " ${APP_ARCHS} " in
  *" arm64 "*)
    case " ${APP_ARCHS} " in *" x86_64 "*) ARCH="universal" ;; *) ARCH="arm64" ;; esac ;;
  *" x86_64 "*) ARCH="x86_64" ;;
  *) ARCH="${APP_ARCHS// /-}" ;;
esac
STAGE="${WORK}/Lampyris-${VERSION}-${ARCH}"
mkdir -p "${STAGE}/scripts"
ditto "${APP}" "${STAGE}/Lampyris.app"
cp LICENSE "${STAGE}/LICENSE"
python3 - "${VERSION}" "${STAGE}/README.md" <<'PY'
import sys
from pathlib import Path
Path(sys.argv[2]).write_text(Path("packaging/macos/RELEASE-README.md").read_text().replace("@VERSION@", sys.argv[1]))
PY
cp platforms/macos/install.sh platforms/macos/uninstall.sh "${STAGE}/scripts/"
cp -R packaging/licenses "${STAGE}/DATA-LICENSES"
cp docs/数据来源与许可.md "${STAGE}/DATA-SOURCES.md"
cp data/sources.toml "${STAGE}/data-sources.toml"
cargo tree --locked --offline -p ime-ffi > "${STAGE}/cargo-tree.txt"
{
  printf 'commit=%s\narchitecture=%s\nlipo_archs=%s\nsigned_release=%s\n' "${COMMIT}" "${ARCH}" "${APP_ARCHS}" "${SIGNED}"
  printf 'version=%s\nbuild=%s\n' "${VERSION}" "${BUILD_NUMBER}"
  rustc --version
  swiftc --version
  xcrun --show-sdk-version
  sw_vers
} > "${STAGE}/BUILD-INFO.txt"
# GPL-3.0-or-later §6(d)：二进制包不含源码，改为在同一发布位置提供对应源码（ADR-064）。
cat > "${STAGE}/SOURCE.txt" <<TXT
本安装包按 GPL-3.0-or-later 分发，但**不含源码**（第 6(d) 条）。

Corresponding Source（对应源码）：
  1) 与本包发布在同一位置的 Lampyris-${VERSION}-source.tar.gz；
  2) 公开仓库对应版本：https://github.com/EasyIndie/EasyInputMethod （该 tag 的源码与构建脚本）
若本包被转发到其它位置，转发者须在旁注明等价的源码获取地址；
源码与本包一样免费可得，构建方式见源码包内 platforms/macos/README.md。
TXT
python3 packaging/macos/manifest.py "${STAGE}"
ZIP="${WORK}/Lampyris-${VERSION}-${ARCH}.zip"
ditto -c -k --norsrc --noextattr --keepParent "${STAGE}" "${ZIP}"
BYTES="$(stat -f %z "${ZIP}")"
[ "${BYTES}" -le 15000000 ] || { echo "包超过 15MB：${BYTES}" >&2; exit 1; }
(cd "${WORK}" && shasum -a 256 "$(basename "${ZIP}")" > "$(basename "${ZIP}").sha256")

# ── 对应源码包（与二进制同处发布；GPL §6(d)）─────────────
SOURCE_STAGE="${WORK}/source-tar"
SOURCE_ROOT="${SOURCE_STAGE}/Lampyris-${VERSION}-source"
mkdir -p "${SOURCE_ROOT}"
# Include locked dependency source; third parties can build without registry access.
git archive HEAD | tar -x -C "${SOURCE_ROOT}"
printf '%s\n' "${COMMIT}" > "${SOURCE_ROOT}/SOURCE-COMMIT"
cargo vendor --locked --offline "${SOURCE_ROOT}/vendor" > "${WORK}/vendor-config.toml"
mkdir -p "${SOURCE_ROOT}/.cargo"
cp "${WORK}/vendor-config.toml" "${SOURCE_ROOT}/.cargo/config.toml"
# cargo vendor emits the supplied absolute path; make the archive relocatable.
python3 - "${SOURCE_ROOT}/.cargo/config.toml" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
s = p.read_text().splitlines()
p.write_text('\n'.join('directory = "vendor"' if line.startswith('directory = ') else line for line in s) + '\n')
PY
SOURCE_TAR="${WORK}/Lampyris-${VERSION}-source.tar.gz"
COPYFILE_DISABLE=1 tar -czf "${SOURCE_TAR}" -C "${SOURCE_STAGE}" "Lampyris-${VERSION}-source"
(cd "${WORK}" && shasum -a 256 "$(basename "${SOURCE_TAR}")" > "$(basename "${SOURCE_TAR}").sha256")

echo "本地候选包：${ZIP}（${BYTES} 字节，signed_release=${SIGNED}）"
echo "对应源码包：${SOURCE_TAR}（与二进制同处发布，GPL §6(d)）"
if ! ${SIGNED}; then echo "仅供审核；尚未签名/公证，不可对外发布或安装。"; fi
