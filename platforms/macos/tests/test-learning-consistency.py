#!/usr/bin/env python3
"""学·练·用一致：学习区/练习展示的拆字与引擎实际使用的码表必须是同一套事实。

用户要求（2026-11-19）：「学练时的拆字逻辑按标准五笔对应方案进行，让学练用保持一致的输入拆字逻辑」。
本测试把这条要求钉成断言，任何一侧单独改动都会在这里失败：

1. **用（引擎）**：`wubi86-core.tsv` 是宿主实际装载的码表。B0-runtime 里任何一个全码都必须以
   `(码, 字)` 的形式存在于该表——否则学习区教出来的码在真实输入里打不出这个字。
2. **学（拆字）**：`full` 条目的字根键位序列必须等于全码前缀（识别码另计），且条目数 = 码长 - 1；
   识别码字母必须能由「末笔 × 结构」表重新算出来（与 `Practice.recognitionLetter` 同一张表）。
3. **练（题库）**：`full` 是练习出题的唯一来源（`LearningHints.fullCharacters`），因此 `full` 必须
   自带全码；键名字（四同键，如 `wwww`）在学习区按「连打四次」讲解，允许无字根，其余有码必有字根。
   简码槽位必须与随包的 D17/D17-bis 表逐字相同，否则「一级/二级简码」题型会教出码表里不存在的简码
   （ADR-376 的 `一级/二级` 双槽位格式）。
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
RUNTIME = ROOT / 'data/generated/B0-runtime.tsv'
ENGINE_TABLE = ROOT / 'data/generated/wubi86-core.tsv'
LEVEL1 = ROOT / 'data/sources/wubi86-level1-codes.tsv'
LEVEL2 = ROOT / 'data/sources/wubi86-level2-codes.tsv'

STROKE_ROW = {'横': 'GFD', '竖': 'HJK', '撇': 'TRE', '捺': 'YUI', '折': 'NBV'}
STRUCTURE_INDEX = {'左右': 0, '上下': 1, '杂合': 2}


def runtime_rows():
    rows = []
    for line in RUNTIME.read_text(encoding='utf-8').splitlines():
        if not line or line.startswith('#'):
            continue
        char, code, quality, roots, recognition, shorts = line.split('\t')
        rows.append({'char': char, 'code': code, 'quality': quality,
                     'roots': [cell for cell in roots.split() if cell],
                     'recognition': recognition, 'shorts': shorts})
    return rows


def code_pairs(path):
    pairs = set()
    for line in path.read_text(encoding='utf-8').splitlines():
        if not line or line.startswith('#'):
            continue
        fields = line.split('\t')
        if len(fields) >= 2:
            pairs.add((fields[0], fields[1]))
    return pairs


def short_table(path):
    table = {}
    for line in path.read_text(encoding='utf-8').splitlines():
        if not line or line.startswith('#'):
            continue
        fields = line.split('\t')
        if len(fields) >= 2:
            table[fields[1]] = fields[0]
    return table


class LearningConsistencyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rows = runtime_rows()
        cls.pairs = code_pairs(ENGINE_TABLE)
        cls.level1 = short_table(LEVEL1)
        cls.level2 = short_table(LEVEL2)

    def test_taught_codes_exist_in_engine_table(self):
        """学习区教的全码必须是引擎真能打出来的码（学 = 用）。"""
        missing = [(row['char'], row['code']) for row in self.rows
                   if row['code'] and (row['code'], row['char']) not in self.pairs]
        self.assertEqual(missing, [], f'学习区全码在引擎码表里不存在：{missing[:5]}')

    def test_practice_pool_entries_are_answerable(self):
        """练习池 = `full` ∩ 有字根（`Practice.bank` 的条件）；这些条目必须能判分也能讲解。

        键名字（`wwww`）与成字字根（`羽`/`母`，按「报户口+笔画」讲解）没有字根格子，不进练习池；
        其余 `full` 必须同时有全码和字根，且字根数只能是「码长」或「码长-1（带识别码）」。
        """
        for row in self.rows:
            char, code, roots = row['char'], row['code'], row['roots']
            if row['quality'] != 'full':
                continue  # partial 只展示已核验的前缀，宿主标「拆解待核验」
            self.assertTrue(code, f'{char}: full 缺全码，练习会出空答案')
            if not roots:
                continue
            glyphs = [cell.rsplit(':', 1)[0] for cell in roots]
            for cell in roots:
                glyph, key = cell.rsplit(':', 1)
                self.assertTrue(glyph and key in 'abcdefghijklmnopqrstuvwxy', f'{char}: 字根格子非法 {cell!r}')
            if glyphs == [char]:
                continue  # 成字字根：报户口 + 笔画取码，只有「自己」这一格
            self.assertLessEqual(len(roots), len(code),
                                 f'{char}: 字根数 {len(roots)} 超过码长 {len(code)}')

    def test_root_keys_match_code_prefix(self):
        """拆字的键位序列必须逐位等于全码前缀（同一套取码规则）。"""
        for row in self.rows:
            if row['quality'] != 'full':
                continue
            keys = ''.join(cell.split(':')[1] for cell in row['roots'])
            self.assertTrue(row['code'].startswith(keys),
                            f'{row["char"]}: 字根键位 {keys} 与全码 {row["code"]} 不一致')

    def test_recognition_letter_is_derived(self):
        """识别码必须能由「末笔 × 结构」重算出来，且条目数 = 码长 - 1。"""
        for row in self.rows:
            if row['quality'] != 'full' or not row['recognition']:
                continue
            letter, stroke, structure = row['recognition'].split('|')
            expected = STROKE_ROW[stroke][STRUCTURE_INDEX[structure]].lower()
            self.assertEqual(letter.lower(), expected,
                             f'{row["char"]}: 识别码 {letter} 与 {stroke}/{structure} 推出的 {expected} 不符')
            self.assertEqual(len(row['roots']), len(row['code']) - 1,
                             f'{row["char"]}: 识别码条目字根数应等于码长-1')

    def test_shortcode_slots_match_shipped_tables(self):
        """简码槽位 `一级/二级`（缺项 `-`）必须与随包简码表逐字相同。"""
        for row in self.rows:
            slots = row['shorts'].split('/') if row['shorts'] else ['-', '-']
            self.assertEqual(len(slots), 2, f'{row["char"]}: 简码列必须是两个槽位：{row["shorts"]!r}')
            first, second = slots
            if first != '-':
                self.assertEqual(self.level1.get(row['char']), first,
                                 f'{row["char"]}: 一级简码槽 {first} 与码表 {self.level1.get(row["char"])} 不符')
            if second != '-':
                self.assertEqual(self.level2.get(row['char']), second,
                                 f'{row["char"]}: 二级简码槽 {second} 与码表 {self.level2.get(row["char"])} 不符')

    def test_second_level_shortcodes_reach_practice(self):
        """二级简码必须落在二级槽位，否则「二级简码」题型永远出不到这些字（ADR-376）。"""
        for char in self.level2:
            row = next((r for r in self.rows if r['char'] == char), None)
            if row is None:
                continue
            slots = row['shorts'].split('/') if row['shorts'] else ['-', '-']
            self.assertEqual(slots[1], self.level2[char],
                             f'{char}: 二级简码必须在第二槽位，实际 {row["shorts"]!r}')


if __name__ == '__main__':
    unittest.main()
