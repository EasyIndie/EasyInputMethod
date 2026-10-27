#!/usr/bin/env python3
"""离线回归：产品页的版本描述必须精确到构建号，且不能自相矛盾。

版本真源是两个受控文件：`Cargo.toml` 的 `workspace.package.version` 与
`packaging/build-number`（见 `tools/release_version.py`）。

站点按 `docs/更新发布流程.md` §2.5 的约定**只在正式发布时才更新**，所以递增后
站点会短暂落后于仓库。这里允许「落后」，但钉死三件不能错的事：
1. 版本行必须带构建号（否则两个同版本候选在页面上无法区分）；
2. 站点不能**超前**于仓库真源（避免提前宣传还没构建出来的版本）；
3. 页面自身自洽：下载链接与版本行指向同一版，且不残留第二个版本号。
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

VERSION_LINE = re.compile(r"v(\d+)\.(\d+)\.(\d+) · 构建 ([1-9][0-9]{0,3})")
DOWNLOAD_LINK = re.compile(r"releases/latest/download/([^\"]+)")
ANY_VERSION = re.compile(r"v(\d+\.\d+\.\d+)")


def numbers(version, build):
    return tuple(int(part) for part in str(version).split(".")) + (int(build),)


def problems(html, identity):
    """返回产品页与版本真源不一致的原因列表；空列表表示通过。"""
    found = VERSION_LINE.search(html)
    if found is None:
        return ["版本行必须写成 `vX.Y.Z · 构建 NN`（精确到构建号）"]
    major, minor, patch, build = found.groups()
    site = numbers(f"{major}.{minor}.{patch}", build)
    repo = numbers(identity["version"], identity["build"])
    issues = []
    if site > repo:
        issues.append(f"站点宣传了尚未构建的版本：页面 {site}，仓库 {repo}")
    advertised = {"%s.%s.%s" % (major, minor, patch)}
    for version in ANY_VERSION.findall(html):
        if version not in advertised:
            issues.append(f"页面残留第二个版本号 v{version}")
    links = DOWNLOAD_LINK.findall(html)
    if not links:
        issues.append("页面没有下载链接")
    for name in links:
        if name != f"Lampyris-{major}.{minor}.{patch}-universal.dmg":
            issues.append(f"下载链接与本页版本不一致：{name}")
    return issues


class SiteVersionTests(unittest.TestCase):
    def setUp(self):
        self.identity = release_version.identity(ROOT)
        self.html = SITE.read_text()

    def test_product_page_is_consistent(self):
        self.assertEqual(problems(self.html, self.identity), [])

    def test_page_lags_at_most_one_release_behind(self):
        """落后是允许的（发布时才改），但不能停留在很旧的版本上。"""
        found = VERSION_LINE.search(self.html)
        site = numbers(".".join(found.groups()[:3]), found.group(4))
        repo = numbers(self.identity["version"], self.identity["build"])
        self.assertLessEqual(site[1], repo[1], "站点版本不得落后一个小版本以上")


class SiteVersionRuleTests(unittest.TestCase):
    """防止校验本身失效：三条规则各自能抓到反例。"""

    identity = {"version": "0.1.15", "build": "24"}

    def page(self, version="0.1.15", build="24"):
        return (
            f'<p class="meta">v{version} · 构建 {build} · 约 8 MB</p>\n'
            f'<a href="https://github.com/o/r/releases/latest/download/Lampyris-{version}-universal.dmg">下载</a>\n'
        )

    def test_accepts_current_and_lagging_page(self):
        self.assertEqual(problems(self.page(), self.identity), [])
        self.assertEqual(problems(self.page("0.1.14", "23"), self.identity), [])

    def test_rejects_page_without_build_number(self):
        html = self.page().replace(" · 构建 24", "")
        self.assertTrue(problems(html, self.identity))

    def test_rejects_page_ahead_of_the_repo(self):
        self.assertTrue(problems(self.page("0.1.16", "25"), self.identity))

    def test_rejects_mixed_versions(self):
        html = self.page() + '<a href="https://github.com/o/r/releases/latest/download/Lampyris-0.1.14-universal.dmg">旧</a>'
        self.assertTrue(problems(html, self.identity))


if __name__ == "__main__":
    unittest.main()
