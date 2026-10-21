#!/usr/bin/env python3
"""Select baseline vocabulary and training terms from registered pinyin data."""
import hashlib
import json
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
source = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "data/generated/pinyin-words.tsv"
target = Path(sys.argv[2]) if len(sys.argv) > 2 else root / "data/generated/pinyin-core.tsv"
budget = 800_000
limit = 20_000
selected = {fields[2] for line in (root / "data/input-quality.tsv").read_text().splitlines()
            if not line.startswith("#") and len(fields := line.split("\t")) == 3 and fields[1] == "train"}
raw = source.read_bytes()
rows = []
for line in raw.decode("utf-8").splitlines():
    if not line or line.startswith("#"):
        continue
    pinyin, word, weight = line.split("\t")
    rows.append((int(weight), word, pinyin))
rows.sort(key=lambda row: (-row[0], row[1], row[2]))
output = bytearray("# 萤火虫核心拼音词表；CC-BY-SA-4.0；ADR-031\n# 来源 D4/D5/D10（MIT）；前20000条加D15训练词，原始词频不变，详见数据许可文档。\n".encode())
count = 0
for index, (weight, word, pinyin) in enumerate(rows):
    if index >= limit and word not in selected:
        continue
    line = f"{pinyin}\t{word}\t{weight}\n".encode()
    if len(output) + len(line) > budget:
        raise ValueError("核心拼音词表超出预算")
    output.extend(line)
    count += 1
target.parent.mkdir(parents=True, exist_ok=True)
target.write_bytes(output)
report = {
    "source_sha256": hashlib.sha256(raw).hexdigest(),
    "output_sha256": hashlib.sha256(output).hexdigest(),
    "budget_bytes": budget, "output_bytes": len(output), "entries": count,
    "order": "top 20000 by weight, word, pinyin plus D15 train; holdout excluded",
    "selection_sha256": hashlib.sha256((root / "data/input-quality.tsv").read_bytes()).hexdigest(),
    "sources": ["D4", "D5", "D10", "D15"], "license": "CC-BY-SA-4.0",
}
target.with_name("pinyin-core-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print(json.dumps(report, ensure_ascii=False))
