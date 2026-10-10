# 多角色全面审计（2026-10-10）

> **性质：只读审计 + 问题记录，未改任何代码。** 用于决定"MVP 内统一处理 vs 发布后迭代"。
> 角色视角：资深产品 / 架构师 / 质量保障 / 安全研究 / 自动化运维 / 文档专家。
> 关联：[盘点007](007-ux-and-tech-debt.md)（UX/TD 明细）、[报告006](006-macos-mvp-gap-review.md)、ADR-057…065。
>
> 分级：`MVP` = 建议随首版处理；`P2` = 发布后迭代；`观察` = 记录不改（可接受/非目标）。
> 证据均来自当前源码/脚本/CI/文档；未做渗透测试、未复核远端设置。

---

## 0. 结论摘要

- 工程骨架**扎实**：分层清晰、核心 `forbid(unsafe_code)`、FFI 有 panic 兜底、CI 固定 Actions、依赖审计强制、数据可复现。
- 真正需要"随 MVP 收"的是**安全一致性 + 性能/IO 债 + 测试/CI 补强 + 文档同步**，均为**行为不变或极小**的工程改动。
- **新功能面**（设置界面、字根提示、简繁、emoji、i18n）不是"债"，会扩大范围 → **建议 P2**。
- 已发现 **1 个潜在内存安全缺陷**（`ime_config_snapshot` 跨线程借用），当前宿主未使用，但必须修或废弃。

| 视角 | 高优发现 | MVP 项数 | P2 项数 |
|---|---|---|---|
| 产品 | 无鼠标点选、无状态指示、无关于 | 3 | 6 |
| 架构 | snapshot 借用不安全、无 ABI 版本、词库 IO | 3 | 5 |
| 质量 | fuzz 未进 CI、性能基线噪声、锁竞态无测试 | 3 | 5 |
| 安全 | snapshot UAF、配置权限不一致、锁策略不一致 | 4 | 3 |
| 运维 | 分支保护/演练、依赖自动化、定时扫描 | 3 | 3 |
| 文档 | 005 陈旧、无 CHANGELOG、发布指引分散 | 4 | 2 |

---

## 1. 产品（PROD）

| ID | 问题 | 证据 | 影响 | 分级 |
|---|---|---|---|---|
| PROD-01 | 无设置界面，偏好只能改 `config.toml` | 无 UI；`ime_config_schema()` 已备 | 普通用户门槛高 | P2 |
| PROD-02 | 菜单无「关于/版本」 | `InputController.menu()` | 看不到版本/构建 | MVP |
| PROD-03 | **候选不支持鼠标点选** | `CandidateWindow` 仅 `NSTextField`，无鼠标/手势处理 | 与主流输入法直觉不符 | MVP |
| PROD-04 | **无中英/全角/模式状态指示** | 菜单栏无角标；候选窗无标记（仅打开菜单可见当前模式） | 用户不确定当前状态 | MVP |
| PROD-05 | 无字根提示（§6.2 既定能力） | `Candidate.comment` 未展示 | 学习辅助缺失 | P2 |
| PROD-06 | 无简繁转换 | 未实现 | 繁体用户不可用 | P2 |
| PROD-07 | 无 emoji/符号面板 | 未实现 | 输入符号不便 | P2 |
| PROD-08 | 无首次使用引导/帮助入口 | 无 | 上手成本 | P2 |
| PROD-09 | 无 i18n（菜单/提示硬编码中文） | 宿主字符串 | 非中文用户 | P2 |
| PROD-10 | 词库锁残留需手工处理 | ADR-063/故障恢复文档 | 异常后需人工 | P2（保守） |
| PROD-11 | 超 64 字符静默忽略 | ADR-062 | 极端场景无反馈 | 观察 |

## 2. 架构（ARCH）

| ID | 问题 | 证据 | 影响 | 分级 |
|---|---|---|---|---|
| ARCH-01 | **`ime_config_snapshot` 借用不安全**：单槽 `SNAPSHOT: Mutex<Option<Arc>>`，并发调用时先者的 `Arc` 被后者覆盖释放 → 悬垂指针 | `crates/ime-ffi/src/config.rs` | 潜在 UAF，且与"线程安全只读"声明矛盾（当前宿主未用） | MVP |
| ARCH-02 | 无 FFI/ABI 版本号 | `ime.h` 无 version | 宿主/库不匹配无检测 | MVP |
| ARCH-03 | `ime-config` 文件监听 **200ms 常驻轮询** | `config.rs` `FileWatcher::start(200ms,150ms)` | 空闲唤醒（与 MVP-13 已修 UI 定时器形成新空闲源） | P2 |
| ARCH-04 | 词库 **每键全表扫描 + 每次选词全量重写**（TD-01/02） | `ime-ffi/session.rs`、`ime-dict/lib.rs` | 词库增大后卡顿/IO | MVP |
| ARCH-05 | `Candidate.comment` 从未使用 | `ime-core` 字段 | 死字段/扩展点 | 观察 |
| ARCH-06 | TSV 解析逻辑在 ime-table/ime-pinyin/ime-dict 各写一份 | 三处 `from_tsv/parse` | 重复、易漂移 | P2 |
| ARCH-07 | `CandidateSource::Phrase` 从未构造 | `ime-core` | 冗余枚举 | 观察 |
| ARCH-08 | 无 Schema→设置界面通路 | 见 PROD-01 | 同源 | P2 |
| ARCH-09 | 平台抽象仅 macOS 验证 | 仅 `platforms/macos` | Windows/Linux 未验 | P2 |
| ARCH-10 | `ime-ffi` 一 crate 承载 session/config/schema/data | `crates/ime-ffi/src/*` | 可接受 | 观察 |

