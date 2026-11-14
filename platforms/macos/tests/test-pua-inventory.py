"""N1-d 自绘清单：PUA inventory 的覆盖与「不猜」契约。"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
INVENTORY = ROOT / "modules/hanzi-structure/corpus/pua-inventory.tsv"


class PuaInventoryTests(unittest.TestCase):
    def test_inventory_covers_three_thousand_partials(self):
        rows = [line.split("\t") for line in INVENTORY.read_text(encoding="utf-8").splitlines()
                if line and not line.startswith("#")]
        self.assertGreaterEqual(len(rows), 250)
        known = [r for r in rows if r[2] == "known"]
        unresolved = [r for r in rows if r[2] == "unresolved"]
        self.assertGreaterEqual(len(known), 150)
        self.assertGreaterEqual(len(unresolved), 100)
        self.assertTrue(all(r[1] for r in known), "known 行必须有 label")
        self.assertTrue(all(not r[1] for r in unresolved), "unresolved 行不得填猜测 label")
        self.assertTrue(all(r[0] and r[4].isdigit() and int(r[4]) > 0 for r in rows))

    def test_inventory_mentions_adr(self):
        text = INVENTORY.read_text(encoding="utf-8")
        self.assertIn("ADR-353", text)
        self.assertIn("自绘", text)
        self.assertIn("pua\tlabel\tstatus", text)


if __name__ == "__main__":
    unittest.main()
