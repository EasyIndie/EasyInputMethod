#!/usr/bin/env python3
"""验收证据索引：把 docs/reviews/ 里的报告按「被验产物执行 SHA」归档（ADR-293）。

为什么需要：以前的口径是"历史 PASS 不继承"，靠时间/版本号判断，同一份产物换台机器、
换个构建号就要全部重跑。ADR-293 改成把证据绑定**产物执行文件 SHA-256**：
只要被验产物的字节没变，这条结论就继续有效；SHA 变了必须重跑。

用法：
  acceptance-evidence.py index [--root .]        # 全部索引（sha → 覆盖到的验收项 → 报告）
  acceptance-evidence.py for <sha> [--root .]    # 某个 SHA 已有哪些证据（也可传前 8 位）
  acceptance-evidence.py current [--root .]      # 本机已装包执行 SHA 的现有证据

判定"覆盖到哪个验收项"用报告里的关键词（见 ITEMS）；这是给人和代理做判断用的索引，
不替代报告本身，也不自动把结论升级为 PASS。
"""
import argparse
import json
import pathlib
import re
import subprocess
import sys

SHA = re.compile(r"\b[0-9a-f]{64}\b")
SHORT = re.compile(r"\b[0-9a-f]{8}(?=[…\s）)]|$)")

# 验收项 → 报告里出现就算"覆盖到"的线索（中文关键词，大小写不敏感）。
ITEMS = {
    "hotkeys": ("快捷键", "热键", "shift 切", "⌥p", "⌥f", "⌥t", "⌥m"),
    "clients": ("客户端", "client matrix", "文本编辑/safari", "safari"),
    "quality": ("质量样本", "quality-samples"),
    "memory": ("内存门禁", "memory-gate", "adr-263", "adr-292"),
    "soak": ("久用", "soak"),
    "network": ("零外联", "外联", "tcp/udp", "0 条"),
    "voiceover": ("voiceover", "播报", "axannouncementrequested"),
    "sleep": ("睡眠", "唤醒", "sleep-test"),
    "multi-display": ("多屏", "缩放", "热插拔", "multi-display"),
    "spaces": ("多 space", "桌面"),
    "install": ("卸载", "重装", "安装", "reinstall"),
    "repro": ("离线重建", "复现", "run-repro", "it-15"),
    "accessibility": ("辅助功能", "ax 树", "axselectedchildren"),
}

APP = pathlib.Path.home() / "Library/Input Methods/Lampyris.app/Contents/MacOS/Lampyris"


def installed_sha():
    if not APP.is_file():
        return None
    result = subprocess.run(["shasum", "-a", "256", str(APP)], capture_output=True, text=True, check=False)
    return result.stdout.split()[0] if result.returncode == 0 else None


def reports(root):
    """只扫描 docs/reviews 下的正式报告，跳过 history 与模板。"""
    directory = root / "docs/reviews"
    if not directory.is_dir():
        return []
    files = []
    for path in sorted(directory.glob("*.md")):
        if path.name.startswith("TEMPLATE") or "history" in path.parts:
            continue
        files.append(path)
    return files


def index(root):
    entries = {}
    for path in reports(root):
        text = path.read_text(encoding="utf-8", errors="replace")
        lowered = text.lower()
        shas = sorted(set(SHA.findall(text)))
        if not shas:
            # 只写了前 8 位的报告（早期报告常见）：记到短 SHA 名下，供模糊查询。
            shas = sorted({"short:" + s for s in set(SHORT.findall(text))})
        items = sorted(name for name, words in ITEMS.items() if any(word in lowered for word in words))
        title = next((line.lstrip("# ").strip() for line in text.splitlines() if line.startswith("# ")), path.stem)
        for sha in shas:
            entries.setdefault(sha, []).append({
                "report": str(path.relative_to(root)),
                "title": title,
                "items": items,
            })
    return entries


def cmd_index(root, as_json):
    data = index(root)
    if as_json:
        print(json.dumps({k: v for k, v in sorted(data.items())}, ensure_ascii=False, indent=2))
        return 0
    for sha, rows in sorted(data.items()):
        print(sha)
        for row in rows:
            print(f"  {row['report']}: {', '.join(row['items']) or '(未识别)'}")
    return 0


def cmd_for(root, wanted, as_json):
    wanted = wanted.strip().lower()
    data = index(root)
    hits = {}
    for sha, rows in data.items():
        key = sha.removeprefix("short:")
        # 双向前缀匹配：报告里可能只写了前 8 位（`a165f05c…`），查询可能给全 64 位。
        if key == wanted or (len(wanted) >= 8 and (key.startswith(wanted) or wanted.startswith(key))):
            hits[sha] = rows
    covered = sorted({item for rows in hits.values() for row in rows for item in row["items"]})
    missing = sorted(set(ITEMS) - set(covered))
    payload = {"sha": wanted, "reports": hits, "covered": covered, "missing": missing}
    if as_json:
        print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print(f"执行 SHA {wanted}")
        if not hits:
            print("  没有找到这个 SHA 的任何报告 → 需要用完整验收跑一遍")
        for sha, rows in sorted(hits.items()):
            for row in rows:
                print(f"  {row['report']}: {', '.join(row['items']) or '(未识别)'}")
        print("  已有证据: " + (", ".join(covered) or "无"))
        print("  仍缺: " + (", ".join(missing) or "无"))
    return 0 if hits else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("action", choices=("index", "for", "current"))
    parser.add_argument("sha", nargs="?")
    parser.add_argument("--root", type=pathlib.Path, default=pathlib.Path(__file__).resolve().parents[1])
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    if args.action == "index":
        return cmd_index(args.root, args.json)
    if args.action == "for":
        if not args.sha:
            print("用法：acceptance-evidence.py for <sha>", file=sys.stderr)
            return 2
        return cmd_for(args.root, args.sha, args.json)
    sha = installed_sha()
    if not sha:
        print("本机未找到已安装的 Lampyris.app", file=sys.stderr)
        return 2
    return cmd_for(args.root, sha, args.json)


if __name__ == "__main__":
    sys.exit(main())
