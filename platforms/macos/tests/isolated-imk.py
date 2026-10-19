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
TRIPLES = {"arm64": "aarch64-apple-darwin", "x86_64": "x86_64-apple-darwin"}
DEPLOYMENT_TARGET = "13.0"


def host_arch():
    machine = subprocess.check_output(["uname", "-m"], text=True).strip()
    if machine not in TRIPLES:
        raise ValueError("不支持的宿主架构：" + machine)
    return machine


def build_arches(value):
    """把架构要求解析为要构建的切片；native 表示只构建宿主架构。"""
    if value in ("", "native"):
        return [host_arch()]
    if value == "universal":
        return ["arm64", "x86_64"]
    if value in TRIPLES:
        return [value]
    raise ValueError("不支持的架构要求：" + value)


def macho_arches(binary):
    return subprocess.check_output(["lipo", "-archs", str(binary)], text=True).split()


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


def build(root, arch="native"):
    app = bundle(root)
    slices = build_arches(arch)
    # 只构建宿主自身架构时沿用默认 target 目录，保持既有本地探针行为不变。
    native_only = len(slices) == 1 and slices[0] == host_arch()
    sources = sorted(path for path in (ROOT / "platforms/macos/Sources").glob("*.swift") if path.name != "main.swift")
    include = str(ROOT / "crates/ime-ffi/include")
    cache = root / "module-cache"
    cache.mkdir()
    # 慢机器（如 A/Intel + 老工具链）可设 LAMPYRIS_IMK_TEST_OPT=-Onone 缩短编译时间；
    # 该产物只用于协议/注册验证，不用于性能结论，默认仍为 -O。
    opt = os.environ.get("LAMPYRIS_IMK_TEST_OPT", "-O").split()
    executables = []
    for slice_arch in slices:
        triple = TRIPLES[slice_arch]
        target_args = [] if native_only else ["--target", triple]
        library = ROOT / ("target/release" if native_only else "target/" + triple + "/release") / "libime_ffi.a"
        subprocess.run(["cargo", "build", "--locked", "--release", *target_args, "-p", "ime-ffi"], cwd=ROOT, check=True)
        if not library.is_file():
            raise ValueError("缺少 staticlib " + str(library) + "；跨架构构建需先 rustup target add " + triple)
        slice_cache = cache / slice_arch
        slice_cache.mkdir()
        executable = app / ("Contents/MacOS/LampyrisIMKTest-" + slice_arch)
        subprocess.run([
            "swiftc", *opt, "-warnings-as-errors", "-target", slice_arch + "-apple-macosx" + DEPLOYMENT_TARGET,
            "-module-name", "LampyrisIMKTest", "-module-cache-path", str(slice_cache), "-I", include,
            str(ROOT / "platforms/macos/tests/isolated-imk/main.swift"),
            *map(str, sources), str(library),
            "-framework", "AppKit", "-framework", "InputMethodKit", "-framework", "CoreFoundation",
            "-o", str(executable),
        ], check=True, cwd=ROOT)
        executables.append(executable)
    binary = app / "Contents/MacOS/LampyrisIMKTest"
    if len(executables) == 1:
        executables[0].rename(binary)
    else:
        subprocess.run(["lipo", "-create", *map(str, executables), "-output", str(binary)], check=True)
        for executable in executables:
            executable.unlink()
    if sorted(macho_arches(binary)) != sorted(slices):
        raise ValueError("产物架构与要求不符：" + " ".join(macho_arches(binary)))
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
