#!/usr/bin/env bash
# CI credentials only; never enable shell tracing or upload this temporary directory.
set -euo pipefail
: "${RUNNER_TEMP:?需要 GitHub runner 临时目录}"
WORK="${RUNNER_TEMP}/lampyris-signing"
KEYCHAIN="${WORK}/signing.keychain-db"
ORIGINAL_KEYCHAINS=()
SEARCH_LIST_CHANGED=0
cleanup() {
  if [ "${SEARCH_LIST_CHANGED}" -eq 1 ]; then
    security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" >/dev/null 2>&1 || true
  fi
  if [ -f "${KEYCHAIN}" ]; then security delete-keychain "${KEYCHAIN}" >/dev/null 2>&1 || true; fi
  if [ -d "${WORK}" ]; then rm -rf "${WORK}"; fi
}
if [ "${1:-}" = --cleanup ]; then cleanup; exit 0; fi
APP="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/platforms/macos/build/Lampyris.app"
if [ "${1:-}" = --app ]; then
  [ "$#" -eq 2 ] || { echo "用法：$0 [--cleanup] [--app <path.app>]" >&2; exit 2; }
  APP="$2"
elif [ "$#" -ne 0 ]; then
  echo "用法：$0 [--cleanup] [--app <path.app>]" >&2; exit 2
fi
[ -d "${APP}" ] || { echo "待签名 app 不存在：${APP}" >&2; exit 1; }
ASC_API_KEY_P8="${ASC_API_KEY_P8:-${ASC_API_KEY_P8_BASE64:-}}"
MISSING=()
for name in MACOS_CERTIFICATE_P12_BASE64 MACOS_CERTIFICATE_PASSWORD MACOS_SIGNING_IDENTITY ASC_API_KEY_P8 ASC_API_KEY_ID ASC_API_ISSUER_ID; do
  [ -n "${!name:-}" ] || MISSING+=("${name}")
done
if [ "${#MISSING[@]}" -gt 0 ]; then
  echo "缺少 CI 配置：${MISSING[*]}；请按 CI-ACCEPTANCE.md 一次配置" >&2
  exit 1
fi
[[ "${MACOS_SIGNING_IDENTITY}" == 'Developer ID Application: '* ]] || { echo "需要 Developer ID Application 证书" >&2; exit 1; }
[ ! -e "${WORK}" ] || { echo "签名临时目录已存在，请先清理" >&2; exit 1; }
umask 077
mkdir "${WORK}"
trap cleanup EXIT
printf '%s' "${MACOS_CERTIFICATE_P12_BASE64}" | base64 --decode > "${WORK}/certificate.p12"
if [[ "${ASC_API_KEY_P8}" == *'-----BEGIN PRIVATE KEY-----'* ]]; then
  printf '%s\n' "${ASC_API_KEY_P8}" > "${WORK}/api-key.p8"
else
  printf '%s' "${ASC_API_KEY_P8}" | base64 --decode > "${WORK}/api-key.p8"
fi
KEYCHAIN_PASSWORD="$(openssl rand -hex 32)"
while IFS= read -r keychain; do
  [ -n "${keychain}" ] && ORIGINAL_KEYCHAINS+=("${keychain}")
done < <(security list-keychains -d user | sed 's/^[[:space:]]*"//;s/"[[:space:]]*$//')
security create-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}"
security set-keychain-settings -lut 21600 "${KEYCHAIN}"
security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}"
security import "${WORK}/certificate.p12" -P "${MACOS_CERTIFICATE_PASSWORD}" -k "${KEYCHAIN}" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}" >/dev/null
SEARCH_LIST_CHANGED=1
security list-keychains -d user -s "${KEYCHAIN}" "${ORIGINAL_KEYCHAINS[@]}"
# Public certificate names, fingerprints and validation errors only; no key export.
security find-identity -p codesigning "${KEYCHAIN}"
IDENTITY_HASH="$(security find-identity -v -p codesigning "${KEYCHAIN}" | awk -F '"' -v name="${MACOS_SIGNING_IDENTITY}" '$2 == name {split($1, fields, /[[:space:]]+/); for (i in fields) if (fields[i] ~ /^[0-9A-Fa-f]+$/ && length(fields[i]) == 40) print fields[i]}')"
[[ "${IDENTITY_HASH}" =~ ^[0-9A-Fa-f]{40}$ ]] || { echo "找不到唯一有效签名身份，请检查证书名称/有效性" >&2; exit 1; }
codesign --force --options runtime --timestamp --keychain "${KEYCHAIN}" --sign "${IDENTITY_HASH}" "${APP}"
codesign --verify --strict "${APP}"
ditto -c -k --keepParent "${APP}" "${WORK}/notarization.zip"
xcrun notarytool submit "${WORK}/notarization.zip" --key "${WORK}/api-key.p8" --key-id "${ASC_API_KEY_ID}" --issuer "${ASC_API_ISSUER_ID}" --wait --timeout 45m
xcrun stapler staple "${APP}"
xcrun stapler validate "${APP}"
spctl --assess --type execute --verbose=2 "${APP}"
