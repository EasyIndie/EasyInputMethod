#!/bin/bash
# 走查取证：把当前安装身份、数据指纹与输入源状态一次采集，供 IT-22/IT-23 记录引用。
# 只读取，不修改任何文件；输出同时写到 stdout 与一个带时间戳的文件。
#
# 用法：tools/macos-probe/walkthrough-evidence.sh [--label 名称]
set -uo pipefail

label="walkthrough"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --label) [ "$#" -ge 2 ] || { echo "用法：$0 [--label 名称]" >&2; exit 2; }; label="$2"; shift 2 ;;
    *) echo "用法：$0 [--label 名称]" >&2; exit 2 ;;
  esac
done

host_app="$HOME/Library/Input Methods/Lampyris.app"
updater_app="$HOME/Applications/LampyrisUpdateCheck.app"
support="$HOME/Library/Application Support/Lampyris"
probe_dir="$(cd "$(dirname "$0")" && pwd)"
out_dir="${TMPDIR:-/tmp}/lampyris-evidence"
mkdir -p "$out_dir"
out="$out_dir/${label}-$(date -u +%Y%m%dT%H%M%SZ).txt"

plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null || echo "?"; }
sha() { [ -e "$1" ] && shasum -a 256 "$1" | awk '{print $1}' || echo "absent"; }

{
  echo "# 萤火虫走查取证（${label}）"
  echo "generated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "macos=$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
  echo "arch=$(uname -m)"
  echo
  echo "## 已安装身份"
  if [ -d "$host_app" ]; then
    echo "host_version=$(plist "$host_app" CFBundleShortVersionString)/$(plist "$host_app" CFBundleVersion)"
    echo "host_exec_sha256=$(sha "$host_app/Contents/MacOS/Lampyris")"
    echo "host_identifier=$(plist "$host_app" CFBundleIdentifier)"
  else
    echo "host=absent"
  fi
  if [ -d "$updater_app" ]; then
    echo "updater_version=$(plist "$updater_app" CFBundleShortVersionString)/$(plist "$updater_app" CFBundleVersion)"
    echo "updater_exec_sha256=$(sha "$updater_app/Contents/MacOS/LampyrisUpdateCheck")"
  else
    echo "updater=absent"
  fi
  echo "host_pid=$(pgrep -f 'Input Methods/Lampyris.app/Contents/MacOS/Lampyris' | tr '\n' ' ')"
  echo "voiceover_pid=$(pgrep -x VoiceOver | tr '\n' ' ')"
  echo
  echo "## 用户数据指纹"
  echo "config_sha256=$(sha "$support/config.toml")"
  if [ -e "$support/user-dictionary.tsv" ]; then
    echo "dictionary_lines=$(wc -l < "$support/user-dictionary.tsv" | tr -d ' ')"
    echo "dictionary_sha256=$(sha "$support/user-dictionary.tsv")"
  else
    echo "dictionary=absent"
  fi
  echo "state_dirs=$(ls -1 "$support" 2>/dev/null | grep -E '^(uninstalled|updates)$' | tr '\n' ' ')"
  echo
  echo "## 输入源"
  if [ -x "$probe_dir/bin/tissrc" ]; then
    "$probe_dir/bin/tissrc" list
  else
    echo "tissrc=missing"
  fi
} > "$out" 2>&1

cat "$out"
echo
echo "EVIDENCE=$out"
