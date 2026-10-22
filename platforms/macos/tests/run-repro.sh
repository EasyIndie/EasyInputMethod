#!/usr/bin/env bash
# Rebuild a locally prepared release archive from its paired source package.
# Never installs its application.
set -euo pipefail
[ "$#" -eq 1 ] || { echo "用法：$0 <本项目候选 ZIP>" >&2; exit 2; }
ZIP="$1"
VERSION="$(basename "${ZIP}" | sed -E 's/^Lampyris-(.+)-(universal|arm64|x86_64)\.zip$/\1/')"
# 对应源码包与二进制同处发布（GPL-3.0 §6(d)，ADR-064）。
SRC="$(dirname "${ZIP}")/Lampyris-${VERSION}-source.tar.gz"
[ -f "${SRC}" ] || { echo "找不到对应源码包：${SRC}" >&2; exit 1; }
WORK="$(mktemp -d -t lampyris-repro)"
trap 'rm -rf "${WORK}"' EXIT
(cd "$(dirname "${SRC}")" && shasum -a 256 -c "$(basename "${SRC}").sha256")
tar -xzf "${SRC}" -C "${WORK}"
SOURCE="${WORK}/Lampyris-${VERSION}-source"
[ -d "${SOURCE}" ] || { echo "源码包结构异常" >&2; exit 1; }
ditto -x -k "${ZIP}" "${WORK}/zip"
PACKAGE="$(find "${WORK}/zip" -maxdepth 1 -type d -name "Lampyris-${VERSION}-*" | head -1)"
[ -n "${PACKAGE}" ] || { echo "解包后找不到 Lampyris-${VERSION}-* 候选目录" >&2; exit 1; }
python3 - "${PACKAGE}" <<'PY'
import hashlib, json, os, sys
from pathlib import Path
root = Path(sys.argv[1]).resolve()
for line in (root / 'SHA256SUMS').read_text().splitlines():
    digest, name = line.split('  ', 1)
    path = root / name
    if not path.resolve().is_relative_to(root):
        raise SystemExit(f'越界附件：{name}')
    if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        raise SystemExit(f'校验和错误：{name}')
links = root / 'SYMLINKS.json'
if links.exists():
    for name, target in json.loads(links.read_text()).items():
        path = root / name
        if not path.is_symlink() or os.readlink(path) != target or not path.resolve().is_relative_to(root):
            raise SystemExit(f'软链错误：{name}')
print('候选文件校验通过')
PY
(cd "${SOURCE}" && CARGO_NET_OFFLINE=true \
  CLANG_MODULE_CACHE_PATH="${WORK}/module-cache" ./platforms/macos/build.sh --strict --universal)
BUILT="${SOURCE}/platforms/macos/build/Lampyris.app"
cp "${PACKAGE}/Lampyris.app/Contents/MacOS/Lampyris" "${WORK}/expected"
cp "${BUILT}/Contents/MacOS/Lampyris" "${WORK}/rebuilt"
codesign --remove-signature "${WORK}/expected"
codesign --remove-signature "${WORK}/rebuilt"
cmp "${WORK}/expected" "${WORK}/rebuilt"
for name in wubi86-core.tsv pinyin-chars.tsv pinyin-core.tsv; do
  cmp "${PACKAGE}/Lampyris.app/Contents/Resources/${name}" "${BUILT}/Contents/Resources/${name}"
done
shasum -a 256 "${WORK}/rebuilt"
echo "离线源码重建成功；去签名可执行文件与默认数据逐字节一致。"
