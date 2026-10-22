"""Read product identity from tracked build inputs, never user preferences."""
import argparse
from pathlib import Path
import re
import tomllib

ROOT = Path(__file__).resolve().parents[1]
NUMBER = r"(?:0|[1-9][0-9]*)"
SEMVER = re.compile(rf"({NUMBER}\.{NUMBER}\.{NUMBER})(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?")


def identity(root=ROOT):
    version = tomllib.loads((root / "Cargo.toml").read_text())["workspace"]["package"]["version"]
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
