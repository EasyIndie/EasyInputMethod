#!/usr/bin/env python3
"""离线回归：站点版本行必须由发布数据盖章生成，不能硬编码（报告 251）。

2026-11-06 实际踩过一次：`site/index.html` 里版本行是硬编码的，1.1.0 发布后 dispatch Pages
部署出去的还是 1.0.2 的页面（报告 250）。现在源文件只保留占位符，由
`tools/stamp-site.py` 用真实 Release 数据替换，这里钉死三件事：
1. 源文件不得残留任何具体版本号（只允许占位符）；
2. 盖章后的页面必须自洽：版本行带构建号、正文只有这一个版本号、下载链接指向同一版；
3. 盖章函数对非法输入（缺构建号、版本格式错、占位符未替换）必须报错。
"""
import importlib.util
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
SITE = ROOT / "site/index.html"

spec = importlib.util.spec_from_file_location("stamp_site", ROOT / "tools/stamp-site.py")
stamp_site = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stamp_site)

VERSION_LINE = re.compile(r"v(\d+)\.(\d+)\.(\d+) · 构建 ([1-9][0-9]{0,3})")
DOWNLOAD_LINK = re.compile(r"releases/latest/download/([^\"]+)")
ANY_VERSION = re.compile(r"v(\d+\.\d+\.\d+)")


def problems(html):
    """盖章后的页面自洽性检查；返回空列表表示通过。"""
    found = VERSION_LINE.search(html)
    if found is None:
        return ["版本行必须写成 `vX.Y.Z · 构建 NN`（精确到构建号）"]
    major, minor, patch, _build = found.groups()
    version = f"{major}.{minor}.{patch}"
    issues = []
    for found_version in ANY_VERSION.findall(html):
        if found_version != version:
            issues.append(f"页面残留第二个版本号 v{found_version}")
    links = DOWNLOAD_LINK.findall(html)
    if not links:
        issues.append("页面没有下载链接")
    for name in links:
        if name != f"Lampyris-{version}-universal.dmg":
            issues.append(f"下载链接与本页版本不一致：{name}")
    if stamp_site.PLACEHOLDER_RE.search(html):
        issues.append("页面仍有未替换的占位符")
    return issues


class SiteSourceTests(unittest.TestCase):
    def test_source_page_uses_placeholders(self):
        html = SITE.read_text(encoding="utf-8")
        for placeholder in stamp_site.PLACEHOLDERS:
            self.assertIn(placeholder, html)
        self.assertEqual(ANY_VERSION.findall(html), [], "站点源文件不得硬编码版本号")

    def test_stamped_page_is_consistent(self):
        html = SITE.read_text(encoding="utf-8")
        stamped = stamp_site.stamp(html, "1.1.0", "38", "7.0")
        self.assertEqual(problems(stamped), [])
        self.assertIn("v1.1.0 · 构建 38", stamped)
        self.assertIn("Lampyris-1.1.0-universal.dmg", stamped)


class StampRuleTests(unittest.TestCase):
    """防止盖章函数与校验本身失效。"""

    def test_rejects_bad_version(self):
        with self.assertRaises(ValueError):
            stamp_site.stamp("{{VERSION}}", "1.2", "38", "7.0")

    def test_rejects_bad_build(self):
        with self.assertRaises(ValueError):
            stamp_site.stamp("{{BUILD}}", "1.1.0", "0", "7.0")

    def test_rejects_leftover_placeholder(self):
        with self.assertRaises(ValueError):
            stamp_site.stamp("{{VERSION}} {{BUILD}} {{SIZE_MB}} {{OTHER}}", "1.1.0", "38", "7.0")

    def test_page_without_build_number_is_rejected(self):
        page = ("<p>v1.1.0 · 约 7 MB</p>\n"
                '<a href="https://github.com/o/r/releases/latest/download/Lampyris-1.1.0-universal.dmg">下载</a>')
        self.assertTrue(problems(page))

    def test_mixed_versions_are_rejected(self):
        page = ("<p class=\"meta\">v1.1.0 · 构建 38</p>\n"
                '<a href="https://github.com/o/r/releases/latest/download/Lampyris-1.1.0-universal.dmg">新</a>\n'
                '<a href="https://github.com/o/r/releases/latest/download/Lampyris-1.0.2-universal.dmg">旧</a>')
        self.assertTrue(problems(page))


if __name__ == "__main__":
    unittest.main()
