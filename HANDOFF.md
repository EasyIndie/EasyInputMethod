# HANDOFF — 会话交接文档

> **本文件记录"当前状态"，供任意 AI 工具在任意新会话中快速接手，防止背景信息丢失。**
> **每次会话结束时必须更新本文件**（规则见 `AGENTS.md` §6.1；操作见 Skill `update-handoff`）。
>
> 稳定背景（设计、决策、数据合规）在 `docs/`；**本文件只回答三件事：此刻在哪 / 下一步做什么 / 有什么坑。**

---

## 0. 元信息

| 项 | 值 |
|---|---|
| 最后更新 | 2026-10-08 |
| 更新者 | pi |
| 当前阶段 | **P1-M1 进行中（T-M1-06b 完成：jieba 词表 + 真实词频权重）** |
| 当前分支 | `main`（本次 T-M1-06b 变更未提交） |
| 活跃 PR | 无 |
| 最近一次 `make verify` | ✅ 全绿（fmt+clippy+38 测试+1 doctest+deny+隐私断言） |

## 1. 三十秒摘要

- **萤火虫**：跨平台、开源可审计、默认离线、只做核心输入的中文输入法（五笔优先，**默认混输**）。
- **技术**：Rust 引擎 + 窄 C ABI + 平台薄宿主；**GPL-3.0-or-later**。
- **现在**：**P1-M1 进行中**。**T-M1-06b 完成**：改用 `fxsjy/jieba` `dict.txt`（D10，MIT，349,045 词**带词频**）重生成词组码表并统一赋权。`wubi86-single.tsv` 的 `weight` 改为 jieba **真实词频**（缺者默认 1）；`wubi86-phrases.tsv` 改为多候选 `code\t词组\tweight`（**337,231 条 / 155,726 码**，5.8 MB），按词频降序（ADR-021）。同卡交付 T-M1-07（ADR-013）。
- **下一步**：`ROADMAP.md` 的 **P1-M1 / T-M1-08**（数据登记收尾）→ **T-M1-09**（正式码表接入 `ime-table`/`ime-cli`）。
- ⛔ 继续遵循铁律：核心不联网、`forbid(unsafe_code)`、数据登记许可。

## 2. 已完成

