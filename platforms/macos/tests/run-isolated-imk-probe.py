"""Check the dedicated IMK entry's data isolation; no input source registration."""
import argparse
import hashlib
import importlib.util
from pathlib import Path
import selectors
import shutil
import signal
import subprocess
import sys
import time

SPEC = importlib.util.spec_from_file_location("isolated", Path(__file__).with_name("isolated-imk.py"))
isolated = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(isolated)


def stamp(path):
    return hashlib.sha256(path.read_bytes()).digest() if path.exists() else None


def probe(root, mode):
    executable = root / "LampyrisIMKTest.app/Contents/MacOS/LampyrisIMKTest"
    process = None
    reader = None
    try:
        process = subprocess.Popen([str(executable), "--isolation-probe", mode],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        reader = selectors.DefaultSelector()
        reader.register(process.stdout, selectors.EVENT_READ)
        deadline = time.monotonic() + 15
        ready = False
        while time.monotonic() < deadline:
            if reader.select(timeout=0.2):
                if process.stdout.readline().strip() == f"READY {process.pid}":
                    ready = True
                    break
            if process.poll() is not None:
                break
        if not ready:
            detail = process.communicate(timeout=1)[1] if process.poll() is not None else "就绪超时"
            raise RuntimeError("独立宿主未就绪：" + detail.strip())
        if mode in ("INT", "TERM"):
            process.send_signal(signal.SIGINT if mode == "INT" else signal.SIGTERM)
        _, error = process.communicate(timeout=5)
        expected = {"normal": 0, "failure": 7, "INT": -signal.SIGINT, "TERM": -signal.SIGTERM}[mode]
        if process.returncode != expected:
            raise RuntimeError(f"退出码{process.returncode}，期望{expected}：{error}")
        if "IMK隔离测试词" not in (root / "user-dictionary.tsv").read_text():
            raise RuntimeError("测试词库未落在独有目录")
        if not (root / "config.toml").is_file():
            raise RuntimeError("独有配置未保存")
    finally:
        if reader is not None:
            reader.close()
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    real = Path.home() / "Library/Application Support/Lampyris"
    protected = [real / "config.toml", real / "user-dictionary.tsv"]
    before = [stamp(path) for path in protected]
    try:
        isolated.require_owned(root)
        for mode in ("normal", "failure", "INT", "TERM"):
            probe(root, mode)
            if [stamp(path) for path in protected] != before:
                raise RuntimeError("真实文件发生变化；不尝试覆盖恢复")
            print("PASS dedicated IMK entry isolation " + mode, flush=True)
        binding = root / "LampyrisIMKTest.app/Contents/Resources/IMKTestRoot"
        saved_binding = binding.read_text()
        config_stamp = stamp(root / "config.toml")
        dict_stamp = stamp(root / "user-dictionary.tsv")
        executable = root / "LampyrisIMKTest.app/Contents/MacOS/LampyrisIMKTest"
        try:
            binding.chmod(0o644)
            rejected = subprocess.run([str(executable), "--isolation-probe", "normal"],
                                      capture_output=True, text=True, timeout=5)
            if rejected.returncode != 3 or "测试根声明不符" not in rejected.stderr:
                raise RuntimeError("公开根声明未被拒绝")
            binding.chmod(0o600)
            binding.write_text("/tmp")
            rejected = subprocess.run([str(executable), "--isolation-probe", "normal"],
                                      capture_output=True, text=True, timeout=5)
            if rejected.returncode != 3 or "验收目录或包身份不符" not in rejected.stderr:
                raise RuntimeError("错误根路径未被拒绝")
            if stamp(root / "config.toml") != config_stamp or stamp(root / "user-dictionary.tsv") != dict_stamp:
                raise RuntimeError("错误根声明改变了自己的配置或词库")
            print("PASS invalid root binding/permissions blocked before configuration", flush=True)
        finally:
            binding.write_text(saved_binding)
            binding.chmod(0o600)
        marker = root / "owner"
        marker.write_text("wrong-owner")
        executable = root / "LampyrisIMKTest.app/Contents/MacOS/LampyrisIMKTest"
        config_before = stamp(root / "config.toml")
        dictionary_before = stamp(root / "user-dictionary.tsv")
        rejected = subprocess.run([str(executable), "--isolation-probe", "normal"],
                                  capture_output=True, text=True, timeout=5, check=False)
        if rejected.returncode != 3 or "所有权标记不符" not in rejected.stderr:
            raise RuntimeError("错误身份未在启动前被拒绝")
        if stamp(root / "config.toml") != config_before or stamp(root / "user-dictionary.tsv") != dictionary_before:
            raise RuntimeError("错误身份改变了配置或词库")
        marker.write_text(root.name)
        isolated.require_owned(root)
        if [stamp(path) for path in protected] != before:
            raise RuntimeError("错误身份启动改变了真实文件；不尝试覆盖恢复")
        shutil.rmtree(root)
        print("PASS invalid owner blocked before configuration; owned resources removed")
        print("SCOPE: data isolation only; IMK registration/client input and performance remain untested")
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        print("BLOCKED：" + str(error) + "; RETAINED=" + str(root), file=sys.stderr)
        return 3


if __name__ == "__main__":
    sys.exit(main())
