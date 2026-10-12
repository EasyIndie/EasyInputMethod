"""Select only an owned IMK source and verify exact restoration; never send keys."""
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import selectors
import shutil
import signal
import subprocess
import sys
import time

spec = importlib.util.spec_from_file_location('isolated', Path(__file__).with_name('isolated-imk.py'))
isolated = importlib.util.module_from_spec(spec)
spec.loader.exec_module(isolated)
LS = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'


def main():
    if len(sys.argv) != 2:
        raise ValueError('必须提供本次独有根目录')
    root = Path(sys.argv[1]).resolve()
    isolated.require_owned(root)
    app = root/'LampyrisIMKTest.app'
    isolated.validate_identity(plistlib.loads((app/'Contents/Info.plist').read_bytes()),
                               isolated.IDENTITY+root.name.removeprefix('lampyris-imk-'))
    binding = app/'Contents/Resources/IMKTestRoot'
    if (binding.is_symlink() or not binding.is_file() or binding.stat().st_uid != os.geteuid()
            or binding.stat().st_mode & 0o777 != 0o600 or Path(binding.read_text()).resolve() != root):
        raise ValueError('实体包私有根声明不符')
    helper = root/'source-state'
    subprocess.run(['swiftc','-O','-warnings-as-errors','-module-cache-path',str(root/'module-cache'),
                    str(isolated.ROOT/'platforms/macos/tests/isolated-imk/source-state.swift'),'-o',str(helper)],check=True)
    evidence = root/'selection-evidence'
    evidence.mkdir(mode=0o700)
    number = 0

    def state(action):
        nonlocal number
        number += 1
        if action in ['select-owned', 'restore-original'] and alias.exists():
            command = [str(alias/'Contents/MacOS/LampyrisIMKTest'), '--source-action', 'select' if action == 'select-owned' else 'restore']
        else:
            command = [str(helper),action,str(root)]
        result = subprocess.run(command,capture_output=True,text=True,timeout=15)
        (evidence/(str(number)+'-'+action+'.json')).write_text(json.dumps({'exit':result.returncode,'stdout':result.stdout,'stderr':result.stderr}))
        if result.returncode:
            raise RuntimeError(result.stderr.strip())
        return {} if result.stdout.startswith("SOURCE ") else json.loads(result.stdout)

    before = state('state')
    journal = root/'selection-state.json'
    with journal.open('x') as stream:
        json.dump(dict(before, identity=isolated.IDENTITY+root.name.removeprefix('lampyris-imk-')),stream)
    journal.chmod(0o600)
    protected = Path.home()/'Library/Application Support/Lampyris'
    def real():
        return {name:(protected/name).read_bytes() if (protected/name).exists() else None for name in ['config.toml','user-dictionary.tsv']}
    real_before = real()
    alias = Path.home()/('Library/Input Methods/LampyrisIMKTest-'+root.name.removeprefix('lampyris-imk-')+'.app')
    process = None
    server_error = None
    created = False
    reader = None
    completed = False
    old_int = signal.getsignal(signal.SIGINT)
    old_term = signal.getsignal(signal.SIGTERM)
    def interrupted(_number,_frame):
        raise KeyboardInterrupt('输入源恢复探针捕获中断')
    signal.signal(signal.SIGINT,interrupted)
    signal.signal(signal.SIGTERM,interrupted)
    try:
        if os.path.lexists(alias):
            raise RuntimeError('已有同名路径，不覆盖')
        shutil.copytree(app,alias)
        created = True
        subprocess.run([LS,'-f',str(alias)],capture_output=True,timeout=15,check=True)
        state('register')
        server_error = (evidence/'server-error.txt').open('w')
        process = subprocess.Popen([str(alias/'Contents/MacOS/LampyrisIMKTest')],stdout=subprocess.PIPE,
                                   stderr=server_error,text=True)
        reader = selectors.DefaultSelector()
        reader.register(process.stdout,selectors.EVENT_READ)
        deadline = time.monotonic()+10
        ready = False
        while time.monotonic()<deadline:
            if reader.select(timeout=.2):
                if process.stdout.readline().strip()==f'READY server {process.pid}':
                    ready = True
                    break
            if process.poll() is not None:
                break
        if not ready:
            raise RuntimeError('隔离服务未READY')
        for mode in ['normal','failure','INT','TERM']:
            try:
                state('select-owned')
                print('SELECTED '+mode,flush=True)
                if mode=='failure':
                    raise RuntimeError('injected failure')
                if mode in ['INT','TERM']:
                    signal.raise_signal(signal.SIGINT if mode=='INT' else signal.SIGTERM)
            except (RuntimeError,KeyboardInterrupt) as error:
                if str(error) not in ['injected failure','输入源恢复探针捕获中断']:
                    raise
            finally:
                state('restore-original')
            restored = state('state')
            if restored['current']!=before['current'] or real()!=real_before:
                raise RuntimeError('原输入源或真实数据不一致')
            print('PASS exact source restoration '+mode,flush=True)
        completed = True
    finally:
        signal.signal(signal.SIGINT,signal.SIG_IGN)
        signal.signal(signal.SIGTERM,signal.SIG_IGN)
        try:
            if created:
                state('restore-original')
                after = state('disable-owned')
                own = {item['id'] for item in after['owned']}
                if after['current']!=before['current'] or set(after['enabled'])-own!=set(before['enabled']):
                    raise RuntimeError('用户状态改变，保留独有资源')
                physical_spec = importlib.util.spec_from_file_location('physical', Path(__file__).with_name('run-physical-source-probe.py'))
                physical = importlib.util.module_from_spec(physical_spec)
                physical_spec.loader.exec_module(physical)
                if alias.is_symlink() or physical.manifest(alias)!=physical.manifest(app):
                    raise RuntimeError('所有权改变，不删除未知路径')
                subprocess.run([LS,'-u',str(alias)],capture_output=True,timeout=15,check=True)
                shutil.rmtree(alias)
                final = state('state')
                if final['current']!=before['current'] or final['enabled']!=before['enabled'] or any(item['enabled'] for item in final['owned']):
                    raise RuntimeError('最终输入源状态未恢复')
        finally:
            if reader is not None:
                reader.close()
            if process is not None and process.poll() is None:
                process.terminate()
                try:process.wait(timeout=5)
                except subprocess.TimeoutExpired:process.kill();process.wait(timeout=5)
            if server_error is not None:
                server_error.close()
            signal.signal(signal.SIGINT,old_int)
            signal.signal(signal.SIGTERM,old_term)
        if real()!=real_before:
            raise RuntimeError('真实数据改变，不覆盖恢复')
    print('PASS final source/enabled set and real data restored; own alias/server cleaned')
    print('RETAINED='+str(root))
    return 0 if completed else 3


if __name__=='__main__':
    try:sys.exit(main())
    except (OSError,ValueError,RuntimeError,KeyboardInterrupt,subprocess.SubprocessError) as error:
        print('BLOCKED：'+str(error),file=sys.stderr)
        sys.exit(3)
