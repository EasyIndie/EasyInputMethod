#!/usr/bin/env python3
"""Verified in-place upgrade for the production input method (ADR-259).

顺序固定：**先下载（可省略）、验签，再解包/校验候选，最后才停宿主与替换**；
任何一步失败都回到升级前状态，下载临时目录始终清理。
默认只做预检（dry-run）；真正写入必须显式 `--apply`，且宿主只在目标已存在时才停止。

用法（真实升级，需已构建的更新程序提供验签入口）：
    python3 packaging/macos/upgrade.py \
        --payload-url https://example.invalid/Lampyris-0.1.0-universal.zip \
        --signature <base64 Ed25519> \
        --verifier <LampyrisUpdateCheck 可执行文件> \
        --apply

下载只接受 **https**；`--allow-file-url` 仅用于本地离线测试，正式发布不得使用。

测试通过注入 hooks 覆盖替换/回滚逻辑，不触碰真实输入法目录。
"""
from __future__ import annotations

import argparse
import dataclasses
import functools
import hashlib
import importlib.util
import plistlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from typing import Callable
import urllib.parse
import urllib.request
import uuid

MAX_PAYLOAD_BYTES = 256 * 1024 * 1024
# GitHub Releases 会把下载重定向到资产主机；只允许这些主机（仍是 https）。
ALLOWED_REDIRECT_HOSTS = {
    'github.com', 'objects.githubusercontent.com',
    'release-assets.githubusercontent.com', 'raw.githubusercontent.com',
}


@functools.lru_cache(maxsize=1)
def appcast_module():
    path = Path(__file__).with_name('feed.py')
    spec = importlib.util.spec_from_file_location('lampyris_feed', path)
    module = importlib.util.module_from_spec(spec)
    sys.modules['lampyris_feed'] = module
    spec.loader.exec_module(module)
    return module


def select_release(sources, current: str, *, allow_file: bool = False):
    """按顺序尝试 (url, 本地路径|null) 来源；返回 release 或 None（无更新）。全部失败抛错。"""
    appcast = appcast_module()
    failures = 0
    for source, path in sources:
        try:
            data = path.read_bytes() if path is not None else fetch_feed(source, allow_file=allow_file)
            release = appcast.newest_release(
                appcast.parse_appcast(data, allow_file=allow_file), current)
        except (UpgradeError, OSError, ValueError):
            failures += 1
            continue
        return release
    raise UpgradeError(f'所有更新来源均不可用（已尝试 {failures} 个）')


def installed_build(domain: Path) -> str | None:
    info = domain / BUNDLE / 'Contents/Info.plist'
    try:
        return str(plistlib.loads(info.read_bytes()).get('CFBundleVersion'))
    except (OSError, plistlib.InvalidFileException, ValueError):
        return None


def fetch_feed(url: str, *, allow_file: bool = False) -> bytes:
    allowed = {'https'} | ({'file'} if allow_file else set())
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in allowed:
        raise UpgradeError('feed 地址只允许 https；拒绝：' + (parsed.scheme or '无协议'))
    with urllib.request.urlopen(url, timeout=30) as response:
        final = urllib.parse.urlparse(response.geturl())
        if final.scheme not in allowed:
            raise UpgradeError('feed 重定向后协议不允许：' + final.scheme)
        origin_host = (parsed.hostname or '').lower()
        final_host = (final.hostname or '').lower()
        if final_host and final_host != origin_host and final_host not in ALLOWED_REDIRECT_HOSTS:
            raise UpgradeError('feed 重定向到未允许的主机：' + final.hostname)
        data = response.read(1024 * 1024 + 1)
    if len(data) > 1024 * 1024:
        raise UpgradeError('feed 超过大小上限')
    return data

BUNDLE = 'Lampyris.app'
EXECUTABLE = 'Contents/MacOS/Lampyris'
IDENTITY = 'cn.jokerhub.inputmethod.Lampyris'


class UpgradeError(RuntimeError):
    """升级前置条件或校验失败；发生时磁盘保持升级前状态或已回滚。"""


@dataclasses.dataclass(frozen=True)
class Hooks:
    """可注入的外部检查，测试用桩替换，生产用真实实现。"""
    verify_payload: Callable[[Path, str], None]
    verify_candidate: Callable[[Path], None]
    stop_host: Callable[[Path], None]


