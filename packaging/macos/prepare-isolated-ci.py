"""Build a test-only host and bind its signed resources to the target device root."""
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[2]

def target_identity(value):
    target = Path(value)
    if not target.is_absolute() or ".." in target.parts or not str(target).startswith("/private/var/folders/"):
        raise ValueError("目标必须是设备私有临时目录中的绝对路径")
    if not target.name.startswith("lampyris-imk-"):
        raise ValueError("目标根身份不符")
    suffix = target.name.removeprefix("lampyris-imk-")
    if str(uuid.UUID(suffix)) != suffix:
        raise ValueError("目标UUID不符")
    return target

def main():
    target = target_identity(os.environ["TARGET_TEST_ROOT"])
    spec = importlib.util.spec_from_file_location("isolated", ROOT/"platforms/macos/tests/isolated-imk.py")
    isolated = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(isolated)
    if subprocess.check_output(["uname", "-m"], text=True).strip() != "arm64":
        raise ValueError("本次设备B隔离候选要求arm64 runner")
    root = Path(tempfile.gettempdir()).resolve()/target.name
    root.mkdir(mode=0o700)
    marker = root/"owner"
    marker.write_text(root.name)
    marker.chmod(0o600)
    isolated.require_owned(root)
    app = isolated.build(root)
    subprocess.run([str(app/"Contents/MacOS/LampyrisIMKTest"), "--isolation-probe", "normal"], check=True, timeout=15)
    # Rebind before signing, then never execute the recipient-bound app on the runner.
    (app/"Contents/Resources/IMKTestRoot").write_text(str(target))
    destination = ROOT/"platforms/macos/build/Lampyris.app"
    if destination.exists():
        raise ValueError("目标构建目录已存在，不覆盖")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(app, destination)
    output = ROOT/"packaging/out/isolated-imk"
    output.mkdir(parents=True)
    (output/"TARGET-ROOT.txt").write_text(str(target)+"\n")
    (output/"SOURCE-COMMIT.txt").write_text(subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True))

if __name__ == "__main__":
    main()