- 竞品调研、架构选型；**码表自建可行性已验证**（词组码 99.90% 可由单字码推导）。
- 权威方案 `docs/技术方案.md` + 配套文档；交叉审核（`docs/reviews/001.md`）已确认并落地行动项。
- **P1-M0**：Rust workspace、`ime-core`（Engine/InputMode/会话状态机）、`ime-table`（码表引擎）、`ime-cli`（REPL）。
- **P1-M1 / T-M1-01**：新建 `crates/wubi-encoder`（零外部依赖、`forbid(unsafe_code)`）：`RadicalTable::from_tsv` + `radical_to_key`，`Stroke`/`Structure`/`EncodeError`；6 个单测。
- **P1-M1 / T-M1-02**：`RadicalTable::key_name_char`/`is_radical_char` + `encode_key_name`/`stroke_to_key`/`encode_chengzi`（键名字、成字字根）；新增 `TooFewStrokes` 错误；7 个单测。
- **P1-M1 / T-M1-04**：`data/sources.toml` + `data/sources/fetch-wubi-chaizi.sh`（D2 `aardio/wubi-lex`、D3 `huanfeng/WindInput`，均 MIT，SHA-256 固定）；`wubi-encoder/examples/crosscheck.rs` 产出 `data/generated/chaizi-diff.txt`。
- **P1-M1 / T-M1-03**：`wubi-encoder` 新增 `recognition_key` + `encode_hechengzi`（合体字 + 末笔字型识别码）+ `TooFewRadicals`；`examples/oracle.rs` 与 D3 全量对照（全体 99.9784%、GB2312 一级 100%）；结构/末笔采用 option 2 派生（ADR-017）。
- 实现阶段发现 `yada` 不支持预测搜索 → 改定 `cedarwood`（ADR-015）。
- **P1-M1 / T-M1-05a / 05b（调研止步）**：逐一核实结构/末笔独立来源许可，结论**暂无合格来源**（ADR-018）；T-M1-05b 尝试自建（Wiktionary dump 1.8 GB）失败 → **ADR-019** 改以「多 oracle 交叉验证」替代「数据独立」，结构/末笔沿用 ADR-017 的 PROVISIONAL 派生数据。
- **P1-M1 / T-M1-04b**：新增 `data/sources/fetch-wubi-oracle2.sh`（`rime/rime-wubi` `wubi86.dict.yaml`，**LGPL-3**，SHA-256 固定）；登记 **D9**（`role=validation-oracle` / `ship=false` / 风险中）；`wubi-encoder/examples/oracle2.rs` → `data/generated/wubi86-oracle2-single.tsv`（70,370 字；抽样 5 字正确；与 D3 全体 98.78%、GB2312 一级 100%）。
- **P1-M1 / T-M1-05**：新增 `wubi-encoder/examples/generate.rs`（生成 + 双 oracle 回归，一条命令可复现）→ `data/generated/wubi86-single.tsv`（27,823 字，471 KB，CC-BY-SA-4.0）与 `wubi86-regression.txt`；发布路径用编码器对 D3 拆字逐字生成（ADR-020），vs D3 99.9784%/GB1 100%、vs rime 98.77%/GB1 100%，三方不一致 0 条；D2 交叉检查 GB1 91.66%（量化其字形记法歧义）。修正 `encode_chengzi`（1/2/≥3 笔成字字根标准）。
- **P1-M1 / T-M1-06**：`wubi-encoder` 新增 `encode_phrase`（2 字 `AaAbBaBb` / 3 字 `AaBaCaCb` / 4+ 字 `AaBaCaZa`）+ `TooFewCharacters`/`TooFewCodes`；6 个单测（含写死样本 中华人民共和国→kwwl、输入法→ltif、中文→khyy）+ doctest。新增 `examples/generate_phrases.rs`：读 D4 词表 + `wubi86-single.tsv`，同码按临时权重（组成字临时权重之和）去重 → `data/generated/wubi86-phrases.tsv`（38,220 条，576 KB）。新增 `data/sources/fetch-phrase-pinyin.sh`（D4 MIT，SHA-256 固定）并登记。
- **P1-M1 / T-M1-06b**（同时交付 T-M1-07）：新增 `data/sources/fetch-jieba-dict.sh` + 登记 **D10**（`fxsjy/jieba` `dict.txt`，MIT，349,046 行）；`generate.rs` 单字 `weight` 改 jieba 真实词频（缺者 1）；`generate_phrases.rs` 改从 jieba 生成、过滤纯汉字/长度 2–10、输出多候选 `wubi86-phrases.tsv`（337,231 条 / 155,726 码）+ `wubi86-phrases-report.txt`；必需样本 8 词齐全（生成器断言 中华人民共和国→kwwl）。新增 **ADR-021**（多候选 + jieba 词频）。验证：`make verify` 全绿。

## 3. 进行中

**P1-M1**（自建码表流水线）：T-M1-01/02/03/04/04b/05/06/06b（含 T-M1-07）已交付；下一步 **T-M1-08（数据登记收尾）**。

## 4. 下一步（优先级排序）

1. **P1-M1 / T-M1-08**：数据登记收尾（`docs/数据来源与许可.md` + `sources.toml` 全量 CI 校验）。
2. **P1-M1 / T-M1-09**：正式码表接入 `ime-table`/`ime-cli`（`.imedict` 编译；内置核心选 ~10k 高频词组，见 `技术方案.md` §7.2）。
3. 定 `TBD-4`：英文/包名（`yinghuo` vs `lampyris`）。

## 5. 待决 / 阻塞

| 编号 | 问题 | 是否阻塞 |
|---|---|---|
| REV-1…4 | 交叉审核已**完成**（`docs/reviews/001.md`），结论有条件通过 | 否 |
| TBD-1 | 词频数据源 — ✅ 已定：`fxsjy/jieba` `dict.txt`（D10，MIT）；见 ADR-021、T-M1-06b | 否 |
| TBD-2 | 五笔98 / 新世纪 / 郑码数据源 | 否 |
| TBD-3 | 用户词库存储格式 | 阻塞 P1-M4 |
| TBD-4 | 英文/包名 | 否 |
| TBD-5 | 结构/末笔独立数据源（GPL-3 兼容）——T-M1-05a/05b 结论：暂无；ADR-019 以多 oracle 交叉验证替代；T-M1-05 实际以 D3 拆字为字根来源（ADR-020） | 否 |

## 6. 必须知道的坑与硬约束（详见 `AGENTS.md` 铁律）

