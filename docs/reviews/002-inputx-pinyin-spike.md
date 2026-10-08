# 调研报告 #2：`inputx-pinyin` spike（T-M2-04）

- **日期**：2026-10-08
- **范围**：评估 `inputx-pinyin`（ADR-008 的 spike 候选）是否在 Phase 1 接入，替代 `ime-pinyin` 内置轻量兜底。
- **方法**：crates.io / GitHub API 交叉核对 + 下载 `inputx-pinyin` 1.4.0 源码与发布包 + 在 `/tmp` 临时工程编译实测（质量 / 体积），**未改动本仓产品代码**。
- **结论**：**不接入（Phase 1）/ 观察（P2 参考）**；保留内置轻量兜底。依据见下。

> 本报告只作调研记录；决策以 ADR-008 的 spike 复核为准。

---

## 0. 被测对象

| 项 | 值 |
|---|---|
| crate | `inputx-pinyin` **1.4.0**（crates.io 最新稳定版，2026-05-27 发布） |
| 上游仓库 | `goliajp/inputx`（`develop` 分支，含 `inputx-pinyin-v2` 等，开发版已到 1.4.7） |
| 作者 | GOLIA K.K.（单作者；GitHub contributors 仅 1 人） |
| 许可 | 代码 **MIT OR Apache-2.0**；数据见 §1 |
| 定位 | 自研拼音引擎：分段、模糊音、FSA 词典、L0 学习、WASM-ready |

## 1. 许可（① 兼容性）

- **代码**：`MIT OR Apache-2.0`（crate 内 `LICENSE-MIT` + `LICENSE-APACHE`），与 GPL-3 兼容 ✓。
  - GitHub API 的 `license` 字段为 `NOASSERTION`（根目录同时含多份 LICENSE、SPDX 无法自动匹配），以 crate 元数据 `MIT OR Apache-2.0` 为准。
- **随产物分发的数据**（README 声明，且发布包仅含**派生** FST + 整数词频，不重分发语料原文）：

| 来源 | 许可 | 贡献 | 与 GPL-3 兼容 |
|---|---|---|---|
| Unihan Database | Unicode License v3 | 单字读音 | ✓ |
| jieba（`fxsjy/jieba`） | MIT | ~349k 词条 | ✓ |
| pypinyin（`mozillazg/python-pinyin`） | MIT | ~47k 词规范读音 | ✓ |
| Leipzig Corpora | CC-BY 4.0 | 词频权重 | ✓ |
| SUBTLEX-CH-WF | CC-BY 4.0 | 口语词频 | ✓ |

- **结论**：代码与（声称的）数据许可均与 GPL-3 兼容，许可不是否决项。

## 2. 体积（② 决定性否决项）

数据以 `include_bytes!` 编入产物（`inputx-pinyin-data-*` sibling crate）。实测原始数据与发布包：

| 数据 | 原始 | 压缩后 `.crate` |
|---|---|---|
| `inputx-pinyin-data-core`（`pinyin.dict`，必需） | 4,398,377 B ≈ **4.2 MiB** | 2.35 MiB |
| `inputx-pinyin-data-bigrams`（默认启用） | 4,462,261 + 1,486,978 B ≈ **5.7 MiB** | 3.70 MiB |
| `inputx-pinyin-data-trigrams`（默认启用） | 13,517,480 B ≈ **12.9 MiB** | 6.70 MiB |
| **默认合计** | **≈ 22.8 MiB** | **≈ 12.8 MiB** |

实测 release 二进制（macOS arm64，`strip -x`）：

| 目标 | 实测体积 |
|---|---|
| `inputx-pinyin`（默认特性，core+bigrams+trigrams） | **24.2 MB** |
| `inputx-pinyin`（`default-features = false`，仅 core） | **4.77 MB** |
| 本仓内置兜底 | 0.44 MB（运行时读 TSV；数据 8.4 MB 词表未内嵌） |

- 即便**仅取 core** 也已 ≈ 4.4 MiB，是 `技术方案.md` §7.2「内置码表 ≤0.6 MB」预算的 **~7 倍**，更远超「拼音数据几百 KB」（§8.2）。
- 默认特性下的 ~23 MiB 数据与「更小、更干净」的项目定位直接冲突。

## 3. 质量（③ 20 常用词抽样）

方法：同一临时工程内并列调用 `inputx_pinyin::PinyinEngine::new().dict().lookup()` 与 `ime_pinyin::TablePinyinBackend::convert()`，取前 5 候选对比。inputx 在 core-only 与全特性下本样本结果一致。

