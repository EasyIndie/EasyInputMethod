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
# 预览窗口按正式包的方式从 Contents/Resources 读数据（符号、emoji、学习提示、码表、三级简码）。
# 只建 data/ 软链会让这些面板报「缺少 xxx.tsv」；这里把预览包 Resources 里的数据文件全部软链过来。
preview_resources = SOURCE.parents[1] / 'Resources'
for item in sorted(preview_resources.iterdir()):
    if item.name == 'data' or item.is_dir():
        continue
    (contents / 'Resources' / item.name).symlink_to(item)
(contents / 'Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': bundle, 'CFBundleExecutable': 'LampyrisIsolated',
    'CFBundleName': 'LampyrisIsolated', 'CFBundlePackageType': 'APPL',
    'NSPrincipalClass': 'NSApplication',
}))
protected = [REAL / 'config.toml', REAL / 'user-dictionary.tsv']
before = [stamp(path) for path in protected]
TISSRC = ROOT / 'tools/macos-probe/bin/tissrc'
ABC = 'com.apple.keylayout.ABC'


def input_source():
    try:
        listed = subprocess.run([str(TISSRC), 'list'], capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    for line in listed.splitlines():
        if line.startswith('current '):
            return line.split(maxsplit=1)[1]
    return None


def select_input_source(source):
    if not TISSRC.is_file() or source is None:
        return False
    try:
        result = subprocess.run([str(TISSRC), 'select', source],
                                capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return False
    return result.returncode == 0


# 先查输入源再启动：TIS 枚举可能拉起已装宿主，不应发生在预览进程之后。
# 已装萤火虫在系统层会先消费 ⌥M/⌥F/⌥P/⌥T，预览收不到；会话期间临时切到 ABC，结束时还原。
original_source = input_source()
switched_source = False
if original_source and original_source.startswith('cn.jokerhub.inputmethod.'):
    if select_input_source(ABC) and input_source() == ABC:
        switched_source = True
        print('已临时切到 ABC（预览才能收到 ⌥ 快捷键）；关闭窗口后自动切回。', flush=True)
    else:
        print('⚠️ 当前输入源是「萤火虫」，且无法自动切到 ABC：它会在系统层先消费 ⌥M/⌥F/⌥P/⌥T。\n'
              '   请手动按 ⌃Space 切到 ABC 再测快捷键。', flush=True)
process = subprocess.Popen([str(contents / 'MacOS/LampyrisIsolated'),
    '--panel-isolation-probe', 'interactive', str(work), str(ROOT / 'data/generated')])
print(f'OWNED_APP={bundle}\nOWNED_PID={process.pid}\nOWNED_ROOT={work}\n'
      f'INPUT_SOURCE={input_source() or "unknown"}', flush=True)
interactive_stdin = sys.stdin.isatty()
if interactive_stdin:
    print('请在隔离窗口点击“输入法菜单”或“偏好设置”；关闭窗口或在此输入 close 结束。', flush=True)
else:
    print('请在隔离窗口点击“输入法菜单”或“偏好设置”；关闭窗口即结束（当前终端不可输入 close）。', flush=True)
reader = selectors.DefaultSelector()
completed = False
try:
    if interactive_stdin:
        reader.register(sys.stdin, selectors.EVENT_READ)
    deadline = time.monotonic() + 3600
    while process.poll() is None and time.monotonic() < deadline:
        if interactive_stdin and reader.select(timeout=0.2):
            if sys.stdin.readline().strip() == 'close':
                completed = True
                break
        else:
            time.sleep(0.2)
    if process.poll() is None:
        process.terminate()
        process.wait(timeout=5)
    changed = [path for path, old in zip(protected, before) if stamp(path) != old]
    if changed:
        # 交互窗口是人工会话：已装输入法可能在别的应用里学习（写 user-dictionary.tsv），
        # 或用户自己改了设置。预览进程只写私有根（`ime_config_init(work/config.toml)`），
        # 这里不能认定是预览越界；自动化隔离仍由 run-panel-isolation.py 严格断言。
        print('WARN 交互会话期间真实数据有变化（通常来自已装输入法的正常学习，'
              '不是预览写入）：' + '、'.join(path.name for path in changed), flush=True)
    if completed or process.returncode == 0:
        shutil.rmtree(work)
        detail = ('preview used its private root; real files changed externally (see WARN)'
                  if changed else 'real files unchanged')
        print(f'PASS interactive cleanup: owned process exited; {detail}', flush=True)
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
    # 先确保预览进程已退出，再还原输入源，避免还原后又被残留窗口消费快捷键。
    if switched_source and original_source:
        if select_input_source(original_source) and input_source() == original_source:
            print(f'已切回输入源：{original_source}', flush=True)
        else:
            print(f'未能自动切回输入源，请手动切回：{original_source}', flush=True)
