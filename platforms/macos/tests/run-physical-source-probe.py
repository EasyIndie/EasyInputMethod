"""Compare registration of an owned physical app; never launch, enable or select it."""
import argparse
import hashlib
import importlib.util
import json
import os
import plistlib
from pathlib import Path
import shutil
import signal
import subprocess
import sys

spec = importlib.util.spec_from_file_location('isolated', Path(__file__).with_name('isolated-imk.py'))
isolated = importlib.util.module_from_spec(spec)
spec.loader.exec_module(isolated)
LS = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'


def manifest(app):
    result = {}
    for path in sorted(app.rglob('*')):
        if path.is_symlink():
            raise ValueError('拒绝带软链的包')
        if not path.is_dir() and not path.is_file():
            raise ValueError('拒绝特殊文件')
        result[str(path.relative_to(app))] = [path.stat().st_mode & 0o777,
            hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else 'directory']
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    root = parser.parse_args().root.resolve()
    isolated.require_owned(root)
    app = root / 'LampyrisIMKTest.app'
    suffix = root.name.removeprefix('lampyris-imk-')
    isolated.validate_identity(plistlib.loads((app/'Contents/Info.plist').read_bytes()), isolated.IDENTITY + suffix)
    target = Path.home() / ('Library/Input Methods/LampyrisIMKTest-' + suffix + '.app')
    if os.path.lexists(target) or not target.parent.is_dir():
        raise ValueError('目标已存在或Input Methods目录缺失')
    source = (isolated.ROOT / 'platforms/macos/tests/isolated-imk/source-state.swift').read_text()
    helper_source = root / 'physical-state.swift'
    helper_source.write_text(source)
    helper = root / 'physical-state'
    subprocess.run(['swiftc', '-O', '-warnings-as-errors', '-module-cache-path', str(root/'module-cache'),
                    str(helper_source), '-o', str(helper)], check=True)

    def state(action):
        value = subprocess.run([str(helper), 'state' if action == 'state-after-removal' else action, str(root)], capture_output=True, text=True, timeout=15)
        with (root / (action + '-physical.json')).open('w') as stream:
            json.dump({'exit': value.returncode, 'stdout': value.stdout, 'stderr': value.stderr}, stream)
        if value.returncode:
            raise RuntimeError(value.stderr.strip())
        return json.loads(value.stdout)

    before = state('state')
    original = manifest(app)
    success = False
    created = False
    def interrupted(_number, _frame):
        raise KeyboardInterrupt("捕获中断，清理自己的实体包")

    original_term = signal.signal(signal.SIGTERM, interrupted)
    try:
        target.mkdir(mode=0o700)  # Exclusive ownership before copying.
        created = True
        shutil.copytree(app, target, dirs_exist_ok=True)
        if manifest(target) != original:
            raise RuntimeError('复制包文件树不一致')
        ls = subprocess.run([LS, '-f', str(target)], capture_output=True, text=True, timeout=15)
        (root/'physical-ls.json').write_text(json.dumps({'exit':ls.returncode,'stdout':ls.stdout,'stderr':ls.stderr}))
        if ls.returncode:
            raise RuntimeError('LaunchServices识别实体包失败')
        registered = state('register')
        if registered['current'] != before['current']:
            raise RuntimeError('当前输入源发生变化')
        print('PASS physical registration: ' + str(len(registered['owned'])) + ' owned sources', flush=True)
        success = True
    finally:
        signal.signal(signal.SIGTERM, original_term)
        if created:
            after = state('disable-owned')
            owned_ids = {item['id'] for item in after['owned']}
            if after['current'] != before['current'] or set(after['enabled']) - owned_ids != set(before['enabled']):
                raise RuntimeError('用户输入源状态发生变化，保留资源，不覆盖')
            if target.is_symlink() or manifest(target) != original:
                raise RuntimeError('所有权/启用状态异常，保留实体包')
            subprocess.run([LS, '-u', str(target)], capture_output=True, timeout=15, check=True)
            shutil.rmtree(target)
            final = state('state-after-removal')
            if final['current'] != before['current'] or final['enabled'] != before['enabled'] or any(item['enabled'] for item in final['owned']):
                raise RuntimeError('注销后状态未恢复，保留诊断，不覆盖用户偏好')
            print('Owned physical app removed; original source/enabled set unchanged', flush=True)
    print('RETAINED=' + str(root))
    return 0 if success else 3


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError, KeyboardInterrupt, subprocess.SubprocessError) as error:
        print('BLOCKED：' + str(error), file=sys.stderr)
        sys.exit(3)