def download(url: str, *, allow_file: bool = False, limit: int = MAX_PAYLOAD_BYTES,
             opener: Callable[..., object] = urllib.request.urlopen) -> Path:
    """把负载流式下载到 0700 私有目录，拒绝非 https 与超限；返回 0600 文件路径。"""
    allowed = {'https'} | ({'file'} if allow_file else set())
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in allowed:
        raise UpgradeError('下载地址只允许 https；拒绝：' + (parsed.scheme or '无协议'))
    folder = Path(tempfile.mkdtemp(prefix='lampyris-download-'))
    folder.chmod(0o700)
    target = folder / 'payload.zip'
    try:
        with opener(url, timeout=30) as response:
            final = urllib.parse.urlparse(response.geturl())
            if final.scheme not in allowed:
                raise UpgradeError('重定向后协议不允许：' + final.scheme)
            origin_host = (parsed.hostname or '').lower()
            final_host = (final.hostname or '').lower()
            # 同主机（自建镜像直链）或 GitHub 资产主机才允许；其余跨主机跳转拒绝。
            if final_host and final_host != origin_host and final_host not in ALLOWED_REDIRECT_HOSTS:
                raise UpgradeError('重定向到未允许的主机：' + final.hostname)
            written = 0
            with target.open('wb') as stream:
                while True:
                    chunk = response.read(1 << 16)
                    if not chunk:
                        break
                    written += len(chunk)
                    if written > limit:
                        raise UpgradeError('负载超过大小上限')
                    stream.write(chunk)
        if written == 0:
            raise UpgradeError('负载为空')
        target.chmod(0o600)
        return target
    except BaseException:
        shutil.rmtree(folder, ignore_errors=True)
        raise


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b''):
            digest.update(chunk)
    return digest.hexdigest()


def _private(path: Path, directory: bool = False) -> None:
    stat = path.lstat()
    if path.is_symlink() or stat.st_uid != os.geteuid():
        raise UpgradeError('升级资源归属或链接不符：' + str(path))
    if directory and not path.is_dir():
        raise UpgradeError('升级资源不是目录：' + str(path))
    if not directory and not path.is_file():
        raise UpgradeError('升级资源不是普通文件：' + str(path))


def _extract(payload: Path, staging: Path) -> Path:
    staging.mkdir(mode=0o700)
    subprocess.run(['/usr/bin/ditto', '-x', '-k', str(payload), str(staging)], check=True)
    # 正式发行 ZIP 顶层是一个发布目录（含 README/SBOM 等），Lampyris.app 在下一层；
    # 也兼容直接把 .app 放在 ZIP 根部的负载。要求候选唯一。
    direct = staging / BUNDLE
    if direct.is_dir() and not direct.is_symlink():
        return direct
    matches = [path for path in staging.glob('*/') if (path / BUNDLE).is_dir()
               and not (path / BUNDLE).is_symlink()]
    if len(matches) != 1:
        raise UpgradeError('负载解包后缺少唯一的 ' + BUNDLE)
    return matches[0] / BUNDLE


def _swap(candidate: Path, destination: Path, backup: Path) -> Path | None:
    """把已安装包移到备份位，再原子放入候选；返回备份路径（不存在旧包时为 None）。"""
    previous = None
    if os.path.lexists(destination):
        if destination.is_symlink():
            raise UpgradeError('拒绝替换符号链接目标')
        backup.mkdir(mode=0o700, parents=False)
        previous = backup / BUNDLE
        destination.rename(previous)
    try:
        candidate.rename(destination)
    except OSError as error:
        if previous is not None and not os.path.lexists(destination):
            previous.rename(destination)
        raise UpgradeError('替换失败，已恢复旧包：' + str(error)) from error
    return previous


