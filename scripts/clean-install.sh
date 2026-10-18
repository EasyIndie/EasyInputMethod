#!/usr/bin/env bash
# 登录后一条命令完成「全新安装」：卸载旧包（可一并清数据）→ 安装新包 → 校验。
# 注销前必须先切到 ABC 并在系统设置移除萤火虫（脚本无法代替这一步）。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP=""
DRY=false
REMOVED=false
KEEP=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --app) [ "$#" -ge 2 ] || { echo "--app 需要路径" >&2; exit 2; }; APP="$2"; shift 2 ;;
    --dry-run) DRY=true; shift ;;
    --input-source-removed) REMOVED=true; shift ;;
    --keep-data) KEEP=true; shift ;;
    *) echo "用法：$0 --app <Lampyris.app> [--dry-run] [--input-source-removed] [--keep-data]" >&2; exit 2 ;;
  esac
done
[ -n "${APP}" ] || { echo "用法：$0 --app <Lampyris.app> [--dry-run] [--input-source-removed] [--keep-data]" >&2; exit 2; }
[ -d "${APP}" ] || { echo "找不到 ${APP}" >&2; exit 1; }
DATA_FLAG="--purge-data"
${KEEP} && DATA_FLAG=""

echo "▶ 1/3 卸载旧包${DATA_FLAG:+（含清理旧配置与词库）}"
if ${DRY}; then
  "${ROOT}/platforms/macos/uninstall.sh" --dry-run ${DATA_FLAG}
else
  ${REMOVED} || {
    cat >&2 <<'TEXT'
请先完成两步，再退出登录（这样脚本才安全）：
  1. 切到 ABC；
  2. 系统设置 → 键盘 → 文字输入 → 移除「萤火虫」；
重新登录后运行：
  scripts/clean-install.sh --app <新包路径> --input-source-removed
TEXT
    exit 2
  }
  "${ROOT}/platforms/macos/uninstall.sh" --input-source-removed ${DATA_FLAG}
fi

echo "▶ 2/3 安装新包"
if ${DRY}; then
  "${ROOT}/platforms/macos/install.sh" --app "${APP}" --dry-run || \
    echo "（预检提示：当前已装其它版本，正式执行时第 1 步会先移走它）"
else
  "${ROOT}/platforms/macos/install.sh" --app "${APP}"
fi

echo "▶ 3/3 校验已安装产物"
DEST="${HOME}/Library/Input Methods/Lampyris.app"
if ${DRY}; then
  echo "（预检结束，未改动安装目录）"
  exit 0
fi
[ -d "${DEST}" ] || { echo "安装后未找到 ${DEST}" >&2; exit 1; }
codesign --verify --deep --strict "${DEST}"
xcrun stapler validate "${DEST}" >/dev/null
spctl -a -vvv -t install "${DEST}" 2>&1 | head -3
echo "执行 SHA：$(shasum -a 256 "${DEST}/Contents/MacOS/Lampyris" | awk '{print $1}')"

echo "▶ 输入源"
if [ -x "${ROOT}/tools/macos-probe/bin/selsrc" ]; then
  "${ROOT}/tools/macos-probe/bin/selsrc" cn.jokerhub.inputmethod.Lampyris.default || {
    echo "未能自动选中输入源：请在系统设置 → 键盘 → 文字输入 里添加「萤火虫」。"
  }
else
  echo "未找到探针（make -C tools/macos-probe）；请在系统设置里添加并选中「萤火虫」。"
fi

CONFIG="${HOME}/Library/Application Support/Lampyris/config.toml"
if [ -e "${CONFIG}" ]; then
  echo "配置：${CONFIG}（$(shasum -a 256 "${CONFIG}" | cut -c1-16)…）"
else
  echo "配置：尚未生成——首次按键/改设置时按 Schema 默认值创建（⌥M / ⌥Space / ⌥P / ⌥T / ⌥, / ⌥A，中英为单独 ⇧）"
fi
echo "✅ 全新安装完成。下一步：打开自建 TextEdit 文档按键一次，核对菜单右侧快捷键与 wq/nihao 输入。"
