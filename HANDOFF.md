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
| 当前阶段 | **P1-M3 进行中：T-M3-01（ime-ffi C ABI）完成** |
| 当前分支 | `main`（T-M3-01 变更未提交） |
| 活跃 PR | 无 |
| 最近一次 `make verify` | ✅ 全绿（fmt+clippy+78 单测+1 doctest+deny+隐私断言；C/Swift 冒烟通过） |

## 1. 三十秒摘要

- **萤火虫**：跨平台、开源可审计、默认离线、只做核心输入的中文输入法（五笔优先，**默认混输**）。
- **技术**：Rust 引擎 + 窄 C ABI + 平台薄宿主；**GPL-3.0-or-later**。
- **现在**：**P1-M1、P1-M2 全部完成；P1-M3 开始，T-M3-01（`ime-ffi` C ABI）已完成**。T-M2-01 完成 `ime-config`（Schema/快照/原子写/监听/广播）；**T-M2-02 完成 `ime-pinyin`**（`PinyinBackend` trait + 内置轻量兜底 + 混输）；**T-M2-03 完成拼音反查首选读音 + `ime-config` 接入 `ime-cli`**（改 `config.toml` 即时生效 + `:set` 调试命令）；**T-M2-04 `inputx-pinyin` spike 完成，结论「不接入」**（体积否决：core 4.2 MiB / 默认 ~23 MiB，超 0.6 MB 预算）。
- **下一步**：P1-M3 Swift + InputMethodKit 宿主（`IMKInputController`，含把真实数据文件接给 FFI 会话）；`TBD-4`（英文/包名）；拼音反查 CLI 展示（可选）。
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
- **P1-M1 / T-M1-09**：`ime-table` 新增 `Table::from_tsv`（`code\ttext\tweight`：注释/空行跳过、缺列/非法权重报错、同码多候选按词频降序）；`ime-cli` 支持 `--table`/`IME_TABLE_PATH` 加载并保留内置回退表；新增 `examples/generate_core.rs` 裁剪出 `data/generated/wubi86-core.tsv`（单字全量 27,823 + 词组按 jieba 词频全局取前 10,000，共 491,854 字节 ≤0.6MB）+ 报告；验收样本 `wq→你`、`kwwl→中华人民共和国`、`gggg` 重码按词频降序通过。
- **P1-M2 / T-M2-01**：新建 `crates/ime-config`（`arc-swap` + `toml_edit`，零网络、`forbid(unsafe_code)`）：`schema.rs`（v1 七项唯一真值）、`config.rs`（Schema 默认值 + 文件值合并快照）、`persist.rs`（原子写 temp+fsync+rename / 咨询锁 / 迁移占位 / 首份中文注释模板）、`watch.rs`（mtime 轮询 + 防抖 → reload）、`lib.rs`（`ConfigStore` set/get/subscribe/reload）；9 个单测覆盖验收 1–6（含 watcher 外部编辑重载）。
- **P1-M2 / T-M2-02**：新建 `crates/ime-pinyin`（零外部依赖、`forbid(unsafe_code)`）：`PinyinBackend` trait（`segment`/`convert`/`reverse_lookup`）、`TablePinyinBackend`（内存表兜底：音节切分最长优先+回溯、全拼整词/单音节字、简拼首字母串）、`PinyinEngine`（适配 `Engine`，`source=Pinyin`，绝不自动上屏）；12 个单测。生成 `data/generated/pinyin-chars.tsv`（53,087 行，575 KB，已入库）与 `pinyin-words.tsv`（340,960 行，8.4 MB，gitignore）；D5 由候选转正式（fetch 脚本 + SHA-256 + 登记）。`ime-cli` 支持 `--pinyin-chars`/`--pinyin-words` + 内置回退拼音表，`:mode pinyin`/`mixed` 验收通过（`nihao→你好`、`wo→我`、`nh→你好`、mixed 无五笔结果出拼音候选）。
- **P1-M2 / T-M2-04**：完成 `inputx-pinyin` spike（只调研不改产品代码）：结论 **Phase 1 不接入**，保留内置兜底，`inputx-pinyin` 降为 P2「观察」候选，终局仍自研 FSA。依据：① 体积（core `pinyin.dict` 4.2 MiB、默认含 bigram/trigram ≈ 22.8 MiB；实测 release 二进制默认 24.2 MB / 仅 core 4.77 MB）远超 0.6 MB 预算；② 20 常用词 hit@1 与内置兜底持平（各 19/20）；③ 单作者、crates.io 1.4.0 滞后、facade 不含简拼/权重（`inputx-core` 未发布）；许可干净。产出 `docs/reviews/002-inputx-pinyin-spike.md` + ADR-008 spike 复核 + T-M2-04 结论。
- **P1-M3 / T-M3-01**：新建 `crates/ime-ffi`（`cdylib`+`staticlib`，`deny(unsafe_op_in_unsafe_fn)`，唯一 unsafe 集中地）：会话 ABI（`new/free/key/candidates/select/page/commit/focus_out/reset` + `ime_string_free`，不透明 `ImeSession`）+ 配置 ABI（`snapshot/get/schema/set/reload/subscribe/unsubscribe`，进程级单例 `ConfigStore`）；所有入口 `catch_unwind` 兜底、坏输入返回错误码。`ime-config` 新增 `ConfigStore::with_defaults`（加载失败降级内存默认值）；`include/ime.h` + `module.modulemap`；C 冒烟（clang 链 staticlib 运行）+ Swift `import ime` typecheck 均通过。