def install(payload: Path, signature: str, domain: Path, support: Path,
            hooks: Hooks, dry_run: bool = True) -> dict:
    for path in (payload,):
        _private(path)
    if domain.is_symlink() or support.is_symlink():
        raise UpgradeError('安装目录不得为符号链接')
    destination = domain / BUNDLE
    if os.path.lexists(destination) and destination.is_symlink():
        raise UpgradeError('已安装包是符号链接，拒绝升级')
    work = support / f'upgrade-{time.strftime("%Y%m%dT%H%M%S")}-{uuid.uuid4().hex[:8]}'
    staging = work / 'staging'
    backup = work / 'backup'
    receipt = {
        'payload_sha256': sha256(payload),
        'signature': signature.strip(),
        'installed': str(destination),
        'previous': None,
        'dry_run': dry_run,
    }
    # 1) 先验签：签名不通过时不解包、不碰已安装目录。
    hooks.verify_payload(payload, signature)
    support.mkdir(mode=0o700, parents=True, exist_ok=True)
    work.mkdir(mode=0o700)
    candidate = _extract(payload, staging)
    # 2) 候选自身必须通过身份/签名/Gatekeeper 校验，才允许停宿主。
    hooks.verify_candidate(candidate)
    receipt['candidate_executable_sha256'] = sha256(candidate / EXECUTABLE)
    if dry_run:
        shutil.rmtree(work, ignore_errors=True)
        receipt['result'] = 'dry-run'
        return receipt
    previous = None
    try:
        if os.path.lexists(destination):
            hooks.stop_host(destination / EXECUTABLE)
        previous = _swap(candidate, destination, backup)
        receipt['previous'] = str(previous) if previous else None
        # 3) 落地后的包必须再次通过同一校验，否则回滚。
        hooks.verify_candidate(destination)
    except Exception as error:
        _rollback(destination, previous, work)
        raise UpgradeError('升级失败，已回滚：' + str(error)) from error
    receipt['result'] = 'installed'
    receipt['installed_executable_sha256'] = sha256(destination / EXECUTABLE)
    _write_receipt(support, receipt)
    shutil.rmtree(staging, ignore_errors=True)
    return receipt


def _rollback(destination: Path, previous: Path | None, work: Path) -> None:
    if os.path.lexists(destination) and previous is not None and previous.exists():
        rejected = work / 'rejected.app'
        try:
            destination.rename(rejected)
        except OSError:
            pass
        if not os.path.lexists(destination):
            previous.rename(destination)


def _write_receipt(support: Path, receipt: dict) -> None:
    receipts = support / 'receipts'
    receipts.mkdir(mode=0o700, exist_ok=True)
    path = receipts / f'{time.strftime("%Y%m%dT%H%M%S")}-{uuid.uuid4().hex[:8]}.json'
    path.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n')
    path.chmod(0o600)


def host_holders(executable: Path, holders: list[tuple[int, str]]) -> tuple[list[int], list[int]]:
    """区分真正的宿主与系统服务（LaunchServices/Spotlight 等）的临时持有。"""
    target = str(executable)
    exact = [pid for pid, command in holders if command == target]
    ignored = [pid for pid, command in holders if command != target]
    return exact, ignored


