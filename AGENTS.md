# AGENTS.md — 萤火虫输入法

> **本文件是所有 AI 编码代理在本仓库工作时的唯一入口。**
> - **pi** / **Codex**：直接读取本文件。
> - **Claude Code**：读 `CLAUDE.md`，该文件只是指向本文件的指针。

---

## 0. 当前阶段（必读）

**方案交叉审核已有条件通过，首版功能与历史 MVP 工程收敛已完成，当前按审计归并计划推进可靠性修复及最终发布候选验收。当前状态以 HANDOFF.md 为准。**

- 审核通过前：**只允许修改文档**，不要创建 `crates/` 下的 Rust 代码。
- 审核通过后：第一个任务是 `ROADMAP.md` 的 **P1-M0**。

---

## 1. 项目是什么

**萤火虫**：跨平台、开源可审计、默认离线、只做核心输入的中文输入法。

- 默认**混合输入**：五笔优先，想不起码时自动用拼音兜底。
- **零网络、零遥测、无广告、无账号**。
- 单一 Rust 引擎 + 各平台薄宿主；许可证 **GPL-3.0-or-later**。

详细设计见 `docs/技术方案.md`。

---

## 2. 铁律（HARD RULES — 违反即视为错误）

1. **不联网**：核心 crate（`ime-core`/`ime-table`/`ime-pinyin`/`ime-dict`/`ime-config`）不得依赖任何网络 crate；不得引入遥测、统计、崩溃上报。
2. **内存安全**：核心 crate 必须 `#![forbid(unsafe_code)]`；`unsafe` **只允许**出现在 `ime-ffi`。
3. **配置唯一**：配置只能通过 `ime-config` 读写；**禁止**写入 `UserDefaults`、注册表、`NSUserDefaults`、环境变量或第二个配置文件。见 `docs/配置架构.md` 四条铁律。
4. **数据合规**：任何词典/词表/数据必须先在 `docs/数据来源与许可.md` 登记，并在 `data/sources.toml` 记录来源/许可/SHA-256；只接受与 GPL-3 兼容的许可。
5. **不扩功能**：不得实现 §3 非目标 中的任何功能；新增功能必须先写 ADR（见 `docs/决策记录.md`）。
6. **许可**：项目为 GPL-3.0-or-later；新依赖必须通过 `cargo deny check`（白名单见 `deny.toml`）。
7. **设计变更先写 ADR**：改架构/协议/约定 → 先更新 `docs/决策记录.md`，再动代码。
8. **提交前必须跑验证**：`make verify`（见 §5），全绿才能提交；**0 警告 0 错误**（ADR-081）。
9. **文档同步**：行为变更 → 同步更新对应文档；文档与代码不一致视为 bug。
10. **小步、可验证**：一次只做**一个**明确、可独立验证的改动；不要顺手重构无关代码。

---

## 3. 非目标（明确不做）

云输入 / 云同步 / 账号体系 · 广告 / 推广 / 弹窗 · 皮肤商店 · AI 写作 / 翻译 / 搜索 · 打字统计 / 用户画像 · 剪贴板历史 · 跨设备同步 · 本地语音（P6 之前不碰）。

---

## 4. 仓库地图（计划布局）

> 代码 crate 已在 **P1-M0** 创建。开发调试使用独立 AppKit 窗口（`make macos-preview`）。