- 核心 crate **不联网**、`#![forbid(unsafe_code)]`；`unsafe` 只在 `ime-ffi`。
- 配置只能走 `ime-config`；**禁止**写 `UserDefaults` / 注册表 / 第二个配置文件。
- 任何数据必须**登记许可**（`docs/数据来源与许可.md` + `data/sources.toml`）。
- ⚠️ `rime-wubi86-jidian` 的**码表 provenance 存疑**（源自闭源"极点五笔"），**只可作过渡/测试**，不得作为正式发布的不可替代来源。
- **不复用 weasel / squirrel 代码**（GPL，只读不抄）。
- 提交前必须 `make verify` 全绿。

## 7. 环境快照

| 项 | 值 |
|---|---|
| 平台 | macOS |
| Rust | 1.98.1（由 `rust-toolchain.toml` 固定） |
| 构建 | `make` 可用；`just` 不可用（故用 Makefile） |
| 依赖工具 | `cargo-deny`、`cargo-fuzz` 已安装 |
| 硬件 | **2 物理核 / 4 逻辑核，16 GB 内存，14 GiB 可用磁盘** |
| 编译成本 | 全量冷编译 ≈ 4 秒，`target/` ≈ 22 MB（当前零依赖；加依赖后会涨） |
| 代码 | ✅ Rust workspace 就绪（`ime-core`/`ime-table`/`ime-cli`/`wubi-encoder`），38 个测试 + 1 doctest 通过 |

## 8. 接手清单（新会话开始时）

- [ ] 读 `AGENTS.md`（铁律 / 工作流 / 约定）
- [ ] 读本文件
- [ ] 看 `ROADMAP.md` 当前进度
- [ ] 读与本次任务相关的 `docs/` 文档
- [ ] 若要写代码：先跑 `make verify` 确认基线
- [ ] 有歧义 → **先问，不要猜**

## 9. 会话日志（倒序，保留最近 10 条；更早见 git 历史）

### 2026-10-08 · pi（T-M1-06b jieba 词表 + 词频，含 T-M1-07）
- 新增 `data/sources/fetch-jieba-dict.sh` + 登记 **D10**（`fxsjy/jieba` `dict.txt`，MIT，349,046 行）；单字 `weight` 改 jieba 真实词频（缺者 1）；词组表改输出 `code\t词组\tweight`（337,231 条 / 155,726 码，5.8 MB）。
- 关键决策 **ADR-021**：卡步骤 3「同码保留权重最高者」会挤掉验收样本 `输入法`（ltif 19 < 加德满都 66）→ 改为与 `技术方案.md` §6.2 一致的多候选（按词频降序）。
- 生成器断言必需样本 8 词齐全（世界 anlw / 人民 wwna / 中文 khyy / 输入法 ltif / 计算机 ytsm / 经济学 xiip / 图书馆 lnqn / 中华人民共和国 kwwl）。
- 验证：`make verify` 全绿（fmt+clippy+38 测试+1 doctest+deny+隐私断言）。
- 遗留：词组表 5.8 MB；T-M1-09 编译内置码表时按词频挑 ~10k（`技术方案.md` §7.2）。

### 2026-10-08 · pi（T-M1-06 词组码自动生成）
- `wubi-encoder` 新增 `encode_phrase`（2 字 `AaAbBaBb`、3 字 `AaBaCaCb`、4+ 字 `AaBaCaZa`）+ `TooFewCharacters`/`TooFewCodes` 错误；6 个单测（写死样本 中华人民共和国→kwwl、输入法→ltif、中文→khyy）+ doctest。
- 新增 `wubi-encoder/examples/generate_phrases.rs`：读 D4 词表（`词: 拼音`，仅取中文词）+ T-M1-05 单字码表，按规则生成；同码按临时权重（组成字临时权重之和）去重 → `data/generated/wubi86-phrases.tsv`（38,220 条，576 KB，CC-BY-SA-4.0；47,111 条生成，同码丢弃 8,891，跳过非汉字/缺字 0）。
- 新增 `data/sources/fetch-phrase-pinyin.sh`（D4 `mozillazg/phrase-pinyin-data` `pinyin.txt` v0.19.0，MIT，SHA-256 固定）；登记 `data/sources.toml` + `docs/数据来源与许可.md` §1/§1.6；源文件不入库。
- 验证：`make verify` 全绿（fmt + clippy -D warnings + 38 测试 + 1 doctest + deny + 隐私断言）。
- 未决：同码去重采用临时权重，待 T-M1-07 真实词频替换后重跑。

