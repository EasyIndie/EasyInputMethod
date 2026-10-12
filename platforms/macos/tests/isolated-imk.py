"""Build an owned IMK host without installing or registering an input source."""
import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[3]
IDENTITY = "cn.jokerhub.inputmethod.LampyrisIMKTest."


def validate_identity(info, expected):
    if not expected.startswith(IDENTITY) or ".inputmethod." not in expected:
        raise ValueError("隔离输入法身份必须保留.inputmethod.命名段")
    uuid.UUID(expected.removeprefix(IDENTITY))
    if info.get("CFBundleIdentifier") != expected or info.get("InputMethodConnectionName") != expected + "_Connection":
        raise ValueError("隔离包身份或连接名不符")
    for modes in (info.get("tsInputModeListKey"), info.get("ComponentInputModeDict", {}).get("tsInputModeListKey")):
        if not isinstance(modes, dict) or set(modes) != {expected + ".default"} or modes[expected + ".default"].get("TISInputSourceID") != expected + ".default":
            raise ValueError("隔离输入模式身份不符")


def create():
    root = Path(tempfile.gettempdir()).resolve() / ("lampyris-imk-" + str(uuid.uuid4()))
    root.mkdir(mode=0o700)
    owner = root / "owner"
    owner.write_text(root.name)
    owner.chmod(0o600)
    return root


def bundle(root):
    require_owned(root)
    app = root / "LampyrisIMKTest.app"
    (app / "Contents/MacOS").mkdir(parents=True)
    resources = app / "Contents/Resources"
    resources.mkdir()
    binding = resources / "IMKTestRoot"
    binding.write_text(str(root.resolve()))
    binding.chmod(0o600)
    identity = IDENTITY + root.name.removeprefix("lampyris-imk-")
    info = plistlib.loads((ROOT / "platforms/macos/Info.plist").read_bytes())
    old = info["CFBundleIdentifier"]

    def replace(value):
        if isinstance(value, dict):
            return {key.replace(old, identity): replace(item) for key, item in value.items()}
        if isinstance(value, list):
            return [replace(item) for item in value]
        if isinstance(value, str):
            return value.replace(old, identity)
        return value

    info = replace(info)
    info.update(CFBundleExecutable="LampyrisIMKTest", CFBundleName="LampyrisIMKTest",
                CFBundleDisplayName="萤火虫隔离验收 " + root.name.removeprefix("lampyris-imk-")[:8], InputMethodConnectionName=identity + "_Connection")
    validate_identity(info, identity)
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
    label = info["CFBundleDisplayName"]
    for language in ("en", "zh-Hans"):
        localized = resources / (language + ".lproj")
        localized.mkdir()
        (localized / "InfoPlist.strings").write_text(
            '"CFBundleName" = "' + label + '";\n'
            '"CFBundleDisplayName" = "' + label + '";\n'
            '"' + identity + '.default" = "' + label + '";\n')
    for name in ("wubi86-core.tsv", "pinyin-chars.tsv", "pinyin-core.tsv", "variant-s2t.tsv"):
        shutil.copy2(ROOT / "data/generated" / name, resources / name)
    shutil.copy2(ROOT / "assets/icons/yinghuo-official-app.icns", resources / "Lampyris.icns")
    for source in (ROOT / "platforms/macos/Resources").glob("*.png"):
        shutil.copy2(source, resources / source.name)
    return app


def require_owned(root):
    root = Path(root)
    if root.is_symlink() or not root.is_dir() or root.stat().st_uid != os.geteuid():
        raise ValueError("验收目录归属不符")
    uuid.UUID(root.name.removeprefix("lampyris-imk-"))
    owner = root / "owner"
    if (not root.name.startswith("lampyris-imk-") or owner.is_symlink() or not owner.is_file()
            or owner.stat().st_uid != os.geteuid() or owner.read_text() != root.name):
        raise ValueError("验收所有权标记不符")
    if root.stat().st_mode & 0o077 or owner.stat().st_mode & 0o077:
        raise ValueError("验收资源权限过宽")


def build(root):
    app = bundle(root)
    subprocess.run(["cargo", "build", "--locked", "--release", "-p", "ime-ffi"], cwd=ROOT, check=True)
    sources = sorted(path for path in (ROOT / "platforms/macos/Sources").glob("*.swift") if path.name != "main.swift")
    cache = root / "module-cache"
    cache.mkdir()
    subprocess.run([
        "swiftc", "-O", "-warnings-as-errors", "-module-name", "LampyrisIMKTest",
        "-module-cache-path", str(cache), "-I", str(ROOT / "crates/ime-ffi/include"),
        str(ROOT / "platforms/macos/tests/isolated-imk/main.swift"),
        *map(str, sources), str(ROOT / "target/release/libime_ffi.a"),
        "-framework", "AppKit", "-framework", "InputMethodKit", "-framework", "CoreFoundation",
        "-o", str(app / "Contents/MacOS/LampyrisIMKTest"),
    ], check=True, cwd=ROOT)
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
    return app


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    root = create()
    try:
        app = build(root)
        print("OWNED_ROOT=" + str(root))
        print("OWNED_APP=" + str(app))
        print("仅构建隔离宿主，未注册输入源；验证结束须按所有权清理。")
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print("BLOCKED：" + str(error) + "; RETAINED=" + str(root), file=sys.stderr)
        return 3


if __name__ == "__main__":
    sys.exit(main())
