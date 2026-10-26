"""Read product identity from tracked build inputs, never user preferences."""
import argparse
from pathlib import Path
import re

try:  # Python 3.11+ 自带 tomllib；macOS 13 的系统 python3 是 3.9（报告206）
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - 只在旧解释器上走到
    tomllib = None

ROOT = Path(__file__).resolve().parents[1]
NUMBER = r"(?:0|[1-9][0-9]*)"
SEMVER = re.compile(rf"({NUMBER}\.{NUMBER}\.{NUMBER})(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?")


def workspace_version(root=ROOT):
    text = (root / "Cargo.toml").read_text()
    if tomllib is not None:
        return tomllib.loads(text)["workspace"]["package"]["version"]
    # 没有 tomllib 时只取 `[workspace.package]` 里的 version，避免为了本机构建装第三方包。
    section = re.search(r"^\[workspace\.package\](.*?)(?=^\[|\Z)", text, re.S | re.M)
    if section is None:
        raise ValueError("缺少 [workspace.package]")
    version = re.search(r'^version\s*=\s*"([^"]+)"', section.group(1), re.M)
    if version is None:
        raise ValueError("缺少 workspace.package.version")
    return version.group(1)


def identity(root=ROOT):
    version = workspace_version(root)
    match = SEMVER.fullmatch(version)
    if match is None or any(part.isdigit() and len(part) > 1 and part[0] == "0"
                            for part in (match[2] or "").split(".")):
        raise ValueError("产品版本必须符合SemVer")
    build = (root / "packaging/build-number").read_text().strip()
    if not re.fullmatch(r"[1-9][0-9]{0,3}", build):
        raise ValueError("构建号必须为1至9999的独立正整数")
    return {"version": version, "apple": match[1], "build": build}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("field", choices=("version", "apple", "build"))
    args = parser.parse_args()
    print(identity()[args.field])