### 2026-10-08 · pi（T-M1-05 单字码表生成 + 双 oracle 回归）
- 新增 `wubi-encoder/examples/generate.rs`：发布路径用编码器对 D3 第 2 列（干净拆字）逐字生成全码，输出 `data/generated/wubi86-single.tsv`（27,823 字，471 KB，CC-BY-SA-4.0）+ `wubi86-regression.txt`；D2 降级为交叉检查（GB1 91.66%，量化字形记法歧义）。
- 双 oracle 回归（ADR-019）：vs D3 全体 99.9784%/GB1 100%；vs rime 全体 98.77%/GB1 100%；三方两两不一致 0 条（无需人工裁定）。
- 修正 `encode_chengzi`：1 笔=键+首笔+LL、2 笔=键+首笔+次笔、≥3 笔=键+首笔+次笔+末笔（原实现把 2 笔成字字根错编为 4 键）；新增/更新单测，wubi-encoder 现 21 测试。
- 写 **ADR-020**（字根来源改 D3 拆字 + 成字字根规则补全）+ `docs/数据来源与许可.md` §1.5 + T-M1-05 结论。
- 验证：`make verify` 全绿（fmt + clippy -D warnings + 32 测试 + deny + 隐私断言）。
- 遗留：D1 码表由 D3 拆字生成（ADR-020），将来若获得许可明确的独立拆字/结构数据可替换；`.imedict` 编译留待 T-M1-09。

### 2026-10-08 · pi（T-M1-04b oracle #2：rime-wubi）
- 新增 `data/sources/fetch-wubi-oracle2.sh`（`rime/rime-wubi` `wubi86.dict.yaml`，LGPL-3，SHA-256 固定）；登记 **D9**（`role=validation-oracle`、`ship=false`、风险中）+ `docs/数据来源与许可.md` §1.4。
- 新增 `wubi-encoder/examples/oracle2.rs`：Rime 字典 → `data/generated/wubi86-oracle2-single.tsv`（仅单字、同字取最长码、丢弃 z 码；70,370 字）；抽样 5 字全部正确；与 D3 全体 98.78%、GB2312 一级 100%（粗报，正式对照在 T-M1-05）。
- oracle 数据不入库、不打包（ADR-016/019）。验证：`make verify` 全绿（30 测试）。

### 2026-10-08 · pi（T-M1-05a 结构/末笔独立数据源调研）
- 逐一核实候选来源许可：**结论无合格来源**（KanjiVG CC BY-SA 3.0 仅 63.8% GB1 覆盖；Arphic Public License 被 FSF 判 GPL 不兼容；CHISE/cjkvi-ids 许可不明确）。
- 按卡规「停下并写结论」交付：写 **ADR-018** + `docs/数据来源与许可.md` §1.3（候选许可判定表）+ 任务卡结论；未引入任何数据、未退回 D3。
- 阻塞：T-M1-05（单字码表生成）待找到合格来源；候选路径见 ADR-018。验证：`make verify` 全绿（纯文档变更）。

### 2026-10-08 · pi（T-M1-03 合体字 + 末笔字型识别码）
- `crates/wubi-encoder` 新增 `recognition_key`（5×3 识别码双射）与 `encode_hechengzi`（≥4 取 1/2/3/末；3/2 字根 + 识别码）+ `TooFewRadicals`；19 个单测（含规范样例 中/和/对/地/要/会）。
- 新增 `examples/oracle.rs`：从 D3 逐位推导字形→键映射，全量对照 → `data/generated/oracle-report.txt`（全体 99.9784%、GB2312 一级 100%、三码字 100%；仅 6 处歧义字形归因）+ PROVISIONAL 派生 `wubi86-structure-laststroke.tsv`。
- 调研结论：结构/末笔采用 option 2（从 D3 派生），写 **ADR-017**；新增 `data/generated/gb2312-level1.txt`（GB2312 一级 3755 字）。
- 验证：`make verify` 全绿（30 测试）。
- 遗留：可靠拆字数据（字根数/结构/末笔）待引入（T-M1-05 前置，需联网阶段登记新数据源）。

### 2026-10-08 · pi（ADR-016：码表来源决策）
- T-M1-04 发现：WindInput 的 `wubi86_chaizi.txt`（MIT）含 **27,823 字已验证五笔86 码**。
- **决定（长期正确性）**：发布码表**只能由自建编码器生成**；第三方码表**仅作验证 oracle，不发布** → 新写 **ADR-016**。
- 影响：T-M1-03（合体字+识别码）**保留且是核心**（现在可与 oracle 全量对照）；T-M1-05 改为“自建码表 + oracle 回归”。
- 纠正认知：D2/D3 字根表示体系不同，T-M1-04 的拆字 diff **不能用于裁定**；有效对照是“自建码 vs D3 码”。