## 3. 进行中

**P1-M3**：T-M3-01（`ime-ffi` C ABI）已完成；下一步 Swift + InputMethodKit 宿主（`IMKInputController`），尚未开始。

## 4. 下一步（优先级排序）

1. **P1-M3**：Swift + InputMethodKit 宿主（`IMKInputController`）；把真实数据文件（`wubi86-core.tsv` / `pinyin-chars.tsv` / `pinyin-words.tsv`）接给 FFI 会话（当前 FFI 用内置样本引擎）。
2. **P1-M4**：候选窗翻页（`ime_session_page` 当前为 no-op，依赖候选窗/跨页状态）。
3. **可选**：拼音反查 CLI 展示命令（`:pinyin <字>`，后端 `reverse_lookup` 已就绪；无任务卡）。
4. 定 `TBD-4`：英文/包名（REV-4）。
5. **P2**（参考，不阻塞）：自研 FSA 拼音引擎（ADR-008 终局）；修复内置兜底贪心切分漏检超长整句（T-M2-04 附带发现）。

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
| macOS/宿主 | macOS 13.7.8 **Intel x86_64**；**仅 CLT、无 Xcode**；Swift 5.8.1 + InputMethodKit 可编译/链接（已实测）；**不能用 IB/AssetCatalog**（actool/ibtool 为 stub）→ 纯代码 UI；ad-hoc 签名可用 |
| 代码 | ✅ Rust workspace 就绪（`ime-core`/`ime-table`/`ime-cli`/`wubi-encoder`/`ime-config`/`ime-pinyin`），69 单测 + 1 doctest 通过 |

## 8. 接手清单（新会话开始时）

- [ ] 读 `AGENTS.md`（铁律 / 工作流 / 约定）
- [ ] 读本文件
- [ ] 看 `ROADMAP.md` 当前进度
- [ ] 读与本次任务相关的 `docs/` 文档
- [ ] 若要写代码：先跑 `make verify` 确认基线
- [ ] 有歧义 → **先问，不要猜**

## 9. 会话日志（倒序，保留最近 10 条；更早见 git 历史）

