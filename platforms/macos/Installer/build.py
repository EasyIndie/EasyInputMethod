#!/usr/bin/env python3
"""Build the standalone DMG installer app (no network, no Rust dependencies)."""
import plistlib
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))
from release_version import identity

ROOT = Path(__file__).resolve().parent
REPO_ROOT = ROOT.parents[2]
scratch = REPO_ROOT / "platforms/macos/build/installer"
version = identity()
architectures = ["arm64", "x86_64"]
slices = []
for arch in architectures:
    build_dir = scratch / arch
    command = [
        "swift", "build",
        "--package-path", str(ROOT),
        "--scratch-path", str(build_dir),
        "--triple", f"{arch}-apple-macosx13.0",
        "-c", "release",
        "-Xswiftc", "-warnings-as-errors",
        "-Xswiftc", "-strict-concurrency=complete",
    ]
    subprocess.run(command, check=True)
    folder = subprocess.check_output(command + ["--show-bin-path"], text=True).strip()
    slice_path = scratch / f"LampyrisInstaller-{arch}"
    shutil.copy2(Path(folder) / "LampyrisInstaller", slice_path)
    slices.append(slice_path)

app = scratch / "LampyrisInstaller.app"
contents = app / "Contents"
binary = contents / "MacOS/LampyrisInstaller"
binary.parent.mkdir(parents=True, exist_ok=True)
subprocess.run(["lipo", "-create", *map(str, slices), "-output", str(binary)], check=True)
archs = subprocess.check_output(["lipo", "-archs", str(binary)], text=True).split()
if set(archs) != {"arm64", "x86_64"}:
    raise SystemExit(f"安装器不是通用二进制：{archs}")
for slice_path in slices:
    slice_path.unlink()

info = {
    "CFBundleIdentifier": "cn.jokerhub.Lampyris.Installer",
    "CFBundleExecutable": binary.name,
    "CFBundlePackageType": "APPL",
    "CFBundleName": "Lampyris Installer",
    "CFBundleDisplayName": "安装萤火虫",
    "CFBundleVersion": version["build"],
    "CFBundleShortVersionString": version["apple"],
    "LampyrisSemanticVersion": version["version"],
    "CFBundleIconFile": "AppIcon",
    "NSHighResolutionCapable": True,
    "LSMinimumSystemVersion": "13.0",
    "LampyrisDistributionChannel": "website-dmg",
}
(contents / "Info.plist").write_bytes(plistlib.dumps(info))
resources = contents / "Resources"
resources.mkdir(exist_ok=True)
icon = REPO_ROOT / "assets/icons/yinghuo-official-app.icns"
if not icon.is_file():
    raise SystemExit("缺少应用图标 assets/icons/yinghuo-official-app.icns")
shutil.copy2(icon, resources / "AppIcon.icns")
print("仅构建 DMG 安装器（不安装/不联网）：" + str(app))
