"""U3-5 符号 / emoji 数据：覆盖、搜索词、许可登记与报告 SHA。"""
from pathlib import Path
import hashlib
import json
import tomllib
import unittest

ROOT = Path(__file__).resolve().parents[3]
SYMBOLS = ROOT / "data/symbols.tsv"
EMOJI = ROOT / "data/generated/emoji.tsv"
REPORT = ROOT / "data/generated/emoji-report.json"


def rows(path):
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        # 注释以「# 」开头；emoji `#️⃣` 的数据行以 # 开头但不是注释。
        if not line or line == "#" or line.startswith("# "):
            continue
        fields = line.split("\t")
        assert len(fields) >= 4, f"{path.name}: {line!r}"
        out.append(fields)
    return out


class SymbolEmojiDataTests(unittest.TestCase):
    def test_symbols_cover_six_categories(self):
        data = rows(SYMBOLS)
        self.assertGreaterEqual(len(data), 250)
        categories = {row[0] for row in data}
        self.assertEqual(categories, {"punctuation", "math", "currency", "arrow", "number", "misc"})
        chars = [row[1] for row in data]
        self.assertEqual(len(chars), len(set(chars)), "符号字符重复")
        self.assertTrue(all(row[2] and row[3] for row in data))

    def test_emoji_full_set_and_searchable(self):
        data = rows(EMOJI)
        self.assertEqual(len(data), 3781)
        self.assertEqual(len({row[0] for row in data}), len(data), "emoji 重复")
        self.assertTrue(all(row[4] and row[5] for row in data), "emoji 缺中/英文名")
        self.assertTrue(all(len(row) >= 9 and row[8] for row in data), "emoji 缺拼音搜索词")
        groups = {row[1] for row in data}
        self.assertEqual(len(groups), 9)
        text = "\n".join("\t".join(row) for row in data)
        for term in ("笑", "heart", "牵手", "美国", "xiao", "lian"):
            self.assertIn(term, text, f"缺少搜索词 {term}")
        symbols = (SYMBOLS).read_text(encoding="utf-8")
        for term in ("逗号", "douhao", "箭头"):
            self.assertIn(term, symbols, f"缺少符号搜索词 {term}")

    def test_report_and_sources_registered(self):
        report = json.loads(REPORT.read_text(encoding="utf-8"))
        self.assertEqual(report["entries"], 3781)
        self.assertEqual(report["missing_zh_short_name"], 0)
        actual = hashlib.sha256(EMOJI.read_bytes()).hexdigest()
        self.assertEqual(report["output_sha256"], actual)

        with open(ROOT / "data/sources.toml", "rb") as stream:
            sources = tomllib.load(stream)
        ids = {item.get("id") for item in sources.get("source", [])}
        self.assertTrue({"D21", "D22", "D23"} <= ids)
        derived = {item.get("id") for item in sources.get("derived", [])}
        self.assertIn("emoji-v1", derived)
        for item in sources.get("source", []):
            if item.get("id") in ("D21", "D22"):
                self.assertIn("Unicode", item.get("license", ""))
                self.assertTrue(item.get("fetch_script"))

    def test_build_copies_picker_data(self):
        build = (ROOT / "platforms/macos/build.sh").read_text(encoding="utf-8")
        for name in ("emoji.tsv", "symbols.tsv"):
            self.assertIn(f'"{name}"', build)


if __name__ == "__main__":
    unittest.main()
