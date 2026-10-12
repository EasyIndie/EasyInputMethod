"""Validate paired release assets without extracting or executing archive content."""
import argparse
import hashlib
from pathlib import Path, PurePosixPath
import posixpath
import plistlib
import re
import struct
import sys
import tarfile
import zipfile


def require(condition, message):
    if not condition:
        raise ValueError(message)


def safe_name(name):
    path = PurePosixPath(name)
    require(not path.is_absolute() and ".." not in path.parts and "\\" not in name,
            "归档路径越界：" + name)
    return path


def checksum(path):
    sidecar = Path(str(path) + ".sha256")
    require(sidecar.is_file(), "缺少附件摘要：" + path.name)
    line = sidecar.read_text().strip()
    expected = hashlib.sha256(path.read_bytes()).hexdigest() + "  " + path.name
    require(line == expected, "附件摘要或文件名不符：" + path.name)
    return sidecar


def architectures(executable):
    require(len(executable) >= 8 and executable[:4] == b"\xca\xfe\xba\xbe", "可执行文件不是通用Mach-O")
    count = struct.unpack_from(">I", executable, 4)[0]
    require(count == 2 and len(executable) >= 8 + count * 20, "Mach-O架构数不符")
    cpus = set()
    for index in range(count):
        cpu, _, offset, size, _ = struct.unpack_from(">IIIII", executable, 8 + 20 * index)
        require(size >= 4 and offset >= 8 + count * 20 and offset + size <= len(executable), "Mach-O分片越界")
        require(executable[offset:offset + 4] == b"\xcf\xfa\xed\xfe", "Mach-O分片头无效")
        require(size >= 8 and struct.unpack_from("<I", executable, offset + 4)[0] == cpu, "Mach-O分片架构不符")
        cpus.add(cpu)
    require(cpus == {0x01000007, 0x0100000C}, "缺少arm64或x86_64")


