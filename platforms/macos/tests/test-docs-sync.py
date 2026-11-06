"""版本、发布稿、HANDOFF、ROADMAP 必须互相对得上（报告235）。

踩过的坑：HANDOFF 停 1.0.0 而仓库已到 1.1.0；发布说明停在 0.1.15 而实际已发 1.0.2。
这类偏差靠"记得更新"解决不了，这里做成机器检查。
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]


def cargo_version() -> str:
    text = (ROOT / 'Cargo.toml').read_text(encoding='utf-8')
    return re.search(r'^version\s*=\s*"([^"]+)"', text, re.M).group(1)


def build_number() -> str:
    return (ROOT / 'packaging/build-number').read_text(encoding='utf-8').strip()


class DocsSyncTests(unittest.TestCase):
    def setUp(self):
        self.version = cargo_version()
        self.build = build_number()
        self.handoff = (ROOT / 'HANDOFF.md').read_text(encoding='utf-8')
        self.roadmap = (ROOT / 'ROADMAP.md').read_text(encoding='utf-8')

    def test_release_notes_exist_for_current_version(self):
        self.assertTrue((ROOT / 'docs/releases' / f'{self.version}.md').is_file(),
                        f'缺少 docs/releases/{self.version}.md')

    def test_roadmap_has_current_train(self):
        self.assertRegex(self.roadmap, r'## 当前发布列车：' + re.escape(self.version),
                         f'ROADMAP 顶部应有「当前发布列车：{self.version}」小节（对账三步同名）')
        heading = re.search(r'## 当前发布列车：([^\n（(]+)', self.roadmap)
        self.assertEqual(heading.group(1).strip(), self.version,
                         'ROADMAP 的发布列车版本与 Cargo.toml 不一致')
        self.assertIn('### 发布对账', self.roadmap, 'ROADMAP 必须保留发布对账清单')
        self.assertIn('## 历史任务', self.roadmap, 'ROADMAP 必须把历史任务与当前列车分开')

    def test_handoff_matches_version_and_build(self):
        self.assertIn(self.version, self.handoff,
                      f'HANDOFF 未提到当前版本 {self.version}（历史上出现过停在上一个版号）')
        self.assertIn(self.build, self.handoff,
                      f'HANDOFF 未提到当前构建号 {self.build}')


if __name__ == '__main__':
    unittest.main()
