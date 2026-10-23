#!/usr/bin/env python3
"""Manage one persistent, privately owned IMK development identity per device."""
import argparse
import hashlib
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import uuid

REPO = Path(__file__).resolve().parents[1]
IDENTITY = 'cn.jokerhub.inputmethod.LampyrisIMKTest.'


def private(path, directory=False):
    stat = path.lstat()
    if path.is_symlink() or stat.st_uid != os.geteuid() or stat.st_mode & 0o077:
        raise ValueError('开发资源归属或权限不符：' + str(path))
    if not (path.is_dir() if directory else path.is_file()):
        raise ValueError('开发资源类型不符：' + str(path))


def owned_root(home, initialize=False):
    parent = home / 'Library/Application Support/LampyrisIMKDev'
    if parent.resolve() != parent:
        raise ValueError('开发父目录不得重定向')
    if initialize and not parent.exists():
        parent.mkdir(mode=0o700)
    private(parent, True)
    roots = list(parent.glob('lampyris-imk-*'))
    if not roots and initialize:
        root = parent / ('lampyris-imk-' + str(uuid.uuid4()))
        root.mkdir(mode=0o700)
        marker = root / 'owner'
        with marker.open('x') as stream:
            stream.write(root.name)
        marker.chmod(0o600)
        roots = [root]
    if len(roots) != 1:
        raise ValueError('需要唯一开发根，不自动清理或选择多个身份')
    root = roots[0]
    suffix = root.name.removeprefix('lampyris-imk-')
    if str(uuid.UUID(suffix)) != suffix:
        raise ValueError('开发UUID不符')
    private(root, True)
    private(root / 'owner')
    if (root / 'owner').read_text() != root.name:
        raise ValueError('开发所有权标记不符')
    for name in ('config.toml', 'user-dictionary.tsv'):
        if os.path.lexists(root / name):
            private(root / name)
    return root


def run(*args):
    return subprocess.check_output(list(map(str, args)), text=True, stderr=subprocess.STDOUT).strip()


def verify_app(app, root):
    if app.is_symlink() or app.resolve() != app:
        raise ValueError('开发包必须为规范路径实体包')
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    identity = IDENTITY + root.name.removeprefix('lampyris-imk-')
    spec = importlib.util.spec_from_file_location('isolated', REPO / 'platforms/macos/tests/isolated-imk.py')
    isolated = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(isolated)
    isolated.validate_identity(info, identity)
    if info.get('LampyrisIMKDevelopment') is not True or info.get('CFBundleExecutable') != 'LampyrisIMKTest':
        raise ValueError('不是固定身份开发包')
    binding = app / 'Contents/Resources/IMKTestRoot'
    private(binding)
    if binding.read_text() != str(root):
        raise ValueError('开发根绑定不符')
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', app)
    signature = run('/usr/bin/codesign', '-dv', '--verbose=4', app)
    if 'Authority=Developer ID Application:' not in signature or 'TeamIdentifier=2N62934Y28' not in signature:
        raise ValueError('不是项目Developer ID签名')
    run('/usr/sbin/spctl', '--assess', '--type', 'execute', '--verbose=2', app)
    run('/usr/bin/xcrun', 'stapler', 'validate', app)
    return info


def state(helper):
    result = json.loads(run(helper))
    if not result.get('current') or not isinstance(result.get('enabled'), list):
        raise ValueError('输入源状态不完整')
    return result


def holders(binary):
    result = subprocess.run(['/usr/sbin/lsof', '-t', str(binary)], text=True, capture_output=True)
    if result.returncode == 1 and not result.stdout and not result.stderr:
        return []
    if result.returncode != 0:
        raise ValueError('无法核对开发包使用进程：' + result.stderr)
    return sorted(set(int(pid) for pid in result.stdout.split()))


def idle(target, stop):
    binary = target / 'Contents/MacOS/LampyrisIMKTest'
    pids = holders(binary)
    if pids and not stop:
        raise ValueError('开发宿主仍在运行；切到ABC、结束组合后使用 --stop-host')
    for pid in pids:
        command = run('/bin/ps', '-p', pid, '-o', 'comm=')
        if command != str(binary):
            raise ValueError('包被非精确开发宿主使用，拒绝终止')
        os.kill(pid, signal.SIGTERM)
    deadline = time.monotonic() + 5
    while holders(binary):
        if time.monotonic() >= deadline:
            raise ValueError('开发宿主未退出或重新启动；不换包')
        time.sleep(0.1)