## 3. 质量（QA）

| ID | 问题 | 证据 | 影响 | 分级 |
|---|---|---|---|---|
| QA-01 | **fuzz 未进 CI**（仅 `make fuzz` 手动） | `Makefile`、workflows | 解析器回归靠本地 | MVP |
| QA-02 | `render-perf` 噪声大、无稳定基线 | 本机 p95 9–27ms 波动 | 性能回归难判定 | MVP |
| QA-03 | 属性/差分测试少（已加 1 个 `convert` 差分） | `ime-table` tests | 覆盖可扩 | P2 |
| QA-04 | 配置**锁竞态/陈旧删除**无测试 | `ime-config` 无相关测试 | 并发行为未验证 | MVP |
| QA-05 | packaging 脚本测试覆盖有限 | 仅 2 个 py 测试 | 回归靠 CI 步骤 | P2 |
| QA-06 | 无覆盖率度量 | 无 | 盲区不可见 | P2 |
| QA-07 | `ime_config_snapshot` 无并发测试（因未用） | — | 同 ARCH-01 | MVP |
| QA-08 | `wubi-encoder` 无 fuzz（输入为字典数据） | — | 低风险 | P2 |
| QA-09 | 无签名应用 E2E 自动化 | — | 固有 | 观察 |
| QA-10 | `FileWatcher` debounce 无测试 | — | 低 | 观察 |

## 4. 安全（SEC）

| ID | 问题 | 证据 | 影响 | 分级 |
|---|---|---|---|---|
| SEC-01 | **`ime_config_snapshot` 跨线程悬垂**（同 ARCH-01） | 同上 | 潜在 UAF | MVP |
| SEC-02 | **配置文件权限不一致**：`atomic_write` 用默认 umask（通常 0644），用户词库为 0600 | `ime-config/persist.rs` vs `ime-dict` | 配置可被同机他用户读 | MVP |
| SEC-03 | **锁策略不一致**：config 锁 30s 自动删（`STALE_LOCK_TIMEOUT`），词库锁不自动删；自动删锁存在竞态 | `persist.rs`、`ime-dict` | 互斥被破坏风险 | MVP |
| SEC-04 | 借用指针生命周期仅靠文档（候选/缓冲区/snapshot） | `ime.h` | 误用即 UAF | 观察（API 设计） |
| SEC-05 | `subscribe` 的 `user` 裸指针无生命周期保证 | `config.rs` | 潜在 UAF（当前传 nil） | MVP（限制/文档） |
| SEC-06 | `catch_unwind` + 中毒锁静默降级 | `error.rs`、`SNAPSHOT.lock()` | 错误被吞 | 观察 |
| SEC-07 | `make bootstrap` 未固定 `cargo-deny` 版本 | `Makefile` | 供应链轻微 | MVP |
| SEC-08 | 无**定时**依赖/公告扫描（仅随 CI 运行） | workflows | 公告滞后发现 | MVP |
| SEC-09 | `NSLog` 打印本地路径到系统日志 | 宿主 | 本机隐私轻微 | P2 |
| SEC-10 | 运行时零外联需人工 `lsof` | `verify-no-network.sh` 仅符号级 | 动态验证不可自动 | P2 |
| SEC-11 | `unsafe impl Send/Sync` for Schema（已论证） | `config.rs` | 可接受，建议注释/测试 | 观察 |
| SEC-12 | 供应链 ✅：Actions 固定 SHA、`rust-toolchain`/`Cargo.lock` 固定、`deny.toml` advisories | — | — | ✅ |

## 5. 自动化运维（OPS）

