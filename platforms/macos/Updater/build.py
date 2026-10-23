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
args = parser.parse_args()
version = identity()
if not args.public_key and not PINNED_PUBLIC_KEY.is_file():
    parser.error('缺少入库公钥 packaging/macos/update-public-key.txt')
scratch = ROOT.parent / 'build/website-updater'
# ime-config 是配置唯一来源，更新程序链接它的静态库读取 update.feed_url。
subprocess.run(['cargo', 'build', '--locked', '--release', '-p', 'ime-ffi'],
               cwd=ROOT.parents[2], check=True)
root = ROOT.parents[2]
command = ['swift', 'build', '--package-path', str(ROOT), '--scratch-path', str(scratch),
           '-c', 'release', '-Xswiftc', '-warnings-as-errors',
           '-Xswiftc', '-strict-concurrency=complete',
           '-Xswiftc', '-I' + str(root / 'crates/ime-ffi/include'),
           '-Xlinker', str(root / 'target/release/libime_ffi.a')]
subprocess.run(command, check=True)
folder = subprocess.check_output(command + ['--show-bin-path'], text=True).strip()
app = scratch / 'LampyrisUpdateCheck.app'
contents = app / 'Contents'
binary = contents / 'MacOS/LampyrisUpdateCheck'
binary.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(Path(folder) / 'LampyrisUpdateCheck', binary)
info = {'CFBundleIdentifier': 'cn.jokerhub.Lampyris.WebsiteUpdateCheck',
        'CFBundleExecutable': binary.name, 'CFBundlePackageType': 'APPL',
        'CFBundleVersion': version['build'], 'CFBundleShortVersionString': version['apple'],
        'LampyrisSemanticVersion': version['version'],
        'LSMinimumSystemVersion': '13.0', 'LampyrisDistributionChannel': 'website'}
DEFAULT_FEED = 'https://github.com/EasyIndie/EasyInputMethod/releases/latest/download/appcast.xml'
# 公钥是公开值：默认取自仓库文件（可审计、可离线复验），不依赖 CI 变量/Secret。
public_key = args.public_key or PINNED_PUBLIC_KEY.read_text().strip()
import base64
if len(base64.b64decode(public_key, validate=True)) != 32:
    parser.error('公钥必须是 32 字节 Base64（Ed25519 原始公钥）')
info.update(SUFeedURL=args.feed_url or DEFAULT_FEED, SUPublicEDKey=public_key)
(contents / 'Info.plist').write_bytes(plistlib.dumps(info))
resources = contents / 'Resources'
resources.mkdir(exist_ok=True)
for name in ('ORZ-LICENSE', 'PROVENANCE.json'):
    shutil.copy2(ROOT / 'Vendor' / name, resources / name)
print('仅构建独立检查程序，未安装/启动/联网：' + str(app))
