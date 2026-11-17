"""运行时数据只保留一份清单（报告 294）：正式包与预览不得各写一套复制列表。"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
MANIFEST = ROOT / 'platforms/macos/runtime-resources.txt'


class RuntimeResourceTests(unittest.TestCase):
    def entries(self):
        rows = []
        for line in MANIFEST.read_text(encoding='utf-8').splitlines():
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            relative, name = line.split()
            rows.append((relative, name))
        return rows

    def test_manifest_files_exist_and_are_unique(self):
        rows = self.entries()
        self.assertGreaterEqual(len(rows), 10)
        names = [name for _, name in rows]
        self.assertEqual(len(names), len(set(names)), 'bundle 文件名重复')
        for relative, _ in rows:
            self.assertTrue((ROOT / relative).is_file(), f'清单引用了不存在的文件 {relative}')

    def test_builders_follow_the_manifest(self):
        for script in ('platforms/macos/build.sh', 'platforms/macos/dev-preview.sh'):
            text = (ROOT / script).read_text(encoding='utf-8')
            self.assertIn('runtime-resources.txt', text, f'{script} 未读取统一清单')
        # 关键回归：预览曾漏复制 key-roots，键位图没有字根/口诀。
        self.assertIn(('modules/keymap/data/key-roots-wubi86.tsv', 'key-roots-wubi86.tsv'), self.entries())

    def test_no_per_file_copy_lists_remain(self):
        build = (ROOT / 'platforms/macos/build.sh').read_text(encoding='utf-8')
        self.assertNotIn('copy_data "${GENERATED}/wubi86-core.tsv"', build,
                         'build.sh 又出现逐文件复制列表，请改为只维护 runtime-resources.txt')
        preview = (ROOT / 'platforms/macos/dev-preview.sh').read_text(encoding='utf-8')
        self.assertNotIn('cp "${ROOT}/data/symbols.tsv"', preview,
                         'dev-preview.sh 又出现逐文件复制，请改为只维护 runtime-resources.txt')


if __name__ == '__main__':
    unittest.main()