def real_hooks(verifier: Path) -> Hooks:
    def verify_payload(payload: Path, signature: str) -> None:
        result = subprocess.run([str(verifier), '--verify-payload', str(payload), signature],
                                capture_output=True, text=True)
        if result.returncode != 0:
            raise UpgradeError('负载签名无效；未解包、未安装')

    def verify_candidate(app: Path) -> None:
        executable = app / EXECUTABLE
        if executable.is_symlink() or not executable.is_file() or not os.access(executable, os.X_OK):
            raise UpgradeError('候选缺少可执行文件')
        identity = subprocess.run(
            ['/usr/libexec/PlistBuddy', '-c', 'Print :CFBundleIdentifier', str(app / 'Contents/Info.plist')],
            capture_output=True, text=True)
        if identity.stdout.strip() != IDENTITY:
            raise UpgradeError('候选标识不符：' + identity.stdout.strip())
        subprocess.run(['/usr/bin/codesign', '--verify', '--strict', '--deep', str(app)], check=True)
        details = subprocess.run(['/usr/bin/codesign', '-dv', '--verbose=4', str(app)],
                                 capture_output=True, text=True).stderr
        if 'Authority=Developer ID Application:' not in details or 'runtime' not in details:
            raise UpgradeError('候选缺少 Developer ID 或 hardened runtime')
        subprocess.run(['/usr/bin/xcrun', 'stapler', 'validate', str(app)], check=True,
                       capture_output=True)
        subprocess.run(['/usr/sbin/spctl', '--assess', '--type', 'execute', str(app)], check=True,
                       capture_output=True)

    def stop_host(executable: Path) -> None:
        def current_holders() -> list[tuple[int, str]]:
            listing = subprocess.run(['/usr/sbin/lsof', '-t', str(executable)],
                                     capture_output=True, text=True)
            if listing.returncode != 0:
                return []
            rows = []
            for value in listing.stdout.split():
                pid = int(value)
                command = subprocess.run(['/bin/ps', '-p', str(pid), '-o', 'comm='],
                                         capture_output=True, text=True).stdout.strip()
                rows.append((pid, command))
            return rows

        pids, ignored = host_holders(executable, current_holders())
        if ignored:
            print(json.dumps({'ignored_holders': ignored}), file=sys.stderr)
        for pid in sorted(pids):
            os.kill(pid, signal.SIGTERM)
        deadline = time.monotonic() + 5
        while True:
            remaining, _ = host_holders(executable, current_holders())
            if not remaining:
                return
            if time.monotonic() >= deadline:
                raise UpgradeError('宿主未退出；未替换')
            time.sleep(0.1)

    return Hooks(verify_payload, verify_candidate, stop_host)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument('--payload', type=Path)
    source.add_argument('--payload-url')
    source.add_argument('--feed-file', type=Path, help='本地 appcast（离线/演练）')
    source.add_argument('--feed-url', help='https appcast；发现更新后自动下载负载')
    source.add_argument('--feed-urls', help='逗号/空白分隔的 appcast 列表，按顺序回退')
    parser.add_argument('--current-build', help='缺省从已安装 Info.plist 读取')
    parser.add_argument('--allow-file-url', action='store_true',
                        help='仅本地离线测试：允许 file:// 负载/feed 地址')
    parser.add_argument('--signature', help='显式负载签名；用 feed 时可省略')
    parser.add_argument('--verifier', type=Path, help='已签名的 LampyrisUpdateCheck 可执行文件')
    parser.add_argument('--domain', type=Path, default=Path.home() / 'Library/Input Methods')
    parser.add_argument('--support', type=Path,
                        default=Path.home() / 'Library/Application Support/Lampyris/updates')
    parser.add_argument('--apply', action='store_true', help='真正停宿主并替换；缺省只做预检')
    args = parser.parse_args(argv)
    if args.apply and args.verifier is None:
        parser.error('--apply 需要 --verifier 提供验签')
    verifier = args.verifier
    if verifier is not None and not (verifier.is_file() and os.access(verifier, os.X_OK)):
        parser.error('--verifier 不是可执行文件')
    hooks = real_hooks(verifier) if verifier is not None else Hooks(
        verify_payload=lambda payload, signature: (_ for _ in ()).throw(UpgradeError('未提供验签器')),
        verify_candidate=lambda app: None,
        stop_host=lambda executable: None,
    )
    downloaded = None
    try:
        payload = args.payload
        signature = args.signature
        if args.feed_file is not None or args.feed_url is not None or args.feed_urls is not None:
            current = args.current_build or installed_build(args.domain)
            if current is None:
                raise UpgradeError('无法确定已安装构建号；请提供 --current-build')
            sources = []
            if args.feed_file is not None:
                sources = [('file', args.feed_file)]
            else:
                raw = args.feed_urls or args.feed_url or ''
                urls = [u for u in raw.replace(',', ' ').split() if u]
                sources = [(url, None) for url in urls]
            if not sources:
                raise UpgradeError('没有可用的更新来源')
            release = select_release(sources, current, allow_file=args.allow_file_url)
            if release is None:
                print(json.dumps({'result': 'up-to-date', 'current': current}, ensure_ascii=False))
                return 0
            payload = download(release.download_url, allow_file=args.allow_file_url)
            downloaded = payload.parent
            signature = release.signature
            print(json.dumps({'selected_build': release.build, 'current': current}, ensure_ascii=False),
                  file=sys.stderr)
        elif args.payload_url is not None:
            payload = download(args.payload_url, allow_file=args.allow_file_url)
            downloaded = payload.parent
        if signature is None:
            parser.error('缺少 --signature（或用 feed 提供）')
        receipt = install(payload, signature, args.domain, args.support, hooks,
                          dry_run=not args.apply)
    except (UpgradeError, OSError, subprocess.CalledProcessError) as error:
        print('BLOCKED：' + str(error), file=sys.stderr)
        return 3
    finally:
        if downloaded is not None:
            shutil.rmtree(downloaded, ignore_errors=True)
    print(json.dumps(receipt, ensure_ascii=False, indent=2))
    return 0


if __name__ == '__main__':
    sys.exit(main())
