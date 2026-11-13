# 266 · ADR-337 候选 `2610d1f` 装机复验：Shift 标点与五笔码提示

- 日期：2026-11-13 / Claude Code（air 本机，已授权辅助功能）
- 范围：用户实机反馈的两处缺陷（`12:30` → `12；30`；拼音上屏后五笔码提示不出现）修复后的装机复验，外加全量真机样本与 ADR-338 新口径内存门禁
- 结论：**两处缺陷均已在真机确认修复；26/26 真机样本 PASS；内存门禁 PASS（稳态存活堆 21.0–21.2 MiB，门槛 24）**。

## 1. 候选身份

| 项 | 值 |
|---|---|
| 源码提交 | `2610d1fdde81b939f028ecf5dd8affacfff9bdb8`（`main`，Merge PR #274） |
| CI 构建 | `macOS Acceptance Package` run `43256923832`，**第 3 次尝试**成功（前两次排队 15 分钟未分到 macOS arm64 运行机被取消：「The job was not acquired by Runner of type hosted even after multiple attempts」+ GitHub 容量提示；0 步骤执行，非代码问题） |
| ZIP | `Lampyris-1.2.1-universal.zip`，SHA-256 `a4b5650914f8717cf1952c9c389a3d19107ba585c1307f0ce21bff97f8327dfb`（与随包 `.sha256` 一致） |
| 包内执行 SHA | `975a4b0420664455c1e97dc3dbfebe387bcce542f2ec43f7d739b42e8e6a8551` |
| 版本 / 构建号 | 1.2.1 / 40（仍与线上发布版同号，发版前须升号） |
| 签名 / 公证 | `codesign --verify --deep --strict` 通过；`spctl`：Notarized Developer ID（2N62934Y28） |

## 2. 装机（PASS）

切 ABC → 停宿主 → `LAMPYRIS_RESTART_HOST=1 ./scripts/install.sh --app ./Lampyris.app` → 选回萤火虫。
装后：已装执行 SHA = 包内 `975a4b04…`、`SOURCE-COMMIT` = `2610d1f`、宿主跑新二进制（无 deleted inode）；
`config.toml`（`3aea2bca…`）、用户词库（1755 行 `5e2a2db1…`）、`practice.tsv`（`2512f490…`）装前装后 SHA 相同。证据 `00-pre.txt`、`10-install.txt`、`11-post.txt`。

## 3. 两处缺陷的复验

### 3.1 Shift 标点（PASS）

TextEdit 中混输状态逐键投递：`12` `Shift+;` `30` → **`12:30`**；`Shift+/` → **`？`**；`Shift+;` → **`：`**。
修复前（`3e428b7`）同样按键得到 `12；30`。三条已固化为真机样本。

### 3.2 五笔码提示（PASS，附一条重要发现）

- 装机后第一次试，诊断日志是 `hint skip=mode=wubi`：**用户当前的输入模式是「五笔」**（`config.toml` 的 `mode` 在 2026-11-12 21:26 本地时间被改为 `wubi`，不是验收探针改的）。
  五笔模式下拼音根本不出候选，按设计也不提示；拼音模式下按设计同样不提示（ADR-331 只在混输下提示）。
- 经 `ime-config` 写路径临时切到混输再试：日志 `hint show=你好 五笔 WQVB caret={{12, 1760}, …}`、`hint show=装 五笔 UFYE …`；
  窗口列表在拼音上屏期间看到宿主的一个 148×36 小浮层（⌥P 的「英文标点」浮层是 94×36），位于外接显示器上光标处。五笔上屏（`wqvb`）与标点按设计不提示（`hint skip=not-a-pinyin-candidate`）。
- 测完已把 `mode` 恢复为 `wubi`。
- **修复前为何不显示**：旧包（`3e428b7`）在混输下拼音上屏后，诊断日志连取光标的记录都没有，说明在判定「是不是拼音候选」时就返回了；
  新包把判定数据从跨调用的 `shownCandidates` 改成上屏前快照后即正常。确切是哪一处导致旧状态为空，未进一步追溯。
- **用户侧要知道的**：五笔码提示只在「混输」模式下出现。若平时停在五笔或拼音模式，它不会出现——这是设计，不是缺陷。

## 4. 全量真机样本（26/26 PASS）

`quality-samples.sh`：原 13 条 + ADR-325…337 的 13 条全部 PASS（`30-quality.txt`）。其中本轮新增并首次在真机通过：
数字后冒号保持半角（`12:30`）、Shift 标点问号（`？`）、Shift 标点冒号（`：`）。
跑后 `config.toml` 与跑前逐字节相同；`weak-chars.tsv` 已删除；输入源为萤火虫。

## 5. 内存门禁（PASS，ADR-338 新口径）

临时切混输（与基线同条件）跑 5 轮，测完恢复五笔。系统 load 1.5–2.9，swap 用量 0.4 GB。

| 时点 | 存活堆 MiB（逐轮，判定口径） | 私有已提交 MiB（参考） |
|---|---|---|
| first-key | 5.2 / 5.1 / 5.2 / 5.1 / 5.2 | 28.6–29.7 |
| six-words（稳态） | 21.2 / 21.0 / 21.2 / 21.2 / 21.2 | 36.1–37.7 |
| idle-8s（稳态） | 21.1 / 21.0 / 21.1 / 21.1 / 21.1 | 34.3–37.5 |

门槛 24 MiB，PASS。稳态存活堆比报告 265 §4.3 的 20.1–20.2 高约 1 MiB，与期间用户词库从 1713 增至 1755 行同向；ADR-337 只改宿主取字符与提示判定，不新增常驻数据。

## 6. 仍未验证 / 发版前事项

- DMG 图形安装器完成页的上手提示（ADR-329）：DMG 只在正式发版时产出。
- 升版本号（按版本语义应为 1.3.0）；升号后是新候选，需再出包、复跑本报告 §4 / §5，并做 IT-22 A 档人工走查。
- CI 的 macOS arm64 运行机今天两次排队超时：若发版当天仍如此，可能需要给打包工作流加可选运行机参数（未改，见 HANDOFF）。

## 7. 证据

`platforms/macos/build/acceptance-air-adr337-2610d1f/`（不入库）：`00-pre.txt`、`10-install.txt`、`11-post.txt`、`20-hint-diag.txt`、
`21-hint-diag-mixed.txt`、`30-quality.txt`、`quality/`、`40-memory.txt`、`memory/`、`userdata-before/`、`artifact/`、`extracted/`。