| ID | 问题 | 证据 | 影响 | 分级 |
|---|---|---|---|---|
| OPS-01 | main 分支保护未验证 | 私仓 Free 403（004） | 公开后需补 | MVP（转公开后） |
| OPS-02 | 无 Dependabot/Renovate | 无配置 | 依赖/Actions 更新手工 | P2 |
| OPS-03 | Release/Pages 未端到端演练 | 有 `dry_run` 设计 | 首跑风险 | MVP（演练） |
| OPS-04 | 制品保留 30 天 | workflows | 已由 Release 承载 ✅ | ✅ |
| OPS-05 | 无 Windows/Linux 构建矩阵 | workflows | 未来平台 | P2 |
| OPS-06 | CI 无 fuzz 短跑、无 deny 定时 | workflows | 同 QA-01/SEC-08 | MVP |
| OPS-07 | `make bootstrap` 幂等/版本 | `Makefile` | 开发体验 | MVP（随 SEC-07） |
| OPS-08 | Release 无独立 SBOM 校验步骤 | packaging 已含 SBOM | 低 | 观察 |
| OPS-09 | 磁盘/并行预检已就绪 | `scripts/dispatch-task.sh` | ✅ | ✅ |
| OPS-10 | 无监控/遥测（离线产品，符合非目标） | — | 设计如此 | 观察 |

## 6. 文档（DOC）

| ID | 问题 | 证据 | 影响 | 分级 |
|---|---|---|---|---|
| DOC-01 | 报告 005 状态陈旧 | `docs/reviews/005*` | 交接误导 | MVP |
| DOC-02 | HANDOFF 结构编号跳号/历史叙事 | `HANDOFF.md` | 可读性 | MVP（低） |
| DOC-03 | 无 CHANGELOG | 无 | 版本变更不可追溯 | P2 |
| DOC-04 | `技术方案.md` §5.3 ABI 摘要不全（已注明以 `ime.h` 为准） | — | 低 | 观察 |
| DOC-05 | 007/008 未互相引用 | 本轮 | 索引 | MVP（低） |
| DOC-06 | Pages 站与 `docs/` 内容可能双份 | `site/` | 漂移 | 观察 |
| DOC-07 | 中文文件名链接在 Pages 需 URL 编码 | `site/index.html` 指向 `故障恢复.md` | 可能 404 | 观察 |
| DOC-08 | 发布步骤分散在 checklist/发布说明/ADR-065 | 三处 | 易漏 | MVP（合并指引） |

---

## 7. 建议随 MVP 处理（工程收敛；行为不变或极小）

| 序 | 项 | 关联 | 规模 | 风险 |
|---|---|---|---|---|
| 1 | 修/废弃 `ime_config_snapshot`，消除跨线程悬垂 + 并发测试 | SEC-01/ARCH-01/QA-07 | S | 低 |
| 2 | 统一文件权限为 0600（配置）+ 统一锁策略并写清文档 | SEC-02/SEC-03 | S | 低 |
| 3 | 词库写入去抖/批量 + 用户候选增量索引 | ARCH-04/TD-01/02 | M | 中（需基准） |
| 4 | 候选窗**鼠标点选** + 中英/全角/模式**状态指示** | PROD-03/04 | M | 中 |
| 5 | 菜单加「关于/版本（构建）」 | PROD-02 | S | 低 |
| 6 | 加 `ime_abi_version()` 并在宿主启动校验 | ARCH-02 | S | 低 |
| 7 | 限制/文档化 `subscribe` 的 `user` 生命周期 | SEC-05 | S | 低 |
| 8 | fuzz 短跑进 CI + 定时 `cargo deny` + 固定 `cargo-deny` 版本 | QA-01/SEC-07/08/OPS-06/07 | S | 低 |
| 9 | 性能基线归一（`run-perf` 为准，`render-perf` 标参考） | QA-02 | S | 低 |
| 10 | 文档同步：005、HANDOFF、发布指引合并、007/008 互链 | DOC-01/02/05/08 | S | 低 |
| 11 | 分支保护 + Release/Pages 演练（转公开后） | OPS-01/03 | S | 低 |

> 全部为**可独立验证**的改动；3/4 需先补基准或几何测试。**不改变对外行为承诺**，不扩功能面。

## 8. 建议 MVP 之后（P2）

- 设置界面（PROD-01/ARCH-08）、字根提示（PROD-05）、简繁（PROD-06）、emoji（PROD-07）、首次引导（PROD-08）、i18n（PROD-09）、词库锁安全自动恢复（PROD-10）。
- watcher 轮询优化（ARCH-03）、TSV 解析去重（ARCH-06）、多平台（ARCH-09）、属性测试/覆盖率（QA-03/05/06）、依赖自动化（OPS-02）、多平台矩阵（OPS-05）、CHANGELOG（DOC-03）、NSLog 隐私（SEC-09）、运行时外联自动化（SEC-10）。

## 9. 前提与边界

- 本审计为**静态只读**，未做动态渗透、未复核远端仓库设置/套餐、未做逐行数据流分析。
- 部分结论需**真机/其他系统**验证（多屏定位、性能长稳、macOS 26/27）。
- "能否在 MVP 全部处理"：**推荐只收第 7 节 11 项**（工程债 + 关键体验）；第 8 节属功能扩展，放入 P2 才能保持首版可交付。

## 10. 下一步

先据此**统一排期**（本文件第 7/8 节即草案），逐条拆 `docs/tasks/` 任务卡并实施；每条独立提交、`make verify` 全绿。**本轮不改代码。**
