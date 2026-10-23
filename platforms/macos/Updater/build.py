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
parser = argparse.ArgumentParser()
parser.add_argument('--feed-url')
parser.add_argument('--public-key')
args = parser.parse_args()
version = identity()
if args.feed_url and not args.public_key:
    parser.error('提供发布地址时也必须提供公钥；两者都不提供则构建为默认关闭状态')
scratch = ROOT.parent / 'build/website-updater'
# ime-config 是配置唯一来源，更新程序链接它的静态库读取 update.feed_url。
subprocess.run(['cargo', 'build', '--locked', '--release', '-p', 'ime-ffi'],
               cwd=ROOT.parents[2], check=True)
root = ROOT.parents[2]
command = ['swift', 'build', '--package-path', str(ROOT), '--scratch-path', str(scratch),
           '-c', 'release', '-Xswiftc', '-warnings-as-errors',
           '-Xswiftc', '-strict-concurrency=complete',
           '-Xswiftc', '-I' + str(root / 'crates/ime-ffi/include'),
           '-Xlinker', '-L' + str(root / 'target/release'), '-Xlinker', '-lime_ffi']
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
if args.public_key:
    # 公钥必须来自签名构建元数据；地址缺省用 GitHub 发布源，用户可在设置里覆盖。
    info.update(SUFeedURL=args.feed_url or DEFAULT_FEED, SUPublicEDKey=args.public_key)
(contents / 'Info.plist').write_bytes(plistlib.dumps(info))
resources = contents / 'Resources'
resources.mkdir(exist_ok=True)
for name in ('ORZ-LICENSE', 'PROVENANCE.json'):
    shutil.copy2(ROOT / 'Vendor' / name, resources / name)
print('仅构建独立检查程序，未安装/启动/联网：' + str(app))
