#!/usr/bin/env python3
"""Build an isolated website checker; never install it or contact an update feed."""
import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))
from release_version import identity

ROOT = Path(__file__).resolve().parent
REPO_ROOT = Path(__file__).resolve().parents[3]
PINNED_PUBLIC_KEY = REPO_ROOT / 'packaging/macos/update-public-key.txt'
parser = argparse.ArgumentParser()
parser.add_argument('--feed-url')
parser.add_argument('--public-key', help='覆盖：默认读取仓库内 packaging/macos/update-public-key.txt')
parser.add_argument('--output', help='输出目录（默认 build/website-updater）')
# ADR-288：仅用于隔离 drill 的测试构建，必须三项齐全，且只会写私有根。
parser.add_argument('--isolated-root', help='测试用私有根（必须已存在、0700、带 owner 标记）')
parser.add_argument('--isolated-identity', help='测试用隔离身份 cn.jokerhub.inputmethod.LampyrisIMKTest.<UUID>')
parser.add_argument('--test-build', help='测试载荷构建号（必须高于当前生产构建）')
parser.add_argument('--current-build', help='隔离更新程序自身构建号（默认 test-build - 1，必须低于 test-build）')
args = parser.parse_args()
ISOLATED_IDENTITY_PREFIX = 'cn.jokerhub.inputmethod.LampyrisIMKTest.'
TEST_UPDATER_PREFIX = 'cn.jokerhub.Lampyris.WebsiteUpdateCheckTest.'
ROOT_PREFIX = 'lampyris-imk-'


def isolated_uuid(value):
    import uuid
    if not value.startswith(ISOLATED_IDENTITY_PREFIX):
        parser.error('隔离身份必须以 ' + ISOLATED_IDENTITY_PREFIX + ' 开头')
    suffix = value.removeprefix(ISOLATED_IDENTITY_PREFIX)
    if str(uuid.UUID(suffix)) != suffix:
        parser.error('隔离身份 UUID 必须是规范小写形式')
    return suffix


def isolated_root(value, suffix):
    """Validate the declared drill root; ownership is re-checked at runtime on the receiving device."""
    import os
    import re
    root = Path(value)
    if not root.is_absolute() or str(root) != os.path.normpath(str(root)):
        parser.error('隔离根必须是规范化的绝对路径')
    if root.name != ROOT_PREFIX + suffix:
        parser.error('隔离根目录名必须与隔离身份 UUID 一致')
    parent = root.parent.as_posix()
    private_t = re.fullmatch(r'/(?:private/)?var/folders/(?:[^/]+/)+T', parent)
    development = re.fullmatch(r'/Users/[^/]+/Library/Application Support/LampyrisIMKDev', parent)
    if not private_t and not development:
        parser.error('隔离根必须位于设备私有临时目录或 LampyrisIMKDev 开发根内')
    if root.exists() or root.is_symlink():
        # 本机演练：提前套用运行时会执行的归属/权限检查；CI 绑定的是接收设备路径，只做形状校验。
        info = root.lstat()
        if root.is_symlink() or not root.is_dir():
            parser.error('隔离根必须是非符号链接目录')
        if info.st_uid != os.geteuid() or info.st_mode & 0o077:
            parser.error('隔离根必须为当前用户所有且权限不宽于 0700')
        marker = root / 'owner'
        if marker.is_symlink() or not marker.is_file() or marker.stat().st_uid != os.geteuid():
            parser.error('隔离根缺少由当前用户拥有的 owner 标记')
        if marker.stat().st_mode & 0o077 or marker.read_text() != root.name:
            parser.error('owner 标记权限或内容不符')
    return root


version = identity()
if not args.public_key and not PINNED_PUBLIC_KEY.is_file():
    parser.error('缺少入库公钥 packaging/macos/update-public-key.txt')
scratch = Path(args.output).resolve() if args.output else ROOT.parent / 'build/website-updater'
# 更新程序必须通用：Intel 机器打开 arm64-only 包会被系统拒绝（报告 167）。
# ime-config 是配置唯一来源，更新程序链接它的静态库读取 update.feed_url。
root = ROOT.parents[2]
architectures = [('arm64', 'aarch64-apple-darwin'), ('x86_64', 'x86_64-apple-darwin')]
slices = []
for arch, triple in architectures:
    subprocess.run(['cargo', 'build', '--locked', '--release', '--target', triple, '-p', 'ime-ffi'],
                   cwd=root, check=True)
    build_dir = scratch / arch
    command = ['swift', 'build', '--package-path', str(ROOT), '--scratch-path', str(build_dir),
               '--triple', f'{arch}-apple-macosx13.0',
               '-c', 'release', '-Xswiftc', '-warnings-as-errors',
               '-Xswiftc', '-strict-concurrency=complete',
               '-Xswiftc', '-I' + str(root / 'crates/ime-ffi/include'),
               '-Xlinker', str(root / 'target' / triple / 'release/libime_ffi.a')]
    subprocess.run(command, check=True)
    folder = subprocess.check_output(command + ['--show-bin-path'], text=True).strip()
    slice_path = scratch / f'LampyrisUpdateCheck-{arch}'
    shutil.copy2(Path(folder) / 'LampyrisUpdateCheck', slice_path)
    slices.append(slice_path)
