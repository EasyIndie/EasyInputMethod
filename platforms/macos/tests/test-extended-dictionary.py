"""U2-3 可选扩展词库：文件、体积、覆盖与报告一致性。

核心表仍由 ADR-031 / ADR-227 约束；扩展包只在 `dict.extended=true` 时装载。
"""
from pathlib import Path
import hashlib
import json
import unittest

ROOT = Path(__file__).resolve().parents[3]
GENERATED = ROOT / "data/generated"

WUBI_CORE = GENERATED / "wubi86-core.tsv"
WUBI_EXTENDED = GENERATED / "wubi86-extended.tsv"
PINYIN_CORE = GENERATED / "pinyin-core.tsv"
PINYIN_EXTENDED = GENERATED / "pinyin-extended.tsv"
PINYIN_REPORT = GENERATED / "pinyin-extended-report.json"

WUBI_BUDGET = 7_000_000
PINYIN_BUDGET = 1_500_000


def rows(path):
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        assert len(fields) == 3, f"{path.name}: {line!r}"
        out.append(tuple(fields))
    return out


class ExtendedDictionaryTests(unittest.TestCase):
    def test_files_exist_and_fit_budget(self):
        for path in (WUBI_EXTENDED, PINYIN_EXTENDED):
            self.assertTrue(path.is_file(), f"缺少 {path}")
        self.assertLessEqual(WUBI_EXTENDED.stat().st_size, WUBI_BUDGET)
        self.assertLessEqual(PINYIN_EXTENDED.stat().st_size, PINYIN_BUDGET)

    def test_wubi_extended_is_a_superset_of_core(self):
        core = {(code, text) for code, text, _ in rows(WUBI_CORE)}
        extended = {(code, text) for code, text, _ in rows(WUBI_EXTENDED)}
        missing = core - extended
        self.assertEqual(missing, set(), f"扩展表缺少核心行：{sorted(missing)[:5]}")
        self.assertGreater(len(extended), 300_000, "扩展五笔表应包含全量词组")

    def test_pinyin_extended_extends_core_and_matches_report(self):
        core = {text for _, text, _ in rows(PINYIN_CORE)}
        extended = {text for _, text, _ in rows(PINYIN_EXTENDED)}
        missing = core - extended
        self.assertEqual(missing, set(), f"扩展拼音表缺少核心词：{sorted(missing)[:5]}")
        self.assertGreater(len(extended), 40_000)

        report = json.loads(PINYIN_REPORT.read_text(encoding="utf-8"))
        actual = hashlib.sha256(PINYIN_EXTENDED.read_bytes()).hexdigest()
        self.assertEqual(report["output_sha256"], actual)
        self.assertEqual(report["limit"], 50_000)
        self.assertEqual(report["entries"], len(rows(PINYIN_EXTENDED)))

    def test_extension_adds_no_private_use_characters(self):
        """扩展包不得比核心表多引入私有区字形；核心表现有 6 个历史条目保持不变。"""
        def pua(path):
            found = set()
            for _, text, _ in rows(path):
                found.update(f"U+{ord(char):04X}" for char in text
                             if 0xE000 <= ord(char) <= 0xF8FF)
            return found
        self.assertEqual(pua(WUBI_EXTENDED), pua(WUBI_CORE))
        self.assertEqual(pua(PINYIN_EXTENDED), pua(PINYIN_CORE))

    def test_schema_and_build_wire_the_pack(self):
        schema = (ROOT / "crates/ime-config/src/schema.rs").read_text(encoding="utf-8")
        self.assertIn('key: "dict.extended"', schema)
        self.assertIn('default: "false"', schema)
        build = (ROOT / "platforms/macos/build.sh").read_text(encoding="utf-8")
        for name in ("wubi86-extended.tsv", "pinyin-extended.tsv"):
            self.assertIn(f'"{name}"', build)


if __name__ == "__main__":
    unittest.main()
