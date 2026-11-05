#!/usr/bin/env python3
"""生成候选排序评测样本集 `tools/eval/samples.tsv`。

样本只从仓库内**已登记**的数据派生，可复现：

| 类别 | 来源 | 取法 |
|---|---|---|
| `jianma1` | 五笔86 一级简码（公开标准，见 `docs/技术方案.md`） | 25 个键位全取，按键 = 1 字母 |
| `jianma2` | 高频单字取码表前两码（ADR-304 的二级简码规则） | 30 条，按键 = 2 字母 |
| `single` | 意图频次取 `data/generated/pinyin-chars.tsv`（jieba 单字词频，D10），码取码表 | 前 50 个高频单字；**意图来源与码表排序权重不同源**，否则"首选率 100%"是自证 |
| `word2` | `data/input-quality.tsv` **holdout** 两字词（ADR-227） | 全部，且码表里有 4 字母码 |
| `word2v` | 同上 **validation** 两字词 | 补足数量用（与 holdout 分开统计，避免混考卷） |
| `word34` | 同上，按 holdout → validation → train 顺序取够 | 三/四字词（考的是同码内排序，不是泛化，故三份都用） |
| `sentence` | 同上，同一顺序 | 五字及以上，按码表贪心切词拼成 `|` 分段键入串 |

`input-quality.tsv` 的 holdout 只用于冻结后评估，这里正是它的用途；
样本集一旦入库就不再改动（要改等于换考卷，必须在报告里说明）。
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TABLE = ROOT / "data/generated/wubi86-core.tsv"
CHAR_FREQ = ROOT / "data/generated/pinyin-chars.tsv"
QUALITY = ROOT / "data/input-quality.tsv"
OUT = ROOT / "tools/eval/samples.tsv"

# 五笔86 一级简码（G 键位表）：一键位对应一字母。
LEVEL1 = {
    "g": "一", "f": "地", "d": "在", "s": "要", "a": "工",
    "h": "上", "j": "是", "k": "中", "l": "国", "m": "同",
    "t": "和", "r": "的", "e": "有", "w": "人", "q": "我",
    "y": "主", "u": "产", "i": "不", "o": "为", "p": "这",
    "n": "民", "b": "了", "v": "发", "c": "以", "x": "经",
}


def load_table() -> tuple[dict[str, list[tuple[int, str]]], dict[str, list[tuple[int, str]]]]:
    """返回 (text → [(weight, code)], code → [(weight, text)])。"""
    by_text: dict[str, list[tuple[int, str]]] = {}
    by_code: dict[str, list[tuple[int, str]]] = {}
    for line in TABLE.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 3:
            raise SystemExit(f"码表行格式异常：{line!r}")
        code, text, weight = parts[0], parts[1], int(parts[2])
        by_text.setdefault(text, []).append((weight, code))
        by_code.setdefault(code, []).append((weight, text))
    return by_text, by_code


def load_quality(split: str) -> list[str]:
    rows = []
    for line in QUALITY.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) == 3 and parts[1] == split:
            rows.append(parts[2])
    return rows


def best_code(by_text: dict[str, list[tuple[int, str]]], text: str, length: int = 4) -> str | None:
    codes = [(w, c) for w, c in by_text.get(text, []) if len(c) == length]
    if not codes:
        return None
    return max(codes)[1]


def build() -> list[tuple[str, str, str]]:
    by_text, by_code = load_table()
    samples: list[tuple[str, str, str]] = []

    for key, char in LEVEL1.items():
        samples.append(("jianma1", key, char))

    # 意图频次用 jieba 单字词频（pinyin-chars），与码表排序用的 WindInput 权重不同源。
    freq: dict[str, int] = {}
    for line in CHAR_FREQ.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        parts = line.split("	")
        if len(parts) == 3 and len(parts[1]) == 1:
            freq[parts[1]] = max(freq.get(parts[1], 0), int(parts[2]))
    singles = sorted(((w, t) for t, w in freq.items()), reverse=True)
    for _, char in singles:
        code = best_code(by_text, char)
        if code and len(code) == 4 and sum(1 for s in samples if s[0] == "jianma2") < 30:
            samples.append(("jianma2", code[:2], char))
    seen: set[str] = set()
    for _, char in singles:
        if char in seen:
            continue
        code = best_code(by_text, char)
        if not code:
            continue
        seen.add(char)
        samples.append(("single", code, char))
        if len(seen) == 50:
            break

    # 长词与句子数量少，按 holdout → validation → train 顺序取够；两字词两套分开统计。
    budget = {"word34": 23, "sentence": 25}
    for split in ("holdout", "validation", "train"):
        for word in load_quality(split):
            size = len(word)
            if size == 2:
                code = best_code(by_text, word)
                if code and split == "holdout":
                    samples.append(("word2", code, word))
                elif code and len([s for s in samples if s[0] == "word2v"]) < 30:
                    samples.append(("word2v", code, word))
            elif size in (3, 4):
                code = best_code(by_text, word)
                if code and budget["word34"] > 0:
                    samples.append(("word34", code, word))
                    budget["word34"] -= 1
            else:
                segments = segment(word, by_text)
                if segments and budget["sentence"] > 0:
                    samples.append(("sentence", "|".join(segments), word))
                    budget["sentence"] -= 1
    return samples


def segment(word: str, by_text: dict[str, list[tuple[int, str]]]) -> list[str] | None:
    """按码表里最长的词贪心切分，返回每段的按键串。切不动返回 None。"""
    codes: list[str] = []
    index = 0
    while index < len(word):
        match = None
        for size in range(min(4, len(word) - index), 0, -1):
            piece = word[index : index + size]
            code = best_code(by_text, piece)
            if code:
                match = (code, size)
                break
        if match is None:
            return None
        codes.append(match[0])
        index += match[1]
    return codes


def main() -> int:
    samples = build()
    counts: dict[str, int] = {}
    for category, _, _ in samples:
        counts[category] = counts.get(category, 0) + 1

    header = [
        "# 候选排序评测样本集（tools/eval/gen-samples.py 生成，勿手改）",
        "# category\tkeys\ttarget；keys 用 | 分段，模拟按词组码后逐段确认",
        "# 来源：一级简码=公开标准；单字=data/generated/wubi86-core.tsv（D3/D10）；",
        "#       词/句=data/input-quality.tsv holdout 分割（ADR-227）",
        "# 生成命令：python3 tools/eval/gen-samples.py",
    ]
    body = [f"{c}\t{k}\t{t}" for c, k, t in samples]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(header + body) + "\n", encoding="utf-8")
    print(f"写入 {OUT.relative_to(ROOT)}：{len(body)} 条 " +
          " ".join(f"{k}={v}" for k, v in sorted(counts.items())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
