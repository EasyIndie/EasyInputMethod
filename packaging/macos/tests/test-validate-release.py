"""Reject mismatched, incomplete, and tampered paired release artifacts."""
import hashlib
import importlib.util
import io
from pathlib import Path
import plistlib
import struct
import tarfile
import tempfile
import unittest
import zipfile

SPEC = importlib.util.spec_from_file_location("validator", Path(__file__).resolve().parents[1] / "validate-release.py")
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)
COMMIT = "a" * 40
APP = "Lampyris.app/Contents/"


class ReleaseValidationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        header = b"\xca\xfe\xba\xbe" + struct.pack(">I", 2)
        header += struct.pack(">IIIII", 0x01000007, 3, 48, 8, 0)
        header += struct.pack(">IIIII", 0x0100000C, 0, 56, 8, 0)
        executable = header + b"\xcf\xfa\xed\xfe" + struct.pack("<I", 0x01000007)
        executable += b"\xcf\xfa\xed\xfe" + struct.pack("<I", 0x0100000C)
        self.files = {
            APP + "Info.plist": plistlib.dumps({"CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "0.1.0",
                "CFBundleIdentifier": "cn.jokerhub.inputmethod.Lampyris"}),
            APP + "Resources/SOURCE-COMMIT": COMMIT.encode(),
            APP + "MacOS/Lampyris": executable,
            "BUILD-INFO.txt": (f"commit={COMMIT}\narchitecture=universal\nlipo_archs=arm64 x86_64\nsigned_release=true\n").encode(),
            "LICENSE": b"synthetic", "SOURCE.txt": b"synthetic", "SBOM.cdx.json": b"{}", "DATA-SOURCES.md": b"synthetic",
        }
        self.source_links = {}
        self.source_commit = COMMIT
        for name in ("wubi86-core.tsv", "pinyin-chars.tsv", "pinyin-core.tsv", "variant-s2t.tsv"):
            self.files[APP + "Resources/" + name] = b"synthetic data"
        self.binary = self.root / "Lampyris-0.1.0-universal.zip"
        self.source = self.root / "Lampyris-0.1.0-source.tar.gz"

    def write(self):
        files = dict(self.files)
        files["SHA256SUMS"] = "".join(hashlib.sha256(data).hexdigest() + "  " + name + "\n"
            for name, data in files.items()).encode()
        with zipfile.ZipFile(self.binary, "w") as package:
            for name, data in files.items():
                entry = zipfile.ZipInfo("Lampyris-0.1.0-universal/" + name)
                entry.create_system = 3
                entry.external_attr = (0o100755 if name == APP + "MacOS/Lampyris" else 0o100644) << 16
                package.writestr(entry, data)
        with tarfile.open(self.source, "w:gz") as package:
            for name in ("SOURCE-COMMIT", "Cargo.lock", "Cargo.toml", "LICENSE", ".cargo/config.toml",
                         "platforms/macos/build.sh", "vendor/fixture/lib.rs"):
                data = self.source_commit.encode() if name == "SOURCE-COMMIT" else b"synthetic"
                entry = tarfile.TarInfo("Lampyris-0.1.0-source/" + name)
                entry.size = len(data)
                package.addfile(entry, io.BytesIO(data))
            for name, target in self.source_links.items():
                entry = tarfile.TarInfo("Lampyris-0.1.0-source/" + name)
                entry.type = tarfile.SYMTYPE
                entry.linkname = target
                package.addfile(entry)
        for path in (self.binary, self.source):
            Path(str(path) + ".sha256").write_text(hashlib.sha256(path.read_bytes()).hexdigest() + "  " + path.name + "\n")

    def test_review_does_not_pass_release_gate(self):
        self.files['BUILD-INFO.txt'] = self.files['BUILD-INFO.txt'].replace(b'signed_release=true', b'signed_release=false')
        self.write()
        self.assertEqual(len(validator.validate(self.root, 'v0.1.0', COMMIT, review=True)), 4)
        with self.assertRaises(ValueError):
            self.check()

    def test_internal_source_link_and_escape_rejection(self):
        self.source_links = {'alias': 'LICENSE'}
        self.write()
        self.check()
        for target in ['../../escape', '/absolute', 'absent', 'alias']:
            self.source_links = {'alias': target}
            self.write()
            with self.assertRaises(ValueError):
                self.check()

    def check(self):
        return validator.validate(self.root, "v0.1.0", COMMIT)

    def test_synthetic_pair_passes(self):
        self.write()
        self.assertEqual(len(self.check()), 4)

    def test_external_digest_rejects_tampering(self):
        self.write()
        self.binary.write_bytes(self.binary.read_bytes() + b"changed")
        with self.assertRaisesRegex(ValueError, "摘要"):
            self.check()

    def test_source_commit_must_match(self):
        self.source_commit = "b" * 40
        self.write()
        with self.assertRaisesRegex(ValueError, "源码提交"):
            self.check()

    def test_bundle_version_must_match_tag(self):
        info = plistlib.loads(self.files[APP + "Info.plist"])
        info["CFBundleVersion"] = "0.0.9"
        self.files[APP + "Info.plist"] = plistlib.dumps(info)
        self.write()
        with self.assertRaisesRegex(ValueError, "版本"):
            self.check()

    def test_unsigned_candidate_cannot_publish(self):
        self.files["BUILD-INFO.txt"] = self.files["BUILD-INFO.txt"].replace(b"signed_release=true", b"signed_release=false")
        self.write()
        with self.assertRaisesRegex(ValueError, "元信息"):
            self.check()

    def test_metadata_does_not_substitute_actual_architectures(self):
        self.files[APP + "MacOS/Lampyris"] = b"thin executable"
        self.write()
        with self.assertRaisesRegex(ValueError, "Mach-O"):
            self.check()

    def test_missing_or_duplicate_assets_rejected(self):
        self.write()
        duplicate = self.root / "duplicate"
        duplicate.mkdir()
        (duplicate / self.binary.name).write_bytes(self.binary.read_bytes())
        with self.assertRaisesRegex(ValueError, "重复"):
            self.check()
        (duplicate / self.binary.name).unlink()
        Path(str(self.source) + ".sha256").unlink()
        with self.assertRaisesRegex(ValueError, "缺少"):
            self.check()

    def test_traversal_rejected_even_with_valid_checksum(self):
        self.files["../../outside"] = b"synthetic"
        self.write()
        with self.assertRaisesRegex(ValueError, "越界"):
            self.check()

    def test_inner_digest_rejects_tampering_despite_valid_outer_digest(self):
        self.write()
        with zipfile.ZipFile(self.binary) as package:
            entries = [(entry, package.read(entry)) for entry in package.infolist()]
        with zipfile.ZipFile(self.binary, "w") as package:
            for entry, data in entries:
                package.writestr(entry, b"tampered" if entry.filename.endswith("/LICENSE") else data)
        Path(str(self.binary) + ".sha256").write_text(hashlib.sha256(self.binary.read_bytes()).hexdigest() + "  " + self.binary.name + "\n")
        with self.assertRaisesRegex(ValueError, "包内摘要"):
            self.check()


if __name__ == "__main__":
    unittest.main()