```
EasyInputMethod/
├── AGENTS.md              # ← 你在这里（AI 入口）
├── HANDOFF.md             # ★ 会话交接（当前状态，每次会话更新）
├── CONTRIBUTING.md        # 贡献规范
├── ROADMAP.md             # 任务清单（带复选框）
├── Makefile               # 规范命令（make verify 等）
├── deny.toml              # 依赖许可/安全策略
├── rust-toolchain.toml    # 固定工具链
├── .agents/skills/        # Agent Skills（可复用的操作流程）
├── crates/
│   ├── ime-core/          # 状态机、Engine trait、InputMode、候选模型（零 IO/零网络）
│   ├── ime-table/         # 码表引擎（五笔）
│   ├── ime-pinyin/        # 拼音引擎（后端可插拔）
│   ├── ime-dict/          # 词典格式 + 编译器 + mmap 加载
│   ├── ime-config/        # 配置子系统（见 docs/配置架构.md）
│   ├── ime-ffi/           # 窄 C ABI（唯一 unsafe 集中地）
│   └── ime-cli/           # 开发/测试 CLI + REPL + bench
├── data/                  # 源数据 + sources.toml（许可登记）
├── tools/                 # 数据生成脚本（编码器库在 crates/wubi-encoder）
├── platforms/             # macos / windows / linux / android / ios
├── packaging/             # 安装包脚本
├── scripts/               # 验证/构建/派发/用量统计脚本
└── docs/                  # 设计与决策文档（tasks/ 任务卡、experiments/ 用量实验）
```

**依赖方向（单向，禁止反向）**：

```
ime-cli / ime-ffi
      ↓
ime-table / ime-pinyin
      ↓
ime-dict
      ↓
ime-core   ← 不依赖任何上层，不感知平台/UI/网络
ime-config ← 可被上层读取，但只由自身持久化
```

---

## 5. 验证命令（提交前必须执行）

```sh
make verify     # = fmt-check + lint + test + deny + verify-no-network
```

| 命令 | 作用 |
|---|---|
| `make fmt` | `cargo fmt --all` |
| `make lint` | `cargo clippy --all-targets -- -D warnings` |
| `make test` | `cargo test --workspace` |
| `make deny` | `cargo deny check`（许可 + 漏洞 + 重复依赖） |
| `make verify-no-network` | 断言产物无网络符号、进程无外联 |
| `make fuzz` | `cargo +nightly fuzz`（解析器，可选） |

> ⚠️ **零诊断门禁（ADR-081）**：`cargo` / `rustc` / `clippy` / `cargo-deny` / `swiftc` 的诊断必须为 **0**；`lint/test/deny/fast/verify` 已由 `scripts/check-clean.sh` 把关，CI 同源。有诊断就当失败修掉，不许当背景板。

无 `make` 时，直接运行 `Makefile` 中对应行。

---

## 6. 工作流（每次任务）

1. **选任务**：优先从 `docs/tasks/` 取一张"待认领"任务卡（更细粒度、flash 可执行）；没有卡时从 `ROADMAP.md` 取一个未勾选项（或用户明确指派）。
2. **确认设计**：阅读相关 `docs/`；若需要任何设计变更或偏离铁律，**先停下来**写 ADR 并在回复中说明。
3. **实现**：最小改动；遵守 §2 铁律与 §7 约定。
4. **自测**：`make verify` 全绿。
5. **更新文档/清单**：同步 `docs/`，勾选 `ROADMAP.md` 对应项（若已完成）。
6. **提交**：遵循 Conventional Commits（见 `CONTRIBUTING.md`）；一次提交只做一件事。
7. **报告**：说明改了什么、怎么验证、有何风险/未决问题。

> **遇到歧义先问，不要猜。** 宁可少做，不要做错。

### 6.1 会话协议（跨会话 / 跨工具）

本仓库由 pi / Codex / Claude Code **交替**开发，靠 `HANDOFF.md` 传递上下文：

- **开始任何会话**：先读 `HANDOFF.md`（当前状态）→ `ROADMAP.md`（进度）→ 与任务相关的 `docs/`。
- **结束任何会话**：按 Skill `update-handoff` 更新 `HANDOFF.md`（做了什么 / 当前状态 / 下一步 / 阻塞，并在日志顶部追加一条），并勾选 `ROADMAP.md`。
- `HANDOFF.md` 是**"当前状态"的唯一来源**。
- 不要把设计细节写进 `HANDOFF.md`（那些属于 `docs/`）；也不要把它当日记写成流水帐。

