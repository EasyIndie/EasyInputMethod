# crates/

Rust 工作区成员。**在 P1-M0 创建**（见 `ROADMAP.md`）。

| crate | 职责 | 关键约束 |
|---|---|---|
| `ime-core` | 状态机、`Engine` trait、`InputMode`、候选模型 | 零 IO / 零网络 / `forbid(unsafe_code)` |
| `ime-table` | 码表引擎（五笔） | 同上 |
| `ime-pinyin` | 拼音引擎（`PinyinBackend` 可插拔） | 同上 |
| `ime-dict` | 词典格式 + 编译器 + mmap 加载 | 解析器需 fuzz |
| `ime-config` | 配置子系统（Schema / 快照 / 原子写 / 广播） | 见 `docs/配置架构.md` |
| `ime-ffi` | 窄 C ABI（cdylib + staticlib） | **唯一允许 `unsafe` 的 crate** |
| `ime-cli` | 开发/测试 CLI + REPL + bench | 不发布 |

依赖方向单向，禁止反向：见 `AGENTS.md` §4。

新增 crate 前请先在 `docs/决策记录.md` 写 ADR。
