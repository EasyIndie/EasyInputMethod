#!/usr/bin/env python3
"""Build an isolated website checker; never install it or contact an update feed."""
import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--feed-url')
parser.add_argument('--public-key')
parser.add_argument('--build', default='1')
args = parser.parse_args()
if bool(args.feed_url) != bool(args.public_key):
    parser.error('发布地址和公钥必须同时提供；不提供则构建关闭状态')
scratch = ROOT.parent / 'build/website-updater'
command = ['swift', 'build', '--package-path', str(ROOT), '--scratch-path', str(scratch),
           '-c', 'release', '-Xswiftc', '-warnings-as-errors']
subprocess.run(command, check=True)
folder = subprocess.check_output(command + ['--show-bin-path'], text=True).strip()
app = scratch / 'LampyrisUpdateCheck.app'
contents = app / 'Contents'
binary = contents / 'MacOS/LampyrisUpdateCheck'
binary.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(Path(folder) / 'LampyrisUpdateCheck', binary)
info = {'CFBundleIdentifier': 'cn.jokerhub.Lampyris.WebsiteUpdateCheck',
        'CFBundleExecutable': binary.name, 'CFBundlePackageType': 'APPL',
        'CFBundleVersion': args.build, 'CFBundleShortVersionString': '0.1.0',
        'LSMinimumSystemVersion': '13.0', 'LampyrisDistributionChannel': 'website'}
if args.feed_url:
    info.update(SUFeedURL=args.feed_url, SUPublicEDKey=args.public_key)
(contents / 'Info.plist').write_bytes(plistlib.dumps(info))
resources = contents / 'Resources'
resources.mkdir(exist_ok=True)
for name in ('ORZ-LICENSE', 'PROVENANCE.json'):
    shutil.copy2(ROOT / 'Vendor' / name, resources / name)
print('仅构建独立检查程序，未安装/启动/联网：' + str(app))