app = scratch / 'LampyrisUpdateCheck.app'
contents = app / 'Contents'
binary = contents / 'MacOS/LampyrisUpdateCheck'
binary.parent.mkdir(parents=True, exist_ok=True)
subprocess.run(['lipo', '-create', *map(str, slices), '-output', str(binary)], check=True)
archs = subprocess.check_output(['lipo', '-archs', str(binary)], text=True).split()
if set(archs) != {'arm64', 'x86_64'}:
    parser.error(f'更新程序不是通用二进制：{archs}')
for slice_path in slices:
    slice_path.unlink()
info = {'CFBundleIdentifier': 'cn.jokerhub.Lampyris.WebsiteUpdateCheck',
        'CFBundleExecutable': binary.name, 'CFBundlePackageType': 'APPL',
        'CFBundleName': 'Lampyris Update', 'CFBundleDisplayName': '萤火虫更新',
        'CFBundleVersion': version['build'], 'CFBundleShortVersionString': version['apple'],
        'LampyrisSemanticVersion': version['version'], 'CFBundleIconFile': 'AppIcon',
        'NSHighResolutionCapable': True,
        'LSMinimumSystemVersion': '13.0', 'LampyrisDistributionChannel': 'website'}
isolated = any((args.isolated_root, args.isolated_identity, args.test_build))
if isolated:
    if not all((args.isolated_root, args.isolated_identity, args.test_build)):
        parser.error('隔离构建必须同时给出 --isolated-root、--isolated-identity 与 --test-build')
    suffix = isolated_uuid(args.isolated_identity)
    isolated_root(args.isolated_root, suffix)
    if not args.test_build.isdigit() or int(args.test_build) <= int(version['build']):
        parser.error('测试构建号必须是高于当前生产构建的正整数')
    current_build = args.current_build or str(int(args.test_build) - 1)
    if not current_build.isdigit() or not 0 < int(current_build) < int(args.test_build):
        parser.error('更新程序构建号必须是低于测试载荷构建号的正整数')
    info.update(CFBundleIdentifier=TEST_UPDATER_PREFIX + suffix,
                LampyrisTestOnly=True,
                LampyrisIsolatedRoot=str(Path(args.isolated_root)),
                LampyrisIsolatedIdentity=args.isolated_identity,
                CFBundleVersion=current_build,
                CFBundleName='Lampyris Update Test',
                CFBundleDisplayName='萤火虫 更新（测试）')
DEFAULT_FEED = 'https://github.com/EasyIndie/EasyInputMethod/releases/latest/download/appcast.xml'
# 公钥是公开值：默认取自仓库文件（可审计、可离线复验），不依赖 CI 变量/Secret。
public_key = args.public_key or PINNED_PUBLIC_KEY.read_text().strip()
import base64
if len(base64.b64decode(public_key, validate=True)) != 32:
    parser.error('公钥必须是 32 字节 Base64（Ed25519 原始公钥）')
info.update(SUFeedURL=args.feed_url or DEFAULT_FEED, SUPublicEDKey=public_key)
# 发行用更新程序永远不得带上隔离安装绑定；测试构建必须显式请求。
if not isolated:
    for forbidden in ('LampyrisTestOnly', 'LampyrisIsolatedRoot', 'LampyrisIsolatedIdentity'):
        if forbidden in info:
            parser.error('生产更新程序不得包含隔离绑定：' + forbidden)
(contents / 'Info.plist').write_bytes(plistlib.dumps(info))
resources = contents / 'Resources'
resources.mkdir(exist_ok=True)
for name in ('ORZ-LICENSE', 'PROVENANCE.json'):
    shutil.copy2(ROOT / 'Vendor' / name, resources / name)
icon = root / 'assets/icons/yinghuo-official-app.icns'
if not icon.is_file():
    parser.error('缺少应用图标 assets/icons/yinghuo-official-app.icns')
shutil.copy2(icon, resources / 'AppIcon.icns')
print(('仅构建隔离测试检查程序，未安装/启动/联网：' if isolated else '仅构建独立检查程序，未安装/启动/联网：') + str(app))
