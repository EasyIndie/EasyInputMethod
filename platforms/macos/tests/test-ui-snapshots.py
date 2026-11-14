#!/usr/bin/env python3
"""UI 离屏快照必须能编译并产出图片（防止 `scripts/ui-snapshots.sh` 的源码清单漂移）。

2026-11-15：候选窗新增 `CaretPlacement` / `LearningHints` 依赖后，快照脚本的硬编码
源码清单没有同步，`make macos-ui-snapshots` 直接编译失败。这里跑候选窗这一档（最少的
源码集合、命中缓存后约数秒），确保快速 UI 迭代入口始终可用。
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / 'scripts/ui-snapshots.sh'


class UISnapshotsTests(unittest.TestCase):
    def test_candidate_snapshot_builds_and_renders(self):
        with tempfile.TemporaryDirectory(prefix='lampyris-ui-shot-') as out:
            env = dict(os.environ, UI='candidate', OUT=out)
            result = subprocess.run(
                [str(SCRIPT)], cwd=ROOT, env=env,
                capture_output=True, text=True, timeout=300,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            pngs = sorted(Path(out).glob('*.png'))
            self.assertTrue(pngs, '候选窗快照没有产出图片')
            for png in pngs:
                self.assertGreater(png.stat().st_size, 1024, f'{png.name}: 图片为空')


if __name__ == '__main__':
    unittest.main()
