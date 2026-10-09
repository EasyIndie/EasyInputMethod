#!/usr/bin/env python3
"""Select a deterministic high-frequency prefix from the registered pinyin data."""
import hashlib
import json
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
source = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "data/generated/pinyin-words.tsv"
target = Path(sys.argv[2]) if len(sys.argv) > 2 else root / "data/generated/pinyin-core.tsv"
budget = 256 * 1024
raw = source.read_bytes()
rows = []
for line in raw.decode("utf-8").splitlines():
    if not line or line.startswith("#"):
        continue
    pinyin, word, weight = line.split("\t")
    rows.append((int(weight), word, pinyin))
rows.sort(key=lambda row: (-row[0], row[1], row[2]))
output = bytearray("# 萤火虫核心拼音词表；CC-BY-SA-4.0；ADR-031\n# 来源 D4/D5/D10（MIT）；256KiB 内按词频降序保留，详见数据许可文档。\n".encode())
count = 0
for weight, word, pinyin in rows:
    line = f"{pinyin}\t{word}\t{weight}\n".encode()
    if len(output) + len(line) > budget:
        break
    output.extend(line)
    count += 1
target.parent.mkdir(parents=True, exist_ok=True)
target.write_bytes(output)
report = {
    "source_sha256": hashlib.sha256(raw).hexdigest(),
    "output_sha256": hashlib.sha256(output).hexdigest(),
    "budget_bytes": budget, "output_bytes": len(output), "entries": count,
    "order": "weight descending, word ascending, pinyin ascending",
    "sources": ["D4", "D5", "D10"], "license": "CC-BY-SA-4.0",
}
target.with_name("pinyin-core-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print(json.dumps(report, ensure_ascii=False))
