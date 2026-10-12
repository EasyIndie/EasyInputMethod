#!/usr/bin/env python3
"""Exercise shared TextEdit ownership without typing or changing input sources."""
from pathlib import Path
import shutil
import subprocess
import tempfile

LIBRARY = Path(__file__).with_name('owned-resources.sh').resolve()
BODY = '''source "$1"
WORK="$2"
cleanup() {
    status=$?
    owned_cleanup || exit 99
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
owned_textedit_create || exit 98
osascript -e 'tell application "TextEdit" to activate' || exit 98
[ -z "$(owned_do read)" ] || exit 98
owned_do clear >/dev/null || exit 98
case "$3" in
    normal) exit 0 ;;
    failure) exit 7 ;;
    INT) kill -INT $$ ;;
    TERM) kill -TERM $$ ;;
esac
'''


def windows():
    result = subprocess.run(
        ['osascript', '-e', 'with timeout of 5 seconds', '-e',
         'tell application "TextEdit" to get id of (windows whose visible is true)',
         '-e', 'end timeout'], check=True, capture_output=True, text=True, timeout=10,
    )
    return set(result.stdout.strip().split(', '))


if __name__ == '__main__':
    for mode, expected in [('normal', 0), ('failure', 7), ('INT', 130), ('TERM', 143)]:
        before = windows()
        directory = Path(tempfile.mkdtemp(prefix='lampyris-owned-library-'))
        try:
            result = subprocess.run(
                ['bash', '-c', BODY, 'owned-test', str(LIBRARY), str(directory), mode],
                capture_output=True, text=True, timeout=30, check=False,
            )
            if result.returncode != expected or windows() != before:
                print(f'BLOCKED {mode}: status={result.returncode}; retained={directory}')
                print(result.stderr)
                raise SystemExit(3)
        except (subprocess.TimeoutExpired, subprocess.CalledProcessError):
            print(f'BLOCKED {mode}: retained={directory}')
            raise SystemExit(3)
        shutil.rmtree(directory)
        print(f'PASS shared TextEdit create/read/clear/close and windows preserved ({mode})')
