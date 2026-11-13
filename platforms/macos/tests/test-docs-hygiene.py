"""文档卫生（报告236）：活文档必须可索引、活链接必须能打开、任务卡只放活跃的。

覆盖三类真实踩过的腐坏：发布说明停在 0.1.15、任务卡目录堆了 62 张已完成的卡、
`docs/迭代计划.md` 被 8 个文件引用但其实早已不存在。
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
DOCS = ROOT / 'docs'

# 冻结的过程/证据目录：允许内部链接失效，不要求被索引。
FROZEN = ('archive', 'history', 'reviews', 'design', 'experiments', 'research')
LIVE_CARD_ALLOWLIST = {'README.md', 'T-ITER-22.md', 'T-ITER-22-coverage.md', 'T-ITER-22-1.1.0-affected.md',
                       'T-U3-5-symbol-emoji.md'}

LINK_RE = re.compile(r'\[[^\]]*\]\(([^)#]+\.md)(?:#[^)]*)?\)')


def live_docs():
    files = [p for p in DOCS.glob('*.md')]
    files += list((DOCS / 'tasks').glob('*.md'))
    files += list((DOCS / 'releases').glob('*.md'))
    files += [p for p in ROOT.glob('*.md')]
    return sorted(set(files))


def frozen(path: Path) -> bool:
    rel = path.relative_to(DOCS)
    return any(str(rel).startswith(name + '/') for name in FROZEN)


class DocsHygieneTests(unittest.TestCase):
    def test_live_links_resolve(self):
        broken = []
        for doc in live_docs():
            for target in LINK_RE.findall(doc.read_text(encoding='utf-8', errors='replace')):
                if target.startswith('http'):
                    continue
                resolved = (doc.parent / target).resolve()
                if not resolved.exists():
                    broken.append(f'{doc.relative_to(ROOT)} -> {target}')
        self.assertEqual(broken, [], '活文档里有打不开的链接：\n' + '\n'.join(broken))

    def test_live_docs_are_indexed(self):
        index = (DOCS / 'README.md').read_text(encoding='utf-8')
        cards = (DOCS / 'tasks' / 'README.md').read_text(encoding='utf-8')
        missing = []
        for doc in live_docs():
            rel = doc.relative_to(DOCS) if DOCS in doc.parents else doc.relative_to(ROOT)
            name = doc.name
            # releases 只要在 README 里以 releases/ 目录形式登记即可
            if str(rel).startswith('releases/') or doc.name in ('README.md', 'TEMPLATE-task.md'):
                continue
            if doc.parent.name == 'tasks':
                if name not in cards:
                    missing.append(f'tasks/{name}（未在 tasks/README.md 登记）')
                continue
            if name not in index:
                missing.append(str(rel))
        self.assertEqual(missing, [], '活文档没有被索引：\n' + '\n'.join(missing))

    def test_only_live_task_cards_in_tasks_dir(self):
        extra = sorted(p.name for p in (DOCS / 'tasks').glob('*.md') if p.name not in LIVE_CARD_ALLOWLIST)
        self.assertEqual(extra, [], 'docs/tasks 只放活跃卡；已完成的请 git mv 到 docs/archive/tasks：' + ', '.join(extra))

    def test_archive_is_registered(self):
        index = (DOCS / 'archive' / 'README.md').read_text(encoding='utf-8')
        unlisted = [p.name for p in (DOCS / 'archive').glob('*.md')
                    if p.name != 'README.md' and p.name not in index]
        self.assertEqual(unlisted, [], 'archive/ 新增文件必须登记到 archive/README.md：' + ', '.join(unlisted))

    def test_release_notes_indexed_or_listed(self):
        index = (DOCS / 'README.md').read_text(encoding='utf-8')
        self.assertIn('releases/', index, 'docs/README 必须提到 releases/ 目录')
        for note in (DOCS / 'releases').glob('*.md'):
            self.assertTrue(note.name in index or any(v in index for v in (note.stem,)),
                            f'发布说明 {note.name} 未在 docs/README 登记')


if __name__ == '__main__':
    unittest.main()
