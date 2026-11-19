# T-ROOT86：取得/自建五笔86 canonical 根序，关掉 326 条 partial

- 状态：待认领
- 模型建议：**pro**（七成是取码规则判断与人工核验，机械部分已拆好给脚本）
- 前置：ADR-377/378（运行时 v3、字表 5,021）、ADR-380（只做 86）
- 目标：GB2312 一级 3,755 字的 `full` 从 **3,429（91.3%）** 提到 **≥98%**（≥3,680），且**不降低判定标准、不用不合规数据**。

## 现状与缺口（可复跑）

```sh
awk -F'\t' '!/^#/{print $3}' data/generated/B0-runtime.tsv | sort | uniq -c
# full 4546 / partial 475（其中 GB2312 一级内 partial 326）
python3 modules/hanzi-structure/tests/validate_b0.py ...   # 台账 1,000 字 full 930
```

- 326 条 `partial` 的成因（报告 304 §4.3）：**283 条根序/键位不符**（D2 记视觉拆法，如 `提` 记 `扌日一`）
  + **43 条组件数与码长对不上**（缺复合字根）。
- 已验证**不可行**的省事路线（不要重复尝试）：用 IDS 叶子 + 241 标准字根反推根序 —— 475 条里只有 1 条能复现
  （`家 宀豕`），472 条粒度/写法不同（ADR-380 结果）。
- 不可行路线：cjk-decomp 直接对齐（报告 279 §6：738 条里 0 条可确认）；CDP（无五笔根序）。

## 路线 A：授权取得（先做，1–3 天，成本≈0）

1. 向**王码**（王码电脑/王永民团队）与可能的二手授权方，用同一封信问三个问题：
   1. 是否提供 **86 版逐字拆字（字根序列）** 数据（格式不限：表格/数据库/教材配套）；
   2. 是否允许**再分发**并以 **GPL-3-or-later** 发布衍生数据（含数字化、修改、商用与非商用）；
   3. 是否允许在公开仓库中登记来源与 SHA（我们会署名，且不暗示背书）。
2. 三问任一为否 → **放弃路线 A**，不进入仓库、不进产物（只可像 D3 一样作构建期 oracle 且不入库）。
3. 全部为是 → 登记 `data/sources.toml` 新条目（含许可原文/SHA）、写 `docs/数据来源与许可.md`、跳路线 B 的 4–5 步。

## 路线 B：自建（默认路线，工具 1 天 + 核验 2–3 天）

1. **导出待办清单**（脚本，可照抄）：

   ```sh
   python3 - <<'PY' > /tmp/root86-todo.tsv
   # 列：字 全码 现有组件 识别码 IDS 结构
   ...
   PY
   ```

   只导 GB2312 一级（`data/generated/gb2312-level1.txt`）且 `quality=partial` 的 326 字。
2. **生成候选分解**（脚本）：对每字按码位枚举"标准字根"组合——
   `data/learning/wubi86-root-inventory.tsv` 给出每个键允许的字根；码长 3 → 2 个字根 + 识别码，码长 4 → 3 或 4 个字根。
   每条候选记录：`字 / 根序 / 每根键位 ≡ 码位 / 是否与 IDS 结构一致 / 候选序号`。多解时按"与 IDS 结构一致"优先排序。
3. **人工核验**（pro，每题 30–60 秒）：从候选里选正确的一条；无合适候选 → 自己写根序（仍必须逐位对上码位）；
   确实无法确定 → 保持 `partial` 并在清单里写明原因（**不猜**）。
4. **落盘**：`data/learning/wubi86-root-order.tsv`（项目自编，CC-BY-SA-4.0）：
   `字\t根序(空格分隔)\t全码\t来源(D44 自建)\t证据(码位对齐+IDS/结构)\t核验人/日期`。
5. **接入**：`build_b0.py` 新增 `--root-order`（优先级高于 D2 的视觉拆法；仍走标准 v1 校验，
   校验失败的条目不得升 `full`），重生成运行时与台账。
6. **验收**：

   ```sh
   python3 platforms/macos/tests/test-learning-consistency.py     # 学练用一致
   python3 modules/hanzi-structure/tests/validate_b0.py ...       # 台账自洽
   make verify && make macos-offline-tests
   awk -F'\t' '!/^#/{print $3}' data/generated/B0-runtime.tsv | sort | uniq -c   # 目标 full ≥ 3,680（GB2312 一级 ≥98%）
   ```

## 记录口径

- 每个字**一条**记录，带证据与日期；同一字不允许两个来源并存（冲突时保留证据更强的一条并在清单留痕）。
- 覆盖率口径仍是 **GB2312 一级 3,755 字**（ADR-375/377），对外数字只认这个。
- 数据登记：`data/sources.toml` + `docs/数据来源与许可.md`；文件必须能被 `test-docs-hygiene.py` 与
  `validate_b0.py` 读通。

## 禁止

- 不从无许可词库/输入法（极点、极爽、小鸭、搜狗、WindInput…）抄拆字表；
- 不因为"想上 98%"而放宽标准 v1（键位/字根数/识别码必须逐条对得上）；
- 不把 `partial` 直接标成 `full`，不省略证据；
- 不为本任务引入网络依赖或遥测（核心 crate 仍零网络）。

## 参考

- `docs/standards/wubi-decomposition.md`（标准 v1，含"组件=取码字根"）
- 报告 303 §4.3（326 条成因拆分）、报告 304 §2（F1/F5/F7）
- `docs/research/wubi-schemes-and-learning-loop.md` §1（86 取码规则）
- ADR-358/359（标准字根清单与字形别名）
