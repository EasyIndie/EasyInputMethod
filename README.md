# 萤火虫输入法（EasyInputMethod）

<img src="assets/icons/yinghuo-icon-v4-line.png" width="160" alt="萤火虫项目图标：V4 单线标志">

> 一款**跨平台、开源可审计、默认离线、只做核心输入**的中文输入法。
>
> **状态：方案已冻结，待交叉审核后进入实现。** 现在是"文档 + 脚手架"阶段，尚无功能代码。

## 这是什么

- **默认混合输入**：五笔优先，想不起码时自动用拼音兜底，不用切模式。
- **隐私优先**：零网络、零遥测、无广告、无账号；网络行为可抓包验证。
- **小而美**：只做输入本身，不做云同步/皮肤商店/AI 写作/内容分发。
- **跨平台**：macOS → Windows → Linux → Android/iOS，共享同一套 Rust 引擎。
- **开源可审计**：核心 `forbid(unsafe_code)`；码表可复现生成。
- **许可证**：GPL-3.0-or-later（防止被闭源包装成劣币）。

## 名字

**萤火虫** —— 小、自带微光（不依赖云端）、安静不打扰。

英文/包名不使用 `Firefly`（与 Adobe Firefly 等冲突），使用 `yinghuo` / `lampyris`。

## 目录

```
AGENTS.md          # ★ AI 代理入口（所有工具的统一规则）
HANDOFF.md         # ★ 会话交接（当前状态，每次会话更新）
CONTRIBUTING.md    # 贡献规范（DCO / Conventional Commits）
ROADMAP.md         # 任务清单（带复选框）
Makefile           # make verify 等规范命令
.agents/skills/    # Agent Skills（可复用操作流程）
docs/              # 设计与决策文档
crates/            # Rust 工作区（P1-M0 创建）
platforms/ data/ tools/ packaging/ scripts/
```

## 文档

请从 **[docs/技术方案.md](docs/技术方案.md)** 开始；索引见 [docs/README.md](docs/README.md)。

| 文档 | 内容 |
|---|---|
| [技术方案.md](docs/技术方案.md) | 权威总方案 |
| [配置架构.md](docs/配置架构.md) | 配置子系统（真值唯一 / 实时生效） |
| [数据来源与许可.md](docs/数据来源与许可.md) | 数据合规 |
| [隐私与安全.md](docs/隐私与安全.md) | 安全工程 |
| [决策记录.md](docs/决策记录.md) | ADR |
| [参考与致谢.md](docs/参考与致谢.md) | 借鉴来源 |

## AI 辅助开发

本仓库为长期与 AI 代理共同迭代而组织，支持 **pi / Codex / Claude Code**：

- **[AGENTS.md](AGENTS.md)** —— 唯一入口与规则来源（pi 与 Codex 直接读取）。
- **[HANDOFF.md](HANDOFF.md)** —— **跨会话/跨工具交接**：当前状态、下一步、阻塞（每次会话结束更新）。
- **[CLAUDE.md](CLAUDE.md)** —— 指向 AGENTS.md 的兼容指针（Claude Code）。
- **[ROADMAP.md](ROADMAP.md)** —— AI 从这里取任务（一次一个）。
- **`.agents/skills/`** —— 可复用操作流程：`update-handoff`、`add-config-option`、`add-data-source`、`add-engine`、`verify-privacy`（`.claude/skills` 为指向它的软链，供 Claude Code 读取）。
- **[CONTRIBUTING.md](CONTRIBUTING.md)** —— 提交规范与铁律。
- `make verify` —— 提交前的统一验证（格式 / lint / 测试 / 许可 / 隐私断言）。

## 路线图（摘要）

| 阶段 | 目标 |
|---|---|
| **P1** | macOS 上"默认可混输"的完整五笔输入法 |
| P2 | 拼音体验打磨 + 自研引擎 |
| P3 | Windows（Rust TSF） |
| P4 | Linux（Fcitx5） |
| P5 | Android / iOS |
| P6 | 本地语音（可选，纯本地） |

## 许可

GPL-3.0-or-later，见 [LICENSE](./LICENSE)。
项目名称与 Logo 保留权利；fork 版本请改名。

## 项目图标

[图标资产目录](assets/icons/README.md)保留 V1–V5；当前首选 **V4 单线标志**，以简洁线条表达项目定位。
