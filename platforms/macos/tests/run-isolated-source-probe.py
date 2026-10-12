"""Register and remove one owned source alias without selecting or sending keys."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys

SPEC = importlib.util.spec_from_file_location("isolated", Path(__file__).with_name("isolated-imk.py"))
isolated = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(isolated)
LSREGISTER = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    isolated.require_owned(root)
    app = root / "LampyrisIMKTest.app"
    helper = root / "source-state"
    subprocess.run(["swiftc", "-O", "-warnings-as-errors", "-module-cache-path", str(root / "module-cache"),
                    str(isolated.ROOT / "platforms/macos/tests/isolated-imk/source-state.swift"), "-o", str(helper)], check=True)

    def state(action):
        result = subprocess.run([str(helper), action, str(root)], capture_output=True,
                                text=True, timeout=15, check=False)
        if result.returncode != 0:
            raise RuntimeError(result.stderr.strip() or "输入源辅助工具失败")
        return json.loads(result.stdout)

    before = state("state")
    journal = root / "source-state.json"
    with journal.open("x") as stream:
        json.dump(before, stream, ensure_ascii=False)
    journal.chmod(0o600)
    directory = Path.home() / "Library/Input Methods"
    alias = directory / ("LampyrisIMKTest-" + root.name.removeprefix("lampyris-imk-") + ".app")
    created_directory = False
    created_alias = False
    success = False

    def interrupted(_number, _frame):
        raise KeyboardInterrupt("捕获中断，清理自己的注册资源")

    original_term = signal.signal(signal.SIGTERM, interrupted)
    original_int = signal.getsignal(signal.SIGINT)
    try:
        if not directory.exists():
            directory.mkdir(mode=0o700)
            created_directory = True
        if os.path.lexists(alias):
            raise RuntimeError("同名路径存在，拒绝覆盖")
        alias.symlink_to(app, target_is_directory=True)
        created_alias = True
        recognition = subprocess.run([LSREGISTER, "-f", str(alias)], capture_output=True,
                                     text=True, timeout=15, check=False)
        recognition_path = root / "launchservices-recognition.json"
        with recognition_path.open("x") as stream:
            json.dump({"exit": recognition.returncode, "stdout": recognition.stdout,
                       "stderr": recognition.stderr}, stream, ensure_ascii=False)
        recognition_path.chmod(0o600)
        if recognition.returncode != 0:
            raise RuntimeError("LaunchServices识别失败；诊断已保存在独有目录")
        registered = state("register")
        if registered["current"] != before["current"]:
            raise RuntimeError("注册改变了当前输入源，停止后续操作")
        print("PASS owned registration: " + str(len(registered["owned"])) + " source identities; no selection or keys", flush=True)
        success = True
    except (OSError, ValueError, RuntimeError, KeyboardInterrupt, subprocess.TimeoutExpired) as error:
        print("BLOCKED：" + str(error), file=sys.stderr)
    finally:
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        try:
            if created_alias:
                after = state("disable-owned")
                if after["current"] != before["current"] or after["enabled"] != before["enabled"]:
                    raise RuntimeError("原输入源或启用集合发生变化；不覆盖用户新状态")
                if any(item["enabled"] for item in after["owned"]):
                    raise RuntimeError("独有输入源仍可选")
                if not alias.is_symlink() or os.readlink(alias) != str(app):
                    raise RuntimeError("软链目标已变，不清理未知资源")
                subprocess.run([LSREGISTER, "-u", str(alias)], capture_output=True, timeout=15, check=True)
                alias.unlink()
                created_alias = False
            if created_directory and directory.exists():
                directory.rmdir()
            if success:
                isolated.require_owned(root)
                shutil.rmtree(root)
                print("PASS cleanup: original source/enabled set unchanged; owned alias/root removed", flush=True)
                print("SCOPE: registration only; disabled TIS cache IDs may persist; selection/IMK input untested")
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
            success = False
            print("BLOCKED cleanup：" + str(error), file=sys.stderr)
        signal.signal(signal.SIGTERM, original_term)
        signal.signal(signal.SIGINT, original_int)
    if not success:
        print("RETAINED=" + str(root), file=sys.stderr)
    return 0 if success else 3


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print("BLOCKED：" + str(error), file=sys.stderr)
        sys.exit(3)
