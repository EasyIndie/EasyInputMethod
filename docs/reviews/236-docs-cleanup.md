# 236 — 项目文档梳理：清掉过时与重复，把"不再腐烂"做成门禁

- 日期：2026-11-06　｜　触发：用户「全面梳理项目文档，清理无用及过时文档，保持精简高效」
- 关联：`docs/README.md`、`docs/tasks/README.md`、`docs/archive/README.md`、
  `platforms/macos/tests/test-docs-hygiene.py`、`test-docs-sync.py`

## 0. 结果

| 指标 | 之前 | 之后 |
|---|---|---|
| 活文档里的**死链** | **29**（8 处指向早就不存在的 `docs/迭代计划.md`） | **0** |
| `docs/tasks/` 文件数 / 行数 | **66 / 2,970** | **4 / 约 350**（其余 62 张整卡迁入 `docs/archive/tasks/`） |
| `docs/` 顶层文档 | 21 | 20（`发布说明.md` 归档） |
| 无入链的活文档 | 40+（含 `SECURITY.md`、6 篇发布说明） | 0（发布说明以 `releases/` 目录形式登记） |
| 机器门禁 | 只有版本同步 | 版本同步 + **文档卫生**（索引/死链/任务卡/归档登记） |

## 1. 诊断（先量，再动）

用一次性脚本扫全仓 `*.md` 的相对链接与入链，得到三个真问题：

1. **`docs/迭代计划.md` 早已不存在**，却被 8 个文件引用（`tasks/README.md`、`macos-release-checklist.md`、6 张任务卡）。
2. **`docs/tasks/` 堆了 66 张卡**，其中 62 张是 2026-10 已完成的历史任务（M1/M2/M3/P2/MVP/ITER-01…29），
   真正的"活跃卡"只有 IT-22 走查三张 —— 目录本身在误导人。
3. **`docs/发布说明.md` 停在 0.1.15**，而 1.0.0–1.0.2 的说明都在 `docs/releases/`，
   并且 `releases/` 六篇从没被索引（无入链）。

## 2. 动作

| 动作 | 内容 |
|---|---|
| 归档任务卡 | 62 张 `git mv docs/tasks/* → docs/archive/tasks/`（文件名不变，历史引用照旧可查） |
| 归档过时说明 | `git mv docs/发布说明.md → docs/archive/发布说明-0.1.15.md`，并在 `docs/README.md` 用 `releases/` 取代 |
| 链接归位 | 归档卡内部链接按新层级重写（`../reviews/x` → `../../reviews/x`）；`tasks/README.md` 指向归档路径；`迭代计划.md` 的引用改指 `HANDOFF.md` |
| 新增索引 | `docs/archive/README.md`（归档登记表）、`docs/research/README.md`（两个研究议题的结论去向） |
| 重写索引 | `docs/README.md`：权威表补 `SECURITY.md`、`AGENTS.md`/`CLAUDE.md`/`HANDOFF`/`ROADMAP`，`releases/` 列出版本，新增「文档卫生规则」5 条 |
| 任务卡规则 | `docs/tasks/README.md` 顶部写死：**只放活跃卡**，完成即迁档 |

## 3. 门禁（防复发）

`platforms/macos/tests/test-docs-hygiene.py`（进离线回归，毫秒级）：

1. **活文档死链 = 0**（`docs/` 顶层 + `tasks/` + `releases/` + 根目录 `*.md`）；
2. **活文档必须被索引**（`docs/README.md` 或 `tasks/README.md` 能链到）；
3. **`docs/tasks/` 只允许清单内的活跃卡**（白名单：README + IT-22 三张）；
4. **`docs/archive/` 新增文件必须在 `archive/README.md` 登记**；
5. **`releases/` 必须在 `docs/README.md` 出现**。

配合已有的 `test-docs-sync.py`（版本 ↔ 发布稿 ↔ HANDOFF ↔ ROADMAP）形成两道防线：
前者管"哪里放了什么"，后者管"版本有没有对上"。

## 4. 边界（有意不动）

- `docs/reviews/`（236 篇）、`docs/design/`、`docs/experiments/`、`docs/history/`、`docs/research/`：
  **证据与过程产物，保持原样**，允许内部链接失效（冻结内容改了就失去追溯价值），但：
  - `archive/` 必须登记；`design/`、`research/` 各自有 README 索引；
  - 新增活文档必须被 `docs/README.md` 索引。
- 没有删除任何文件：全部是 `git mv`，历史与报告里的引用仍然有效。
- `docs/决策记录.md`（2,856 行 / 307 条 ADR）保持单文件：它是按编号递增的冻结历史，
  拆分只会让引用变脆；检索靠编号。
