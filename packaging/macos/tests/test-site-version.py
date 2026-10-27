#!/usr/bin/env python3
"""离线回归：产品页的版本描述必须精确到构建号，且与仓库唯一的版本源一致。

版本真源是两个受控文件：`Cargo.toml` 的 `workspace.package.version` 与
`packaging/build-number`（见 `tools/release_version.py`）。产品页写死字符串，
一旦发布时漏改就会对外报错一个版本/构建，所以这里把它钉住（AGENTS §2.9）。
"""
import importlib.util
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
SITE = ROOT / "site/index.html"

spec = importlib.util.spec_from_file_location("release_version", ROOT / "tools/release_version.py")
release_version = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release_version)


class SiteVersionTests(unittest.TestCase):
    def setUp(self):
        self.html = SITE.read_text()
        self.identity = release_version.identity(ROOT)

    def test_version_line_names_the_build(self):
        version, build = self.identity["version"], self.identity["build"]
        self.assertIn(
            f"v{version} · 构建 {build}",
            self.html,
            "产品页版本描述必须精确到构建号（形如 v0.1.14 · 构建 23）",
        )

    def test_no_other_version_is_advertised(self):
        versions = set(re.findall(r"v(\d+\.\d+\.\d+)", self.html))
        self.assertEqual(versions, {self.identity["version"]},
                         "产品页只能出现真源版本，不能残留上一个版本的文案")

    def test_download_links_match_the_version(self):
        version = self.identity["version"]
        links = re.findall(r"releases/latest/download/([^\"]+)", self.html)
        self.assertTrue(links, "产品页必须有下载链接")
        for name in links:
            self.assertEqual(name, f"Lampyris-{version}-universal.dmg")


if __name__ == "__main__":
    unittest.main()
