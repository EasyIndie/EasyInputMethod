# 贡献指南（CONTRIBUTING）

> 本项目欢迎人类与 AI 代理共同贡献。**AI 代理请先读根目录 [`AGENTS.md`](./AGENTS.md)。**

## 1. 前置

- 工具链：见 `rust-toolchain.toml`（`rustup` 会自动切换）。
- 命令：`make help` 查看全部；提交前必须 `make verify` 全绿。
- 开发依赖：`make bootstrap` 安装 `cargo-deny` 等。
- 注意：`.claude/skills` 是指向 `.agents/skills` 的软链，**在 Windows 检出会失效**（当前 macOS 开发不受影响）。

## 2. 许可与署名

- 项目许可：**GPL-3.0-or-later**（见 `LICENSE`）。
- 提交即表示同意以该许可发布你的贡献。
- 使用 **DCO**（Developer Certificate of Origin）：每个提交加 `Signed-off-by`：

  ```sh
  git commit -s -m "feat(table): add wubi short-code support"
  ```

  即表示你确认有权提交该代码且同意其许可。

- **名称与 Logo 保留权利**：fork 版本请改名，不要使用"萤火虫"名称与 Logo。

## 3. 提交规范

采用 [Conventional Commits](https://www.conventionalcommits.org/)：

```
<type>(<scope>): <subject>

<body>

Signed-off-by: Your Name <you@example.com>
```

- `type`：`feat` / `fix` / `docs` / `refactor` / `test` / `chore` / `perf` / `build` / `ci`
- `scope`：crate 名或模块（如 `table`、`config`、`ffi`、`docs`）
- 主题用**英文**，祈使句、小写、无句号。
- **一次提交只做一件事**。

## 4. 分支与 PR

- `main` 受保护；所有改动走 PR。
- PR 必须填写 `.github/PULL_REQUEST_TEMPLATE.md`，包含：改了什么、为什么、如何验证、是否触及铁律。
- CI 必须全绿才能合并。
- 涉及架构/协议/许可 → 先提交 ADR（`docs/决策记录.md`）。

## 5. 代码规范

| 项 | 要求 |
|---|---|
| 格式 | `cargo fmt`（默认配置） |
| Lint | `cargo clippy --all-targets -- -D warnings` |
| 内存安全 | 核心 crate `#![forbid(unsafe_code)]`；`unsafe` 仅限 `ime-ffi` |
| 错误处理 | 库代码禁止 `unwrap()`/`expect()`（测试与 `ime-cli` 除外） |
| 测试 | 新逻辑需有单测；解析器改动需补 fuzz 目标 |
| 依赖 | 新增依赖须过 `cargo deny check` 并说明理由 |
| 注释 | 代码注释用英文；面向用户的文案用中文 |

## 6. 文档规范

- 设计/决策文档在 `docs/`，用**中文**。
- 行为变更必须同步更新文档；**文档与代码不一致视为 bug**。
- 新增数据必须先登记 `docs/数据来源与许可.md` 和 `data/sources.toml`。

## 7. 安全与隐私

- 提交前确认未引入网络/遥测代码（`make verify-no-network`）。
- 安全问题请走 `SECURITY.md`（后续补充），不要公开 issue 披露细节。

## 8. 审核偏好

- **小 PR 优于大 PR**；能拆就拆。
- **删代码优于加代码**（见 `AGENTS.md` §11）。
- 拒绝"顺手重构"与范围外改动。
