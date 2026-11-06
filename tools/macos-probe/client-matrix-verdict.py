#!/usr/bin/env python3
"""客户端矩阵判定（报告234）：必需 = 系统自带应用，可选 = 用户自己装的。

usage: client-matrix-verdict.sh <clients-dir>
输出一行 verdict（PASS … / FAIL … / BLOCKED …），退出码 0 / 1 / 78。
"""
import glob
import json
import os
import sys

PASS_MARK = "你好。"


def main() -> int:
    directory = sys.argv[1] if len(sys.argv) > 1 else ""
    files = sorted(glob.glob(os.path.join(directory, "*.json")))
    if not files:
        print("BLOCKED 没有客户端结果文件")
        return 78

    required_total = required_ok = 0
    optional_pass = optional_skip = optional_fail = 0
    problems = []
    for path in files:
        try:
            data = json.load(open(path, encoding="utf-8"))
        except Exception:
            problems.append(os.path.basename(path))
            continue
        required = data.get("required", True)
        if "SKIP" in str(data.get("status", "")):
            if required:
                print(f"FAIL 必需客户端被跳过：{os.path.basename(path)}")
                return 1
            optional_skip += 1
            continue
        text = " ".join(str(data.get(key, "")) for key in ("value", "title", "file"))
        hit = PASS_MARK in text
        if required:
            required_total += 1
            required_ok += 1 if hit else 0
            if not hit:
                problems.append(os.path.basename(path))
        else:
            optional_pass += 1 if hit else 0
            optional_fail += 0 if hit else 1

    detail = (
        f"必需 {required_ok}/{required_total}，"
        f"可选通过 {optional_pass}、跳过 {optional_skip}、未取证 {optional_fail}"
    )
    if required_total < 2:
        print(f"BLOCKED 必需客户端样本不足（TextEdit/Safari 至少各 1 个）：{detail}")
        return 78
    if required_ok == required_total:
        print(f"PASS ({detail})")
        return 0
    print(f"FAIL 必需客户端未全部通过（{', '.join(problems)}）：{detail}")
    return 1


if __name__ == '__main__':
    raise SystemExit(main())
