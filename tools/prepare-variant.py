#!/usr/bin/env python3
"""把 OpenCC 简→繁词典（STCharacters/STPhrases）编译为紧凑 TSV。

输入：data/sources/opencc-STCharacters.txt、opencc-STPhrases.txt（Apache-2.0）
输出：data/generated/variant-s2t.tsv，格式 `simplified\ttraditional`（按简体升序）。

规则：每条只取第一个候选（OpenCC s2t 的默认形式）；词组表负责消歧，
字符表兜底。运行时按“最长匹配”优先命中词组。
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "data" / "sources"
OUT = ROOT / "data" / "generated" / "variant-s2t.tsv"


def parse(path: Path) -> dict[str, str]:
    mapping: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) != 2:
            continue
        key, values = fields[0].strip(), fields[1].strip()
        if not key or not values:
            continue
        mapping[key] = values.split()[0]  # 第一个候选 = 默认
    return mapping


def main() -> None:
    chars = parse(SOURCES / "opencc-STCharacters.txt")
    phrases = parse(SOURCES / "opencc-STPhrases.txt")
    merged: dict[str, str] = {}
    merged.update(chars)
    merged.update(phrases)  # 词组优先覆盖同键（不应冲突，但以词组为准）
    entries = sorted((k, v) for k, v in merged.items() if k != v)
    header = (
        "# 萤火虫输入法 简→繁 转换表（自 OpenCC STCharacters/STPhrases 编译）\n"
        "# 许可 Apache-2.0；来源 https://github.com/BYVoid/OpenCC （见数据来源登记 D11）\n"
        "# 格式：simplified\\ttraditional\n"
    )
    OUT.write_text(header + "".join(f"{k}\t{v}\n" for k, v in entries), encoding="utf-8")
    print(f"wrote {OUT} entries={len(entries)} bytes={OUT.stat().st_size}")


if __name__ == "__main__":
    main()