**标准交接流程（四种场景：上下文压缩 / 新会话 / 跨 agent / 跨设备）**：

```sh
./scripts/handoff-status.sh --for=compact|session|agent|device [--prompt]   # 只读采集当前状态
```

1. 用脚本表格填写 `HANDOFF.md`：§0 元信息、§1 设备与数据（含**执行 SHA** 与 config/输入源）、§3 未决、§4 下一步/§4.1 换设备、§9 日志（置顶 ≤5 行）。
2. 用 `docs/交接提示词模板.md` 的骨架生成下一位执行者的提示词（`--for=device` 时**必须**同时给 zip SHA 与执行 SHA）。
3. `make verify` 全绿后提交 `docs: handoff …` 并推送；详细契约与反例见 `.agents/skills/update-handoff/SKILL.md`。

> 上下文压缩前也要先落盘（HANDOFF + 一条日志），压缩后先读 HANDOFF 再动手，不要凭记忆继续。

---

## 7. 约定

| 项 | 约定 |
|---|---|
| 语言 | **代码、标识符、commit message 用英文**；**面向用户的文档、错误提示、配置注释用中文** |
| 错误处理 | 库用 `thiserror`/自定义 error，禁止 `unwrap()`/`expect()`（测试和 `ime-cli` 除外） |
| 依赖 | 能不加就不加；新增依赖须通过 `cargo deny`，并在 ADR 或 PR 说明理由 |
| 格式化 | `rustfmt` 默认；`clippy -D warnings` |
| 测试 | 每个 crate 有单测；解析器要有 fuzz 目标；关键逻辑要有回归测试 |
| Rust edition | 2021；MSRV 见 `rust-toolchain.toml` |
| 文档 | 设计文档放 `docs/`，**中文**；代码内文档注释用英文 `///` |
| 提交 | Conventional Commits：`feat:` / `fix:` / `docs:` / `refactor:` / `test:` / `chore:` |
| 分支 | `main` 保护；改动走 PR（见 `.github/PULL_REQUEST_TEMPLATE.md`） |

---

## 8. 决策流程（ADR）

- 任何**架构/协议/依赖/许可/对外行为**的变更，先在 `docs/决策记录.md` 追加一条 ADR（编号递增，不改历史）。
- 格式：`编号 / 决策 / 理由 / 状态 / 关联`。
- 待办项列在 ADR 文末的"待定项"。

---

## 9. Skills（可复用操作流程）

在 `.agents/skills/`（Agent Skills 规范）。执行前先读对应 `SKILL.md`：

| Skill | 何时用 |
|---|---|
| `update-handoff` | **每次会话结束前**（跨会话/跨工具交接） |
| `add-config-option` | 新增/修改一个配置项 |
| `add-data-source` | 引入任何词典/语料/数据 |
| `add-engine` | 新增一个输入引擎（如拼音、仓颉） |
| `verify-privacy` | 验证"零网络/零遥测"承诺 |

> **工具支持**：**pi** 直接读取 `.agents/skills/`；**Claude Code** 通过 `.claude/skills`（指向 `.agents/skills` 的软链）读取同一份内容。两者不复制，保持单一来源。

---

## 10. 深入文档

| 文档 | 内容 |
|---|---|
| `HANDOFF.md` | **当前状态**（会话交接，每次会话更新） |
| `docs/技术方案.md` | **权威总方案** |
| `docs/配置架构.md` | 配置子系统 |
| `docs/数据来源与许可.md` | 数据合规与准入 |
| `docs/隐私与安全.md` | 安全工程与可验证性 |
| `docs/决策记录.md` | ADR |
| `docs/参考与致谢.md` | 借鉴来源与复用边界 |
| `docs/README.md` | 文档索引 |

---

## 11. 给代理的一句话

**这个项目的价值在于"更小、更干净、可被第三方验证"，不在于功能多。**
当你在"多加一个功能"和"删掉一个功能"之间犹豫时，选删掉。
