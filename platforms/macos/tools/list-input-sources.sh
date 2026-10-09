#!/usr/bin/env bash
# 编译并运行「列出系统输入源」诊断工具。
#
# 用法：
#   ./platforms/macos/tools/list-input-sources.sh            # 列出所有输入模式
#   ./platforms/macos/tools/list-input-sources.sh lampyris   # 只看含关键字者
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$(mktemp -t list_sources)"
trap 'rm -f "${BIN}"' EXIT

swiftc -O "${SCRIPT_DIR}/list-input-sources.swift" -o "${BIN}"
"${BIN}" --modes "$@"
