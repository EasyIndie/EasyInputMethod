"""Build a test-only host and bind its signed resources to the target device root."""
import importlib.util
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[2]
# 目标根只允许落在目标设备的系统临时目录里（ADR-124/129/216）：
#   - macOS 每用户的私有临时目录：/private/var/folders/<A>/<B>/T/
#   - 系统公用临时目录：/private/tmp、/tmp、/private/var/tmp、/var/tmp
# 其余绝对路径（尤其真实 Lampyris 数据目录、用户文档、/Applications）一律拒绝。
# macOS 上 /var 与 /private/var 是同一目录的两种写法（firmlink）；设备 TMPDIR 可能是 /var 形式。
TEMP_ROOT_PATTERN = re.compile(r"^/(?:private/)?var/folders/(?:[^/]+/)+T$")
TEMP_ROOT_PARENTS = frozenset({"/private/tmp", "/tmp", "/private/var/tmp", "/var/tmp"})
SUPPORTED_ARCHES = {"arm64", "x86_64", "universal"}


def target_identity(value, development=False):
    target = Path(value)
    if not target.is_absolute() or ".." in target.parts or str(target) != os.path.normpath(str(target)):
        raise ValueError("目标必须是规范化的绝对路径")
    if development:
        if not re.fullmatch(r"/Users/[^/]+/Library/Application Support/LampyrisIMKDev", target.parent.as_posix()):
            raise ValueError("开发根必须位于用户LampyrisIMKDev专用目录")
    elif target.parent.as_posix() not in TEMP_ROOT_PARENTS and not TEMP_ROOT_PATTERN.match(target.parent.as_posix()):
        raise ValueError("目标根必须位于设备系统临时目录内")
    if not target.name.startswith("lampyris-imk-"):
        raise ValueError("目标根身份不符")
    suffix = target.name.removeprefix("lampyris-imk-")
    if str(uuid.UUID(suffix)) != suffix:
        raise ValueError("目标UUID不符")
    return target


def target_arch(value):
    if value in ("", None, "native"):
        return "native"
    if value not in SUPPORTED_ARCHES:
        raise ValueError("架构只能是 arm64、x86_64 或 universal")
    return value


def main():
    development = os.environ.get("IMK_DEVELOPMENT", "false") == "true"
    target = target_identity(os.environ["TARGET_TEST_ROOT"], development)
    arch = target_arch(os.environ.get("TARGET_ARCH"))
    spec = importlib.util.spec_from_file_location("isolated", ROOT/"platforms/macos/tests/isolated-imk.py")
    isolated = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(isolated)
    root = Path(tempfile.gettempdir()).resolve()/target.name
    root.mkdir(mode=0o700)
    marker = root/"owner"
    marker.write_text(root.name)
    marker.chmod(0o600)
    isolated.require_owned(root)
    app = isolated.build(root, arch)
    subprocess.run([str(app/"Contents/MacOS/LampyrisIMKTest"), "--isolation-probe", "normal"], check=True, timeout=15)
    # Rebind before signing, then never execute the recipient-bound app on the runner.
    (app/"Contents/Resources/IMKTestRoot").write_text(str(target))
    if development:
        import plistlib
        info_path = app/"Contents/Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info["LampyrisIMKDevelopment"] = True
        info["LampyrisSourceCommit"] = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
        info_path.write_bytes(plistlib.dumps(info))
    destination = ROOT/"platforms/macos/build/Lampyris.app"
    if destination.exists():
        raise ValueError("目标构建目录已存在，不覆盖")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(app, destination)
    output = ROOT/"packaging/out/isolated-imk"
    output.mkdir(parents=True)
    (output/"TARGET-ROOT.txt").write_text(str(target)+"\n")
    built = " ".join(isolated.macho_arches(destination/"Contents/MacOS/LampyrisIMKTest"))
    (output/"TARGET-ARCH.txt").write_text("requested=" + arch + "\nbuilt=" + built + "\n")
    (output/"SOURCE-COMMIT.txt").write_text(subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True))

if __name__ == "__main__":
    main()
