#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d -t yinghuo-icons)"
trap 'rm -rf "${WORK}"' EXIT
SET="${WORK}/Yinghuo.iconset"
mkdir "${SET}"
for size in 16 32 128 256 512; do
  sips -z "${size}" "${size}" "${ROOT}/assets/icons/yinghuo-official-icon.png" --out "${SET}/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "${double}" "${double}" "${ROOT}/assets/icons/yinghuo-official-icon.png" --out "${SET}/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "${SET}" -o "${ROOT}/assets/icons/yinghuo-official-app.icns"
for spec in '18 YinghuoTemplate.png' '36 YinghuoTemplate@2x.png'; do
  read -r size name <<< "${spec}"
  sips -z "${size}" "${size}" "${ROOT}/assets/icons/menu-v5/yinghuo-menu-v5-master.png" --out "${ROOT}/platforms/macos/Resources/${name}" >/dev/null
done