### 2026-10-08 · pi（T-M3-01 ime-ffi C ABI）
- 新建 `crates/ime-ffi`（`cdylib`+`staticlib`，`deny(unsafe_op_in_unsafe_fn)`，唯一 unsafe 集中地）：会话 ABI（`new/free/key/candidates/select/page/commit/focus_out/reset` + `ime_string_free`，不透明 `ImeSession`）+ 配置 ABI（`snapshot/get/schema/set/reload/subscribe/unsubscribe`，进程级单例 `ConfigStore`）；所有入口 `catch_unwind` 兜底、坏输入（NULL/非法 UTF-8/非法码点/越界）返回错误码。
- `ime-config` 新增 `ConfigStore::with_defaults`（首次加载失败降级内存默认值，保留真实路径）；`include/ime.h` + `module.modulemap`；C 冒烟（clang 链 staticlib 运行）+ Swift `import ime` typecheck 均通过。
- 验证：`make verify` 全绿（78 单测 + 1 doctest；deny advisories/bans/licenses/sources ok；隐私断言 135 产物零网络符号）；`run-c-smoke.sh` 输出 candidates[你|wq]→commit 你、config mode=mixed、schema 7 项。
- 遗留：FFI 会话暂用内置样本引擎（真实数据文件路径留 P1-M3 Swift 宿主）；`ime_session_page` 为 no-op（翻页状态属 P1-M4 候选窗，ime-core 固定 ≤9 候选）；配置路径暂为 `IME_CONFIG_PATH`/`config.toml`（平台路径留宿主）。

### 2026-10-08 · pi（T-M2-04 inputx-pinyin spike）
- 仅调研不改产品代码：`inputx-pinyin` 1.4.0（MIT OR Apache-2.0，纯 Rust，单作者）→ **结论「Phase 1 不接入」**，保留内置兜底；P2「观察」候选，终局仍自研 FSA（ADR-008 复核）。
- 决定性依据（实测）：核心数据 4.2 MiB、默认含 bigram/trigram ≈ 22.8 MiB，release 二进制默认 24.2 MB / 仅 core 4.77 MB，远超 0.6 MB 预算；20 常用词 hit@1 与内置兜底持平（各 19/20）；facade 不含简拼/权重（`inputx-core` 未发布），需自写适配层。
- 附带发现（留待 P2）：内置兜底贪心最长优先切分把 `mingong` 切成 `ming+o+ng`，超长整句词条漏检。
- 产出：`docs/reviews/002-inputx-pinyin-spike.md` + ADR-008 spike 复核 + T-M2-04 结论；`make verify` 全绿（纯文档变更，69 单测+1 doctest）。
- 遗留：无新增接入卡（未推荐接入）；P1-M2 全部完成，下一步 P1-M3。

### 2026-10-08 · pi（T-M2-03 拼音反查首选读音 + ime-config 接入 ime-cli）
- `ime-pinyin` 反查改首选读音：`generate.rs` 字表改为「按字分组、D5 首条读音在前」，`reverse_lookup` 据此返回首选（你→ni、的→de、行→xing）；重生成 `pinyin-chars.tsv`（53,087 行，计数不变）；新增反查首选单测。
- `ime-cli` 接入 `ime-config`：`--config`/`-c`/`IME_CONFIG_PATH` 指定路径（默认 `config.toml`，平台路径留 P1-M3）；`mode` 决定初始模式、`candidate.count` 决定每页候选数；`subscribe`+`FileWatcher`（300ms 轮询/150ms 防抖）使外部编辑即时生效（打印 `[config] <key> 已变更`）；新增 `:set <key> <value>` 调试命令走唯一写路径 `ime_config::set`。
- 新增 ime-cli 2 个单测（mode/candidate.count 读取）。验证：`make verify` 全绿（69 单测 + 1 doctest；advisories/bans/licenses/sources ok；隐私断言通过）；手工冒烟：启动 mode=pinyin、`:set candidate.count 5`、`:set mode wubi`、非法值报错、外部改 mode/count 即时生效均通过。
- 遗留：`inputx-pinyin` spike（T-M2-04，flash）未做；`reverse_lookup` 尚无 CLI/UI 命令（仅后端）；配置 C ABI 属 P1-M3。

