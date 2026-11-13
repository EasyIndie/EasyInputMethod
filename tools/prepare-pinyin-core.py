#!/usr/bin/env python3
"""Select baseline/training vocabulary and validated registered combinations."""
import hashlib
import json
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
source = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "data/generated/pinyin-words.tsv"
target = Path(sys.argv[2]) if len(sys.argv) > 2 else root / "data/generated/pinyin-core.tsv"
limit = int(sys.argv[3]) if len(sys.argv) > 3 else 20_000
budget = int(sys.argv[4]) if len(sys.argv) > 4 else 800_000
if limit <= 0 or budget <= 0:
    raise SystemExit("limit/budget 必须是正整数")
selected = {fields[2] for line in (root / "data/input-quality.tsv").read_text().splitlines()
            if not line.startswith("#") and len(fields := line.split("\t")) == 3 and fields[1] == "train"}
domain_path = root / "data/domain-vocabulary.tsv"
domain_raw = domain_path.read_bytes()
readings = {}
for line in (root / "data/generated/pinyin-chars.tsv").read_text().splitlines():
    if line and not line.startswith("#"):
        spelling, character, _ = line.split("\t")
        readings.setdefault(character, set()).add(spelling)
domain = []
seen = set()
for number, line in enumerate(domain_raw.decode().splitlines(), 1):
    if not line or line.startswith("#"):
        continue
    fields = line.split("\t")
    if len(fields) != 3:
        raise ValueError(f"D16第{number}行缺列")
    _, word, spelling = fields
    syllables = spelling.split(" ")
    if len(word) < 2 or len(word) != len(syllables) or word in seen:
        raise ValueError(f"D16第{number}行重复或字音不对齐")
    if any(syllable not in readings.get(character, set()) for character, syllable in zip(word, syllables)):
        raise ValueError(f"D16第{number}行读音未由D5字符表支持")
    seen.add(word)
    domain.append((word, spelling))
selected.update(seen)
raw = source.read_bytes()
rows = []
for line in raw.decode("utf-8").splitlines():
    if not line or line.startswith("#"):
        continue
    pinyin, word, weight = line.split("\t")
    rows.append((int(weight), word, pinyin))
rows.sort(key=lambda row: (-row[0], row[1], row[2]))
# Freeze the original baseline selection before adding any new reading aliases.
kept = [row for index, row in enumerate(rows) if index < limit or row[1] in selected]
pairs = {(word, spelling) for _, word, spelling in kept}
weights = {}
for weight, word, _ in rows:
    weights[word] = max(weights.get(word, 1), weight)
for word, spelling in domain:
    if (word, spelling) not in pairs:
        kept.append((weights.get(word, 1), word, spelling))
kept.sort(key=lambda row: (-row[0], row[1], row[2]))
label = "核心" if limit == 20_000 else "扩展"
adr = "ADR-031/237" if limit == 20_000 else "ADR-031/237/348"
header = (f"# 萤火虫{label}拼音词表；CC-BY-SA-4.0；{adr}\n"
          f"# 来源D4/D5/D10/D15/D16；{limit // 1000}k基础词+训练词+自编组合；"
          "已有权重不变，新词权重1。\n")
output = bytearray(header.encode())
count = 0
for weight, word, pinyin in kept:
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
    "limit": limit, "budget_bytes": budget, "output_bytes": len(output), "entries": count,
    "order": f"top {limit} plus D15 train and frozen D16; new words weight 1",
    "selection_sha256": hashlib.sha256((root / "data/input-quality.tsv").read_bytes()).hexdigest(),
    "domain_sha256": hashlib.sha256(domain_raw).hexdigest(), "domain_entries": len(domain),
    "sources": ["D4", "D5", "D10", "D15", "D16"], "license": "CC-BY-SA-4.0",
}
report_path = target.with_name(target.stem + "-report.json")
report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print(json.dumps(report, ensure_ascii=False))
