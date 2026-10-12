"""Offline product acceptance coverage gate; evidence still needs human review."""
import argparse
import json
from pathlib import Path
import re
import sys

APPLICATIONS = ("TextEdit", "Safari", "Chrome", "VSCode", "WeChat", "Terminal")
REQUIRED = (
    "resource-isolation", "state-restoration", "core-input", "long-composition",
    "undo", "focus", "mode-switch", "sleep-wake", "accessibility",
    "light-dark-layout", "multi-display", "imk-performance", "package-validation",
    "intel-macos13", "arm64-macos27", "independent-reproduction", "one-person-five-days",
) + tuple("application-" + name for name in APPLICATIONS)
STATUSES = ("PASS", "FAIL", "SKIP", "BLOCKED")


def template():
    return {
        "schema": 2,
        "candidate": {"sha256": "", "commit": "", "architectures": [], "signature": ""},
        "environment": {"system": "", "applications": {name: "" for name in APPLICATIONS}},
        "cases": [{"id": name, "status": "BLOCKED", "reason": "尚未执行", "evidence": []}
                  for name in REQUIRED],
    }


def nonempty(value):
    return isinstance(value, str) and bool(value.strip())


def validate(report, base):
    errors = []
    if not isinstance(report, dict) or report.get("schema") != 2:
        return 2, ["报告schema须为2"]
    candidate = report.get("candidate", {})
    environment = report.get("environment", {})
    if not isinstance(candidate, dict) or not isinstance(environment, dict):
        return 2, ["包与环境身份须为对象"]
    for field, pattern in (("sha256", r"[0-9a-f]{64}"), ("commit", r"[0-9a-f]{40}")):
        value = candidate.get(field)
        if not isinstance(value, str) or not re.fullmatch(pattern, value):
            errors.append("候选身份缺失或无效：" + field)
    if candidate.get("architectures") != ["arm64", "x86_64"]:
        errors.append("正式候选须记录arm64与x86_64（按此顺序）")
    if candidate.get("signature") != "developer-id-notarized":
        errors.append("正式候选须记录Developer ID签名与公证")
    if not nonempty(environment.get("system")):
        errors.append("缺少运行系统版本")
    applications = environment.get("applications", {})
    if not isinstance(applications, dict):
        errors.append("应用版本须为对象")
        applications = {}
    for name in APPLICATIONS:
        if not nonempty(applications.get(name)):
            errors.append("缺少应用版本：" + name)
    cases = report.get("cases")
    if not isinstance(cases, list):
        return 2, errors + ["cases须为数组"]
    seen = set()
    counts = dict.fromkeys(STATUSES, 0)
    for case in cases:
        if not isinstance(case, dict):
            errors.append("用例须为对象")
            continue
        name = case.get("id")
        if not isinstance(name, str) or name not in REQUIRED or name in seen:
            errors.append("未知或重复用例ID：" + str(name))
            continue
        seen.add(name)
        status = case.get("status")
        if not isinstance(status, str) or status not in STATUSES:
            errors.append("无效状态：" + name)
            continue
        counts[status] += 1
        if status == "PASS":
            evidence = case.get("evidence")
            if not isinstance(evidence, list) or not evidence:
                errors.append("PASS缺少证据：" + name)
            else:
                for item in evidence:
                    if not nonempty(item) or not (base / item).is_file():
                        errors.append("证据文件不存在：" + name)
        elif not nonempty(case.get("reason")):
            errors.append("非通过项缺少原因：" + name)
    missing = set(REQUIRED) - seen
    if missing:
        errors.append("缺少必测项：" + ", ".join(sorted(missing)))
    summary = "SUMMARY " + " ".join(name.lower() + "=" + str(counts[name]) for name in STATUSES)
    if errors:
        return 2, errors + [summary, "INCOMPLETE：报告身份、格式或证据覆盖不完整"]
    if counts["FAIL"]:
        return 1, [summary, "FAIL：存在失败用例"]
    if counts["BLOCKED"]:
        return 3, [summary, "BLOCKED：必测项受阻"]
    if counts["SKIP"]:
        return 2, [summary, "INCOMPLETE：必测项被跳过"]
    return 0, [summary, "PASS：本报告覆盖门禁通过；证据真实性仍需审核"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("template", "check"))
    parser.add_argument("report", type=Path)
    args = parser.parse_args()
    try:
        if args.action == "template":
            with args.report.open("x", encoding="utf-8") as stream:
                json.dump(template(), stream, ensure_ascii=False, indent=2)
                stream.write("\n")
            print("已创建未验收模板：" + str(args.report))
            return 0
        report = json.loads(args.report.read_text(encoding="utf-8"))
        code, messages = validate(report, args.report.resolve().parent)
        print("\n".join(messages))
        return code
    except (OSError, ValueError) as error:
        print("INCOMPLETE：" + str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