def install(app, root, home, helper, stop=False):
    # Lock the existing ownership marker without creating another state file.
    with (root / 'owner').open() as marker:
        fcntl.flock(marker, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return replace_package(app, root, home, helper, stop)


MUTABLE_METADATA = {
    'CFBundleVersion', 'CFBundleShortVersionString', 'LampyrisSourceCommit', 'LampyrisSemanticVersion',
    'CFBundleDisplayName', 'tsInputMethodIconFileKey', 'tsInputModeMenuIconFileKey',
    'tsInputModePaletteIconFileKey', 'tsInputModeAlternateMenuIconFileKey',
}


def comparable(info):
    """去掉可演进的显示名/图标/版本字段（含嵌套），其余声明必须逐项一致。"""
    def walk(value):
        if isinstance(value, dict):
            return {key: walk(item) for key, item in value.items() if key not in MUTABLE_METADATA}
        if isinstance(value, list):
            return [walk(item) for item in value]
        return value
    return walk(info)


def replace_package(app, root, home, helper, stop=False):
    info = verify_app(app, root)
    target = home / ('Library/Input Methods/LampyrisIMKTest-' + root.name.removeprefix('lampyris-imk-') + '.app')
    if target.parent.resolve() != target.parent or not target.parent.is_dir():
        raise ValueError('输入法安装父目录不符或不存在')
    before = state(helper)
    if before['current'] in (info['CFBundleIdentifier'], info['CFBundleIdentifier'] + '.default'):
        raise ValueError('开发源正在使用；先结束组合并切到ABC')
    previous = None
    if os.path.lexists(target):
        previous = verify_app(target, root)
        old, new = comparable(previous), comparable(info)
        for key in set(old) | set(new):
            if old.get(key) != new.get(key):
                raise ValueError('输入源声明变化，不能复用已登记身份：' + key)
        idle(target, stop)
    # Staging and backups are outside Input Methods to avoid extra discoverable copies.
    work = Path(tempfile.mkdtemp(prefix='replacement-', dir=root))
    staged = work / 'new.app'
    backup = work / 'previous.app'
    run('/usr/bin/ditto', app, staged)
    verify_app(staged, root)
    if state(helper) != before:
        raise ValueError('准备期间输入源已变化，停止')
    if previous:
        idle(target, False)
        target.rename(backup)
    installed = False
    try:
        staged.rename(target)
        installed = True
        verify_app(target, root)
    except Exception:
        if installed and target.exists():
            target.rename(work / 'rejected.app')
        if backup.exists() and not target.exists():
            backup.rename(target)
        raise
    after = state(helper)
    result = {'root': str(root), 'installed': str(target), 'backup': str(backup) if previous else None,
              'source_commit': info.get('LampyrisSourceCommit'),
              'executable_sha256': hashlib.sha256((target / 'Contents/MacOS/LampyrisIMKTest').read_bytes()).hexdigest(),
              'before': before, 'after': after, 'source_state_unchanged': before == after,
              'native_input_verified': False}
    evidence = work / 'installation.json'
    evidence.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    evidence.chmod(0o600)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if before != after:
        raise ValueError('换包后输入源变化；保留证据，不自动覆盖用户选择')
    print('仅包级换包完成。首次手动添加可能需要注销；已有源请验证新PID/执行SHA及真实输入，尚不能计为免注销验收通过。')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['init', 'root', 'install'])
    parser.add_argument('--app', type=Path)
    parser.add_argument('--stop-host', action='store_true')
    args = parser.parse_args()
    try:
        home = Path.home()
        root = owned_root(home, args.action == 'init')
        if args.action != 'install':
            print(root)
            return 0
        if args.app is None:
            raise ValueError('install需要 --app')
        with tempfile.TemporaryDirectory(prefix='lampyris-dev-state-') as work:
            helper = Path(work) / 'state'
            run('swiftc', '-warnings-as-errors', '-module-cache-path', Path(work) / 'module-cache', REPO / 'platforms/macos/tests/isolated-imk/dev-state.swift', '-o', helper)
            install(args.app.absolute(), root, home, helper, args.stop_host)
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print('BLOCKED：' + str(error), file=sys.stderr)
        return 3


if __name__ == '__main__':
    sys.exit(main())
