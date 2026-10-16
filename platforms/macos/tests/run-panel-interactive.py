"""Create a unique native test app; own its process and files through the session."""
import hashlib
from pathlib import Path
import plistlib
import selectors
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / 'platforms/macos/build/preview/LampyrisPreview.app/Contents/MacOS/LampyrisPreview'
REAL = Path.home() / 'Library/Application Support/Lampyris'


def stamp(path):
    return hashlib.sha256(path.read_bytes()).digest() if path.exists() else None


work = Path(tempfile.mkdtemp(prefix='lampyris-panel-'))
(work / 'owner').write_text(work.name)
(work / 'owner').chmod(0o600)
bundle = 'cn.jokerhub.lampyris.isolatedpanel.' + work.name.removeprefix('lampyris-panel-')
app = work / 'LampyrisIsolated.app'
contents = app / 'Contents'
(contents / 'MacOS').mkdir(parents=True)
(contents / 'Resources').mkdir()
shutil.copy2(SOURCE, contents / 'MacOS/LampyrisIsolated')
(contents / 'Resources/data').symlink_to(ROOT / 'data/generated', target_is_directory=True)
(contents / 'Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': bundle, 'CFBundleExecutable': 'LampyrisIsolated',
    'CFBundleName': 'LampyrisIsolated', 'CFBundlePackageType': 'APPL',
    'NSPrincipalClass': 'NSApplication',
}))
protected = [REAL / 'config.toml', REAL / 'user-dictionary.tsv']
before = [stamp(path) for path in protected]
process = subprocess.Popen([str(contents / 'MacOS/LampyrisIsolated'),
    '--panel-isolation-probe', 'interactive', str(work), str(ROOT / 'data/generated')])
print(f'OWNED_APP={bundle}\nOWNED_PID={process.pid}\nOWNED_ROOT={work}', flush=True)
print('请在隔离窗口点击“输入法菜单”或“偏好设置”；关闭窗口或在此输入 close 结束。', flush=True)
reader = selectors.DefaultSelector()
completed = False
try:
    reader.register(sys.stdin, selectors.EVENT_READ)
    deadline = time.monotonic() + 3600
    while process.poll() is None and time.monotonic() < deadline:
        if reader.select(timeout=0.2):
            if sys.stdin.readline().strip() == 'close':
                completed = True
                break
    if process.poll() is None:
        process.terminate()
        process.wait(timeout=5)
    if [stamp(path) for path in protected] != before:
        raise RuntimeError('protected files changed; no restoration attempted')
    if completed or process.returncode == 0:
        shutil.rmtree(work)
        print('PASS interactive cleanup: owned process exited; real files unchanged', flush=True)
    else:
        raise RuntimeError('interactive session timed out or failed')
finally:
    reader.close()
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
    if work.exists():
        print(f'RETAINED={work}', flush=True)