### 2026-10-08 · pi（T-M1-04 拆字数据交叉校验）
- 新增 `data/sources/fetch-wubi-chaizi.sh`（下载 D2 aardio/wubi-lex 86.txt、D3 WindInput wubi86_chaizi.txt；SHA-256 固定并校验；源文件不入库）+ `data/sources.toml`（D2/D3 登记）；`docs/数据来源与许可.md` §1.1 补 SHA-256 与脚本路径。
- 新增 `crates/wubi-encoder/examples/crosscheck.rs`：产出 `data/generated/chaizi-diff.txt`（交集 6862、仅 D3 独有 20961、分歧 6861；D2 可见字根 vs D3 PUA，差异大属预期）。
- 验证：`make verify` 全绿（24 测试）；未裁定分歧（留 T-M1-05，pro）。

### 2026-10-08 · pi（T-M1-02 键名字+成字字根）
- `crates/wubi-encoder`：新增 `key_name_char`（25 键名固定映射）、`is_radical_char`、`encode_key_name`（键连打四次）、`stroke_to_key`（横G竖H撇T捺Y折N）、`encode_chengzi`（键+首次末笔）；新增 `TooFewStrokes` 错误（笔画<2 报错）。
- 未改动其它 crate；未实现合体字/识别码（留 T-M1-03）。
- 验证：`cargo test -p wubi-encoder` 13 通过；`make verify` 全绿（24 测试）。

### 2026-10-08 · pi（派发防护 + T-M1-01 质检）
- T-M1-01 已由 flash worker 完成并**人工复核**：质量优秀，`make verify` 全绿（17 测试）。已提交。
- 派发工具加防护：`--jobs N`（`CARGO_BUILD_JOBS`）+ 磁盘预检（默认 ≥3 GiB，`--min-free-gb N`）。
- 硬件实测：可用磁盘 14 GiB（每 worktree ≈22 MB，宽裕）；但仅 **2 物理核** → **并行上限建议 2，当前默认顺序派发**。

### 2026-10-08 · pi（T-M1-01 字根表骨架）
- 新建 `crates/wubi-encoder`（零外部依赖、`forbid(unsafe_code)`）：`RadicalTable::from_tsv`/`radical_to_key` + `Stroke`/`Structure`/`EncodeError`。
- 仅字根→键查询，**不含编码逻辑**（留给 T-M1-02/03）；未改动 `ime-core`/`ime-table`/`ime-cli`。
- 验证：`cargo test -p wubi-encoder` 6 通过；`make verify` 全绿（17 测试、clippy、deny、隐私断言）。
- 卡外无改动；`ime-cli` 冒烟行为不变。

### 2026-10-08 · pi（重复实验定论）
- 新增可重复 A/B：`bench-session-vs-workers.sh --workload --repeat`、`usage-compare.sh`（中位数）、`docs/experiments/workloads/`。
- **N=5 中位数结论**：独立负载 fresh 37.9k vs reuse 43.6k（+15%，分布重叠）；
  强依赖负载 fresh 230.9k vs reuse 51.9k（**reuse 快 4.4×**，分布不重叠）。
- **开发约定**：默认每卡新 worker（任务卡保持自包含）；仅“必须接着上卡上下文”的序列用 `--reuse`。
- 详见 `docs/experiments/session-vs-workers.md`。

### 2026-10-08 · pi（会话 vs worker 实测）
- 跑通完整 A/B（模型 `deepseek-v4-flash`，负载 = T-M1-01 + T-M1-02），两臂均成功且产出等价。
- **结论（反直觉）**：对独立任务，**每卡新 worker 更省**（A 521k vs B 918k tokens，+76%）；
  B 的 cacheHitRate 更高（96.8%）但上下文滚雪球（任务二 cacheRead 3.4×）。
- 微基准：固定开销 ≈ 4.3k tokens/次；前缀缓存跨会话共享 → 开新会话 ≠ 冷启动。
- 默认派发改定：**一张卡 = 一个新 worker**；`--reuse` 仅用于强依赖序列。详见 `docs/experiments/session-vs-workers.md`。
- 注意：provider 未配计价，`cost`=0；用 token 口径。n=1，方差大。
