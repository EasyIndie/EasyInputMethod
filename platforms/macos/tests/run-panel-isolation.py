"""Native resource isolation probe; does not automate the installed input method."""
import hashlib
from pathlib import Path
import selectors
import shutil
import signal
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[3]
BINARY = ROOT / 'platforms/macos/build/preview/LampyrisPreview.app/Contents/MacOS/LampyrisPreview'
REAL = Path.home() / 'Library/Application Support/Lampyris'


def stamp(path):
    return hashlib.sha256(path.read_bytes()).digest() if path.exists() else None


def run(mode):
    work = Path(tempfile.mkdtemp(prefix='lampyris-panel-'))
    (work / 'owner').write_text(work.name)
    (work / 'owner').chmod(0o600)
    # These names were previously used by the unsafe script. Preserve both states.
    sentinel = work / 'lampyris-panel-export.tsv'
    sentinel.write_bytes(b'existing user export\x00')
    absent = work / 'lampyris-panel-bad.tsv'
    protected = [REAL / 'config.toml', REAL / 'user-dictionary.tsv', sentinel, absent]
    before = [stamp(path) for path in protected]
    process = None
    try:
        process = subprocess.Popen(
            [str(BINARY), '--panel-isolation-probe', mode, str(work), str(ROOT / 'data/generated')],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        reader = selectors.DefaultSelector()
        reader.register(process.stdout, selectors.EVENT_READ)
        deadline = time.monotonic() + 15
        ready = False
        while time.monotonic() < deadline and not ready:
            if reader.select(timeout=0.2):
                line = process.stdout.readline().strip()
                if line == f'READY {process.pid}':
                    ready = True
            if process.poll() is not None and not ready:
                raise RuntimeError('host exited before owned panel readiness')
        reader.close()
        if not ready:
            raise RuntimeError('owned panel readiness timed out')
        if mode in ('INT', 'TERM'):
            process.send_signal(signal.SIGINT if mode == 'INT' else signal.SIGTERM)
        _, error = process.communicate(timeout=5)
        expected = {'normal': 0, 'failure': 7, 'INT': -signal.SIGINT, 'TERM': -signal.SIGTERM}[mode]
        if process.returncode != expected:
            raise RuntimeError(f'exit={process.returncode}, expected={expected}: {error}')
        if [stamp(path) for path in protected] != before:
            raise RuntimeError('protected files changed; do not overwrite them to restore')
        dictionary = work / 'user-dictionary.tsv'
        if not dictionary.exists() or '面板隔离测试词' not in dictionary.read_text():
            raise RuntimeError('test dictionary did not remain in the owned directory')
        if not (work / 'config.toml').exists():
            raise RuntimeError('isolated configuration missing')
        shutil.rmtree(work)
        print(f'PASS isolation {mode}: owned process exited; protected bytes/existence unchanged')
    except BaseException:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        print(f'BLOCKED: retained test evidence at {work}', flush=True)
        raise


if __name__ == '__main__':
    for scenario in ('normal', 'failure', 'INT', 'TERM'):
        run(scenario)
    print('PASS isolation protocol only; full native add/import/export/lookup acceptance remains pending')
