#!/usr/bin/env python3
"""键位字根表契约：schema、覆盖、与生成器一致、体积。"""
from __future__ import annotations

import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
DATA = ROOT / "modules/keymap/data/key-roots-wubi86.tsv"
TOOL = ROOT / "modules/keymap/tools/build_key_roots.py"
RUNTIME = ROOT / "data/generated/B0-runtime.tsv"


def load_tool():
    spec = importlib.util.spec_from_file_location("build_key_roots", TOOL)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def rows():
    out = []
    for line in DATA.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        out.append(line.split("\t"))
    return out


class KeyRootTableTest(unittest.TestCase):
    def test_schema_and_coverage(self):
        table = rows()
        letters = [r[1] for r in table]
        self.assertEqual(len(letters), len(set(letters)), "键位不得重复")
        main_keys = set("QWERTYUIOPASDFGHJKLXCVBNM")
        self.assertTrue(main_keys <= set(letters), "必须覆盖 25 个主键")
        for row in table:
            self.assertEqual(len(row), 6, f"应为 6 列（含口诀）：{row}")
            self.assertEqual(row[0], "wubi86")
            self.assertIn(int(row[2]), {0, 1, 2, 3, 4, 5})
            # 键名通常是单字；万能键 Z 用"万能"两字说明，没有字根。
            self.assertIn(len(row[3]), (1, 2), "键名字根应为 1–2 字")
            roots = row[4].split()
            self.assertEqual(len(roots), len(set(roots)), "字根不得重复")
            self.assertNotIn(row[3], roots, "字根列表不应重复键名字根")
            if row[1] != "Z":
                self.assertTrue(row[5], f"键 {row[1]} 应有助记口诀")
            for root in roots:
                self.assertNotEqual(root, "？", "不得含占位符")
                self.assertFalse(0xF0000 <= ord(root[0]) <= 0xFFFFD, "不得含 PUA 码位")

    def test_every_main_key_has_roots(self):
        for row in rows():
            if row[1] == "Z":
                continue
            self.assertTrue(row[4].split(), f"键 {row[1]} 应至少有一个字根")

    def test_matches_generator(self):
        self.assertEqual(DATA.read_text(encoding="utf-8"), load_tool().build(RUNTIME),
                         "数据文件必须与生成器输出一致（改完请重跑生成器）")

    def test_display_roots_are_cjk_only(self):
        """视图只画 CJK 汉字/部件（康熙部首、注音符号在系统字体里没有字形，会显示成 ?）。"""
        ranges = ((0x4E00, 0x9FFF), (0x3400, 0x4DBF), (0xF900, 0xFAFF))
        for row in rows():
            for root in row[4].split():
                code = ord(root[0])
                self.assertTrue(any(low <= code <= high for low, high in ranges),
                                f"字根 {root} 不在可渲染范围")

    def test_size_budget(self):
        self.assertLess(DATA.stat().st_size, 32 * 1024)


if __name__ == "__main__":
    unittest.main(verbosity=2)
