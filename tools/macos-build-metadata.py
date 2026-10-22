"""Populate derived Apple build identity while preserving the product contract."""
import argparse
from pathlib import Path
import plistlib
import re
import subprocess
import sys

from release_version import identity

KEYS = ("BuildMachineOSBuild", "DTCompiler", "DTPlatformBuild", "DTPlatformName", "DTPlatformVersion",
        "DTSDKBuild", "DTSDKName", "DTXcode", "DTXcodeBuild")


def contract(info):
    return {key: value for key, value in info.items() if key not in KEYS}


def metadata(sdk, developer, host_build):
    settings = plistlib.loads((sdk / "SDKSettings.plist").read_bytes())
    system = plistlib.loads((sdk / "System/Library/CoreServices/SystemVersion.plist").read_bytes())
    result = {
        "BuildMachineOSBuild": host_build, "DTPlatformName": "macosx",
        "DTPlatformBuild": system["ProductBuildVersion"], "DTSDKBuild": system["ProductBuildVersion"],
        "DTPlatformVersion": settings["Version"], "DTSDKName": settings["CanonicalName"],
    }
    version_file = developer.parent / "version.plist"
    if version_file.is_file():
        version = plistlib.loads(version_file.read_bytes())
        parts = version["CFBundleShortVersionString"].split(".")
        if not all(re.fullmatch(r"\d+", part) for part in parts) or len(parts) > 3:
            raise ValueError("无效Xcode版本")
        parts += ["0"] * (3 - len(parts))
        result["DTXcode"] = str(int(parts[0])) + parts[1] + parts[2]
        result["DTXcodeBuild"] = version["ProductBuildVersion"]
    if not all(isinstance(value, str) and value.strip() for value in result.values()):
        raise ValueError("构建元信息不完整")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("write", "check-contract"))
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    try:
        original = plistlib.loads(args.source.read_bytes())
        version = identity()
        original.update(CFBundleShortVersionString=version["apple"],
                        CFBundleVersion=version["build"], LampyrisSemanticVersion=version["version"])
        if args.action == "check-contract":
            actual = plistlib.loads(args.destination.read_bytes())
            if contract(original) != contract(actual):
                raise ValueError("应用产品契约与源码plist不符")
        else:
            sdk = Path(subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip())
            developer = Path(subprocess.check_output(["xcode-select", "-p"], text=True).strip())
            host = subprocess.check_output(["sw_vers", "-buildVersion"], text=True).strip()
            actual = contract(original)
            actual.update(metadata(sdk, developer, host))
            args.destination.write_bytes(plistlib.dumps(actual, sort_keys=False))
        return 0
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError, plistlib.InvalidFileException) as error:
        print("构建身份核验失败：" + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