| 指标 | 内置兜底 | inputx-pinyin |
|---|---|---|
| 目标词命中 @1 | **19 / 20** | 19 / 20 |
| 目标词命中 @5 | 19 / 20 | **20 / 20** |

- **持平**为主：`nihao→你好`、`zhongguo→中国`、`shurufa→输入法`、`beijing`、`shijie`、`jingji` 等 top-1 一致（`北京` 内置兜底反而排第 1，inputx 排第 2 为「背景」）。
- inputx 唯一占优：超长整句 `zhonghuarenmingongheguo→中华人民共和国`。
- 内置兜底在同样本漏掉该词，根因是**贪心最长优先切分**把 `mingong` 切成 `ming + o + ng`（正确应为 `min + gong`），拼接键不匹配词表 → 候选为空。**这是内置兜底自身的已知局限**（详见 §5），非 inputx 的压倒性优势。
- 反查（④）：两者单字首选读音一致（你→ni、的→de、行→xing、中→zhong）；本仓还支持**词级反查**，inputx facade 的 `char_to_pinyin` **仅单字**。

## 4. API / 可移植 / 维护度

**API 对齐 `PinyinBackend`（T-M2-02）**：
- `segment`：inputx 提供自由函数 `segment(&str) -> Vec<Segmentation>`（`Segmentation { syllables: Vec<String> }`），可适配。
- `convert`：`dict.lookup(&str) -> Vec<String>` **不含权重、不含简拼**；权重需改用 `lookup_with_freq_into`；**简拼（首字母）不在 facade**——`dict.prefix()` / `best_composition()` 对 `nh`/`zg` 返回空；简拼逻辑在其 `inputx-core` 的 `pinyin_adapter`，而 **`inputx-core` 未发布到 crates.io**。
- `reverse_lookup`：`char_to_pinyin(c) -> Vec<String>` 仅单字，无词级反查。
- **可 `impl Engine` 吗**：可以——本仓 `PinyinEngine` 已把任意 `PinyinBackend` 适配为 `ime_core::Engine`，写一个 `InputxBackend: PinyinBackend` 即可；但需**自写权重、简拼、词级反查**的适配代码（不引入其未发布的 `inputx-core`）。
- 结论：trait 抽象足以吸收（ADR-008 的核心成立），但接入不是「零成本换后端」。

**可移植**：纯 Rust，无 C 依赖；`inputx-fsa` 有 `#![forbid(unsafe_code)]`，`inputx-pinyin` 无 `unsafe`；edition 2024，MSRV 1.95（本仓固定 1.98.1 ✓）；宣称 WASM-ready，移动端交叉编译无阻碍。
**网络**：默认特性不含网络依赖；`ureq` 仅在 `tools`（数据流水线）特性下——接入时**绝不能启用 `tools`**，否则违反铁律 1。

**维护度**：
- 仓库创建 2026-05-17，最近推送 **2026-10-04**（活跃），但 **crates.io 停在 1.4.0（2026-05-27）**，落后 `develop`（已到 1.4.7、数据拆分为 sibling crate）；API 有变动迹象。
- **单作者**（bus factor 1），stars 5，open issues 2——正是 `docs/reviews/001.md` P1-2 与 ADR-008 预警的风险。

## 5. 结论与依据

**推荐：不接入（Phase 1）；观察（P2 参考），不写后续接入卡。**

1. **体积**：core 4.2 MiB / 默认 ~23 MiB，均超预算数量级，与项目「更小、更干净」定位冲突（决定项）。
2. **质量**：20 常用词与内置兜底**持平**（hit@1 各 19/20）；仅超长整句占优，而该缺口可用内置兜底自身的切分修复/后续自研 FSA 解决。
3. **维护/风险**：单作者、crates.io 版本滞后、API 变动，bus factor 1——不宜作为混输兜底的关键依赖。
4. **许可**：干净（不是否决项），故列为 P2「观察」候选，而非永久排除。
5. **终局**：仍按 ADR-008 走**自研 FSA**；`PinyinBackend` trait 保持，后续若有需要可将 inputx 作为**可选后端**在其后接入（不影响内置兜底）。

**本次附带发现（非本卡改动范围，记录备查）**：内置兜底的音节切分为「贪心最长优先 + 回溯」，对 `mingong` 这类歧义串会选到 `ming+o+ng` 而非 `min+gong`，导致超长整句词条漏检。可在 P2 自研引擎或以词频加权重排切分时一并解决。

**未决/后续**：
- 无新增接入卡。
- 若 P2 重新评估 inputx，需先复核其 **crates.io 发布版本**（当前 1.4.0）与体积是否收敛。
