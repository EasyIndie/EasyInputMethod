#!/usr/bin/env bash
# 重建 macOS 应用图标（ICNS）与菜单栏模板图。
#
# ADR-390：
#  - 应用 ICNS 的来源换成 full-bleed 母版 `yinghuo-official-icon.png`。旧来源
#    `yinghuo-official-macos.png` 自带白边圆角，macOS 26 会把这种旧式图标塞进白色托板，
#    用户在 Finder 里看到的是「绿块 + 一圈白」。
#  - 安装器 / 卸载器 / 更新程序各出一张带角色角标的图标（arrow.down / trash /
#    arrow.triangle.2.circlepath），否则四个 app 在 DMG 里长得一模一样。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d -t lampyris-icons)"
trap 'rm -rf "${WORK}"' EXIT
MASTER="${ROOT}/assets/icons/yinghuo-official-icon.png"
[ -f "${MASTER}" ] || { echo "缺少 full-bleed 母版：${MASTER}" >&2; exit 1; }

build_icns() {
  local source="$1" output="$2" set
  set="${WORK}/$(basename "${output}" .icns).iconset"
  mkdir -p "${set}"
  for size in 16 32 128 256 512; do
    sips -z "${size}" "${size}" "${source}" --out "${set}/icon_${size}x${size}.png" >/dev/null
    local double=$((size * 2))
    sips -z "${double}" "${double}" "${source}" --out "${set}/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "${set}" -o "${output}"
}

build_icns "${MASTER}" "${ROOT}/assets/icons/yinghuo-official-app.icns"

for spec in 'installer:arrow.down' 'uninstaller:trash' 'updater:arrow.triangle.2.circlepath'; do
  role="${spec%%:*}"
  symbol="${spec#*:}"
  swift "${ROOT}/tools/render-role-icon.swift" "${MASTER}" "${WORK}/${role}.png" "${symbol}" >/dev/null
  build_icns "${WORK}/${role}.png" "${ROOT}/assets/icons/yinghuo-${role}-app.icns"
done

for spec in '18 LampyrisTemplate.png' '36 LampyrisTemplate@2x.png'; do
  read -r size name <<< "${spec}"
  sips -z "${size}" "${size}" "${ROOT}/assets/icons/menu-v5/yinghuo-menu-v5-master.png" --out "${ROOT}/platforms/macos/Resources/${name}" >/dev/null
done
