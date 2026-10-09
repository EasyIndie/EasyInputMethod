#!/usr/bin/env bash
# Local signing is separate from explicit Apple submission.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="${ROOT}/platforms/macos/build/Lampyris.app"
case "${1:-}" in
  --sign)
    [ "$#" -eq 2 ] || { echo "用法：$0 --sign 'Developer ID Application: …'" >&2; exit 2; }
    [[ "$2" == 'Developer ID Application: '* ]] || { echo "需要 Developer ID Application 身份" >&2; exit 2; }
    codesign --force --options runtime --timestamp --sign "$2" "${APP}"
    codesign --verify --strict --verbose=2 "${APP}"
    ;;
  --submit)
    [ "$#" -eq 2 ] || { echo "用法：$0 --submit <钥匙串凭据名>（会上传 Apple）" >&2; exit 2; }
    codesign --verify --strict "${APP}"
    DETAILS="$(codesign -dv --verbose=4 "${APP}" 2>&1)"
    [[ "${DETAILS}" == *"Authority=Developer ID Application:"* ]] || { echo "不是 Developer ID 签名" >&2; exit 1; }
    [[ "${DETAILS}" == *"runtime"* ]] || { echo "缺少 hardened runtime" >&2; exit 1; }
    WORK="$(mktemp -d -t lampyris-notary)"
    trap 'rm -rf "${WORK}"' EXIT
    ditto -c -k --keepParent "${APP}" "${WORK}/Lampyris.zip"
    xcrun notarytool submit "${WORK}/Lampyris.zip" --keychain-profile "$2" --wait
    xcrun stapler staple "${APP}"
    xcrun stapler validate "${APP}"
    spctl --assess --type execute --verbose=2 "${APP}"
    ;;
  *) echo "用法：$0 --sign <身份> | --submit <凭据名>" >&2; exit 2 ;;
esac