def validate(directory, tag, commit, review=False):
    require(re.fullmatch(r"v\d+\.\d+\.\d+", tag), "无效发布版本")
    require(re.fullmatch(r"[0-9a-f]{40}", commit), "源码提交须为40位SHA")
    version = tag[1:]
    binary_name = f"Lampyris-{version}-universal.zip"
    source_name = f"Lampyris-{version}-source.tar.gz"
    assets = []
    for name in (binary_name, source_name):
        matches = list(directory.rglob(name))
        require(len(matches) == 1, "附件缺失或重复：" + name)
        assets.append(matches[0])
    binary, source = assets
    require(binary.stat().st_size <= 15_000_000, "二进制包超过15MB")
    sidecars = [checksum(path) for path in assets]
    prefix = f"Lampyris-{version}-universal/"
    with zipfile.ZipFile(binary) as archive:
        infos = archive.infolist()
        names = [entry.filename for entry in infos]
        require(len(names) == len(set(names)), "ZIP含重复路径")
        require(sum(entry.file_size for entry in infos) <= 100_000_000, "ZIP解压体积过大")
        files = {}
        for entry in infos:
            safe_name(entry.filename)
            require(entry.filename.startswith(prefix) or entry.filename.startswith("__MACOSX/"), "ZIP根目录不符")
            if entry.is_dir() or entry.filename.startswith("__MACOSX/"):
                continue
            require((entry.external_attr >> 16) & 0o170000 != 0o120000, "发布ZIP不接受符号链接")
            files[entry.filename[len(prefix):]] = archive.read(entry)
        require("SHA256SUMS" in files, "缺少包内摘要清单")
        hashes = {}
        for line in files["SHA256SUMS"].decode().splitlines():
            digest, name = line.split("  ", 1)
            safe_name(name)
            require(name not in hashes and re.fullmatch(r"[0-9a-f]{64}", digest), "摘要清单重复或无效")
            hashes[name] = digest
        require(set(hashes) == set(files) - {"SHA256SUMS"}, "摘要清单未完整覆盖附件")
        for name, digest in hashes.items():
            require(hashlib.sha256(files[name]).hexdigest() == digest, "包内摘要不符：" + name)
        app = "Lampyris.app/Contents/"
        required = (app + "Info.plist", app + "Resources/SOURCE-COMMIT", app + "MacOS/Lampyris",
                    "BUILD-INFO.txt", "LICENSE", "SOURCE.txt", "SBOM.cdx.json", "DATA-SOURCES.md")
        require(all(name in files for name in required), "缺少必要发布附件")
        require(all(app + "Resources/" + name in files for name in
                    ("wubi86-core.tsv", "pinyin-chars.tsv", "pinyin-core.tsv", "variant-s2t.tsv")),
                "缺少默认输入数据")
        require(not any(name.startswith("SOURCE/") for name in files), "二进制包不应包含源码目录")
        info = plistlib.loads(files[app + "Info.plist"])
        require(info.get("CFBundleShortVersionString") == version and info.get("CFBundleVersion") == version,
                "包内版本与tag不符")
        require(info.get("CFBundleIdentifier") == "cn.jokerhub.inputmethod.Lampyris", "bundle身份不符")
        require(files[app + "Resources/SOURCE-COMMIT"].decode().strip() == commit, "应用源码提交不符")
        metadata = files["BUILD-INFO.txt"].decode().splitlines()
        for expected in ("commit=" + commit, "architecture=universal", ("signed_release=false" if review else "signed_release=true")):
            key = expected.split("=", 1)[0] + "="
            require([line for line in metadata if line.startswith(key)] == [expected], "构建元信息不符：" + key)
        arches = [line for line in metadata if line.startswith("lipo_archs=")]
        require(len(arches) == 1 and set(arches[0].split("=", 1)[1].split()) == {"arm64", "x86_64"}, "构建架构声明不符")
        architectures(files[app + "MacOS/Lampyris"])
        mode = archive.getinfo(prefix + app + "MacOS/Lampyris").external_attr >> 16
        require(mode & 0o111, "可执行文件缺少执行权限")
    root = f"Lampyris-{version}-source/"
    with tarfile.open(source, "r:gz") as archive:
        members = archive.getmembers()
        names = [member.name for member in members]
        require(len(names) == len(set(names)), "源码包含重复路径")
        for member in members:
            safe_name(member.name)
            require(member.name == root.rstrip("/") or member.name.startswith(root), "源码包根目录不符")
            require(member.isfile() or member.isdir() or member.issym(), "源码包拒绝硬链接和特殊文件")
        by_name = {member.name: member for member in members}
        links = [member for member in members if member.issym()]
        for member in links:
            require(not member.linkname.startswith("/"), "源码链接不得为绝对路径")
            target = posixpath.normpath(posixpath.join(posixpath.dirname(member.name), member.linkname))
            require(target.startswith(root) and target in by_name, "源码链接越界或目标缺失")
            require(by_name[target].isfile() or by_name[target].isdir(), "源码链接目标不得为链接")
            require(not any(name.startswith(member.name + "/") for name in names), "源码链接下不得有额外成员")
            require(not any(target.startswith(link.name + "/") for link in links), "源码链接目标不得穿越其他链接")
        source_files = {member.name for member in members if member.isfile()}
        required = ("SOURCE-COMMIT", "Cargo.lock", "Cargo.toml", "LICENSE", ".cargo/config.toml", "platforms/macos/build.sh")
        require(all(root + name in source_files for name in required), "对应源码或离线构建材料不全")
        require(any(name.startswith(root + "vendor/") for name in source_files), "缺少锁定依赖源码")
        stream = archive.extractfile(root + "SOURCE-COMMIT")
        require(stream.read().decode().strip() == commit, "对应源码提交不符")
    return assets + sidecars


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("tag")
    parser.add_argument("commit")
    parser.add_argument("--assets-only", action="store_true", help="仅输出已核验附件路径，供发布步骤读取")
    parser.add_argument("--review", action="store_true", help="仅校验未签名本地审核包；不能用于发布附件输出")
    args = parser.parse_args()
    if args.review and args.assets_only:
        parser.error("审核模式不能输出正式发布附件")
    try:
        assets = validate(args.directory, args.tag, args.commit, review=args.review)
        if not args.assets_only:
            print("附件摘要、版本、双架构、提交与对应源码核验通过（Apple签名/公证由macOS另验）")
        for path in assets:
            print(path)
        return 0
    except (OSError, ValueError, KeyError, tarfile.TarError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        print("发布附件核验失败：" + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
