#!/usr/bin/env bash
# 不注销的换包路径：仅用于本地迭代（输入源已移除 + 宿主空闲 + 自己签名的候选包）。
#
# 为什么可以省掉注销：注销只是「让宿主退出」的手段；替换 bundle 时只要没有进程在用旧包，
# 就不存在热替换。脚本按下面的顺序强制这三点，任何一条不满足就停：
#   1) 「萤火虫」不在已启用输入源里（`tissrc list`）；
#   2) 没有 Lampyris 宿主进程，或它确实是空闲孤儿（可用 --stop-host 明确授权终止）；
#   3) 目标包是 Developer ID 签名并通过公证（交给 clean-install.sh 校验）。
#
# 用完必须回到「系统设置 → 键盘 → 文字输入」重新添加「萤火虫」，再 `tissrc select …`。
# 发布验收（用户走正常卸载/安装流程）仍需一次真正的注销，不能用本脚本代替。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP=""
STOP_HOST=false
KEEP_DATA=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --app) [ "$#" -ge 2 ] || { echo "--app 需要路径" >&2; exit 2; }; APP="$2"; shift 2 ;;
    --stop-host) STOP_HOST=true; shift ;;
    --keep-data) KEEP_DATA="--keep-data"; shift ;;
    *) echo "用法：$0 --app <Lampyris.app> [--stop-host] [--keep-data]" >&2; exit 2 ;;
  esac
done
[ -n "${APP}" ] || { echo "用法：$0 --app <Lampyris.app> [--stop-host]" >&2; exit 2; }
[ -d "${APP}" ] || { echo "找不到 ${APP}" >&2; exit 1; }
PROBE="${ROOT}/tools/macos-probe/bin/tissrc"
[ -x "${PROBE}" ] || { echo "先运行：make -C tools/macos-probe" >&2; exit 1; }

SOURCE_ID="cn.jokerhub.inputmethod.Lampyris.default"
echo "▶ 1/4 确认输入源已移除（${SOURCE_ID} 不在启用列表）"
if "${PROBE}" list | grep -qx "enabled ${SOURCE_ID}"; then
  cat >&2 <<TEXT
「萤火虫」仍在已启用输入源里。先在「系统设置 → 键盘 → 文字输入」移除它，
（切换输入源不会被脚本代劳）；移除后再运行本脚本。
TEXT
  exit 3
fi
echo "  已移除 ✔（当前输入源：$("${PROBE}" list | awk '/^current /{print $2}')）"

echo "▶ 2/4 确认没有在用旧包的宿主"
if pgrep -x Lampyris >/dev/null; then
  echo "  宿主仍在运行：$(pgrep -fl Lampyris | tr '\n' ' ')"
  if ! ${STOP_HOST}; then
    echo "  未提供 --stop-host，停止。确认这是空闲孤儿（无客户端/无窗口）后可加 --stop-host 重跑。" >&2
    exit 4
  fi
  pkill -x Lampyris
  for _ in $(seq 1 20); do sleep 0.25; pgrep -x Lampyris >/dev/null || break; done
  pgrep -x Lampyris >/dev/null && { echo "  宿主未退出，停止（不热替换）" >&2; exit 4; }
  echo "  已终止空闲孤儿宿主 ✔"
else
  echo "  无宿主 ✔"
fi

echo "▶ 3/4 全新安装（先移走旧包/旧数据）"
"${ROOT}/scripts/clean-install.sh" --app "${APP}" --input-source-removed ${KEEP_DATA}

echo "▶ 4/4 下一步（脚本不代劳）"
cat <<'TEXT'
  1. 系统设置 → 键盘 → 文字输入 → ＋ → 中文（简体）→「萤火虫」；
  2. tools/macos-probe/bin/tissrc select cn.jokerhub.inputmethod.Lampyris.default
  3. 首次按键前配置未生成；验收完记得把输入源还原成 ABC。
TEXT