### 2026-10-08 · pi（T-M2-02 内置轻量拼音引擎 ime-pinyin）
- 新建 `crates/ime-pinyin`（零外部依赖、`forbid(unsafe_code)`）：`PinyinBackend` trait（签名理由见 backend.rs 注释）+ `TablePinyinBackend`（音节切分最长优先+回溯 / 全拼整词+单音节字 / 简拼首字母串）+ `PinyinEngine`（`source=Pinyin`，永不自动上屏）。
- 生成 `data/generated/pinyin-chars.tsv`（53,087 行，575 KB，入库）与 `pinyin-words.tsv`（340,960 行，8.4 MB，gitignore）；词表主源 jieba、拼音由 D5 逐字拼接、D4 覆盖多音字词；**D5 转正式**（fetch 脚本 + SHA-256 + `sources.toml`/文档登记）。
- `ime-cli` 接入 `--pinyin-chars`/`--pinyin-words` + 内置回退表；验收 `nihao→你好`、`wo→我`、`nh→你好`、mixed 无五笔结果自动出拼音候选均通过。
- 验证：`make verify` 全绿（64 单测 + 1 doctest）；`deny` 有既有 license-allowance 警告但 advisories/bans/licenses/sources 均 ok。
- 遗留：`reverse_lookup` 单字返回字典序最小读音（非严格首选读音），精化属拼音反查卡；拼音词表 8.4 MB 未裁剪（内置二进制裁剪留后续卡）；`inputx-pinyin` spike（T-M2-03）未做。

### 2026-10-08 · pi（T-M2-01 ime-config 配置子系统）
- 新建 `crates/ime-config`：Schema 唯一真值（v1 七项）+ `ArcSwap` 快照 + 原子写（temp+fsync+rename）/咨询锁/迁移占位 + mtime 轮询监听（防抖→reload）+ `set/get/subscribe/reload`。
- `set` 唯一写入路径（校验→原子写→发布→广播）；语法错误保留上一份快照并报行号；未知键忽略且不删除；首份文件按 Schema 生成中文注释。
- 依赖 `arc-swap`/`toml_edit`（均许可兼容）；9 个单测覆盖验收 1–6。验证：`make verify` 全绿（52 单测 + 1 doctest）。
- 遗留：C ABI 属 ime-ffi（P1-M3）未做；文件锁为 create_new 咨询锁（唯一写者=IME 进程）；`ime-config` 尚未接入 `ime-cli`。

### 2026-10-08 · pi（T-M1-09 正式码表接入 ime-table/ime-cli）
- `ime-table` 新增 `Table::from_tsv`（`code\ttext\tweight`）：注释/空行跳过、缺列/非法权重报错（`TsvError`）；同码多候选保留并按词频降序；`convert` 前缀候选改为收集后按权重降序截断（修复 `wq→你` 被字典序截断的问题）。
- `ime-cli` 支持 `--table`/`-t`/`IME_TABLE_PATH` 从数据文件加载，未提供时用内置最小回退表；解析/读取失败退出非零。
- 新增 `wubi-encoder/examples/generate_core.rs`：单字全量 + 词组按 jieba 词频全局取前 10,000 → `data/generated/wubi86-core.tsv`（37,823 行 / 30,379 码 / **491,854 字节 ≤0.6MB**）+ `wubi86-core-report.txt`（记录裁剪规则与实测体积）；`输入法`(ltif, weight 19) 因词频过低归入可选包 1，报告已注明。
- 验收：`wq→你`、`kwwl→中华人民共和国`、`gggg`（王→龶 按词频降序）均通过；`make verify` 全绿（43 单测 + 1 doctest）。

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
