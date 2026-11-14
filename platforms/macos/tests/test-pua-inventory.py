"""N1-d 补充区 PUA 清单：覆盖、来源与「不猜」契约（ADR-353 / 报告 280）。"""
import re
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
INVENTORY = ROOT / "modules/hanzi-structure/corpus/pua-inventory.tsv"
SUPPLEMENTARY = ROOT / "modules/hanzi-structure/corpus/pua-supplementary.tsv"
KEY_RE = re.compile(r"^(?:-|[a-y]):\d+(?:,(?:-|[a-y]):\d+)*$")
PUA_RE = re.compile(r"^(?:U\+)?[0-9A-Fa-f]{4,6}$")


def rows(path):
    return [line.split("\t") for line in path.read_text(encoding="utf-8").splitlines()
            if line and not line.startswith("#")]


def map_rows():
    out = {}
    for row in rows(SUPPLEMENTARY):
        out.setdefault(row[0], []).append(row)
    return out


class PuaInventoryTests(unittest.TestCase):
    def test_inventory_is_d2_supplementary_only(self):
        data = rows(INVENTORY)
        self.assertGreaterEqual(len(data), 70)
        for pua, _label, _status, keys, occurrences, samples in data:
            self.assertEqual(len(pua), 1, f"pua 应为单个字符：{pua!r}")
            self.assertGreaterEqual(ord(pua), 0xF0000,
                                    f"{hex(ord(pua))} 不是 D2 补充区 PUA（不要重新混入 D3 BMP PUA）")
            self.assertRegex(keys, KEY_RE)
            self.assertTrue(occurrences.isdigit() and int(occurrences) > 0)
            self.assertTrue(samples)

    def test_status_and_no_guessing(self):
        data = rows(INVENTORY)
        statuses = [row[2] for row in data]
        self.assertGreaterEqual(statuses.count("verified"), 50)
        self.assertGreaterEqual(statuses.count("partial"), 5)
        self.assertGreaterEqual(statuses.count("unresolved"), 10)
        for pua, label, status, *_ in data:
            self.assertIn(status, {"verified", "partial", "unresolved"})
            if status == "unresolved":
                self.assertEqual(label, "", f"{pua}: unresolved 不得填猜测 label")
            else:
                self.assertTrue(label, f"{pua}: {status} 必须有 label")
                self.assertFalse(0xE000 <= ord(label[0]) <= 0xF8FF or ord(label[0]) >= 0xF0000,
                                 f"{pua}: label 不得是私有区字形")

    def test_inventory_mentions_adr_and_source(self):
        text = INVENTORY.read_text(encoding="utf-8")
        self.assertIn("ADR-353", text)
        self.assertIn("wubi-lex-86.txt", text)
        self.assertIn("自绘", text)
        self.assertIn("pua\tlabel\tstatus", text)

    def test_supplementary_map_contract(self):
        mapping = map_rows()
        self.assertGreaterEqual(len(mapping), 60)
        for pua, entries in mapping.items():
            self.assertRegex(pua, PUA_RE)
            self.assertGreaterEqual(ord(chr(int(pua.replace("U+", ""), 16))), 0xF0000)
            for _pua, key, label, status, evidence in entries:
                self.assertRegex(key, r"^[a-y*]$")
                self.assertEqual(status, "verified")
                self.assertTrue(label)
                self.assertTrue(evidence)
                self.assertFalse(0xE000 <= ord(label[0]) <= 0xF8FF or ord(label[0]) >= 0xF0000)

    def test_labels_come_from_supplementary_map(self):
        mapping = map_rows()
        for pua, label, status, *_ in rows(INVENTORY):
            if status == "unresolved":
                continue
            cp = f"U+{ord(pua):05X}"
            self.assertIn(cp, mapping, f"{cp} 有 label 却不在核验表")
            labels = {row[2] for row in mapping[cp]}
            self.assertIn(label, labels, f"{cp}: 清单 label {label!r} 与核验表 {labels} 不一致")


if __name__ == "__main__":
    unittest.main()
