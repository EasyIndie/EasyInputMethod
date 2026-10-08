#!/usr/bin/env bash
# CI credentials only; never enable shell tracing or upload this temporary directory.
set -euo pipefail
: "${RUNNER_TEMP:?需要 GitHub runner 临时目录}"
WORK="${RUNNER_TEMP}/yinghuo-signing"
KEYCHAIN="${WORK}/signing.keychain-db"
cleanup() {
  if [ -f "${KEYCHAIN}" ]; then security delete-keychain "${KEYCHAIN}" >/dev/null 2>&1 || true; fi
  if [ -d "${WORK}" ]; then rm -rf "${WORK}"; fi
}
if [ "${1:-}" = --cleanup ]; then cleanup; exit 0; fi
[ "$#" -eq 0 ] || { echo "用法：$0 [--cleanup]" >&2; exit 2; }
for name in MACOS_CERTIFICATE_P12_BASE64 MACOS_CERTIFICATE_PASSWORD MACOS_SIGNING_IDENTITY ASC_API_KEY_P8_BASE64 ASC_API_KEY_ID ASC_API_ISSUER_ID; do
  [ -n "${!name:-}" ] || { echo "缺少 CI 配置：${name}；请按 CI-ACCEPTANCE.md 配置" >&2; exit 1; }
done
[[ "${MACOS_SIGNING_IDENTITY}" == 'Developer ID Application: '* ]] || { echo "需要 Developer ID Application 证书" >&2; exit 1; }
[ ! -e "${WORK}" ] || { echo "签名临时目录已存在，请先清理" >&2; exit 1; }
umask 077
mkdir "${WORK}"
trap cleanup EXIT
printf '%s' "${MACOS_CERTIFICATE_P12_BASE64}" | base64 --decode > "${WORK}/certificate.p12"
printf '%s' "${ASC_API_KEY_P8_BASE64}" | base64 --decode > "${WORK}/api-key.p8"
KEYCHAIN_PASSWORD="$(openssl rand -hex 32)"
security create-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}"
security set-keychain-settings -lut 21600 "${KEYCHAIN}"
security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}"
security import "${WORK}/certificate.p12" -P "${MACOS_CERTIFICATE_PASSWORD}" -k "${KEYCHAIN}" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}" >/dev/null
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="${ROOT}/platforms/macos/build/Yinghuo.app"
codesign --force --options runtime --timestamp --keychain "${KEYCHAIN}" --sign "${MACOS_SIGNING_IDENTITY}" "${APP}"
codesign --verify --strict "${APP}"
ditto -c -k --keepParent "${APP}" "${WORK}/notarization.zip"
xcrun notarytool submit "${WORK}/notarization.zip" --key "${WORK}/api-key.p8" --key-id "${ASC_API_KEY_ID}" --issuer "${ASC_API_ISSUER_ID}" --wait --timeout 45m
xcrun stapler staple "${APP}"
xcrun stapler validate "${APP}"
spctl --assess --type execute --verbose=2 "${APP}"
