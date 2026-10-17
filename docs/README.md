# 萤火虫输入法 · 文档索引

> 项目已进入实现阶段（macOS 首版收尾，见 `../HANDOFF.md`）。
> 审核请优先读 `技术方案.md`，再按需展开其它文档。

> **AI 代理**：请先读仓库根目录的 [`../AGENTS.md`](../AGENTS.md)（铁律、工作流、验证命令）、[`../HANDOFF.md`](../HANDOFF.md)（当前状态）与 [`../ROADMAP.md`](../ROADMAP.md)（任务清单），再按需查阅本目录文档。

非人工工程验收见 [MVP自动验收状态](MVP自动验收状态.md)。

MVP定义及发布验收见 [MVP产品验收标准](MVP产品验收标准.md)；首版后的路线见 [MVP后里程碑](MVP后里程碑.md)。

本地逐场景自动验收及证据边界见 [报告041](reviews/041-local-automated-acceptance.md)；可重复入口见 [任务卡](tasks/T-LOCAL-ACCEPTANCE.md)。

## 权威文档（当前有效）

| 文档 | 内容 | 读者 |
|---|---|---|
| **[技术方案.md](./技术方案.md)** | **权威总方案**：定位、竞品摘要、架构、引擎、词库、拼音、平台、里程碑、风险 | 所有人 |
| [配置架构.md](./配置架构.md) | 配置子系统：真值唯一、单一写入、实时生效、Schema 驱动 | 实现配置/设置界面 |
| [开发工作流.md](./开发工作流.md) | 分层 CI、单人/团队开关、本地提速、质量与铁律自动化 | 所有贡献者 |
| [数据来源与许可.md](./数据来源与许可.md) | 数据准入制度、来源清单、自建流水线、许可兼容 | 实现词库/合规 |
| [隐私与安全.md](./隐私与安全.md) | 隐私承诺、威胁模型、可验证性、审阅核对清单 | 安全审阅 |
| [决策记录.md](./决策记录.md) | ADR：已冻结决策与理由、待定项 | 所有人 |
| [故障恢复.md](./故障恢复.md) | 配置 / 用户词库 / 数据文件的诊断与手工恢复步骤 | 本机排障 |
| [发布说明.md](./发布说明.md) | 版本说明、已验环境、功能与限制、快捷键、导入格式、归档与分发 | 发布/接收方 |
| [人工验收与多机复现.md](./人工验收与多机复现.md) | 历史验收操作与多机复现步骤；最新候选待验，旧脚本须先修数据保护 | 收尾验收者 |
| [参考与致谢.md](./参考与致谢.md) | 借鉴的项目与来源、复用边界 | 所有人 |

**当前统一优先级、依赖、验收和暂缓项见 [迭代计划](迭代计划.md)；近期实施入口见 [任务卡](tasks/README.md)。**

首版要求与历史实现差距见 [对照报告006](reviews/006-macos-mvp-gap-review.md)。

设备 B 当前功能、UX、UI 与 macOS 工程审计见 [审计009](reviews/009-macos-product-engineering-audit.md)（2026-10-11；含隔离复现、证据边界与优先级）。

体验问题与技术债盘点（优化排期依据）见 [盘点007](reviews/007-ux-and-tech-debt.md)；跨角色全面审计与 MVP/P2 分级见 [审计008](reviews/008-multi-role-audit.md)。

发布进度与剩余验收见 [macOS发布清单](macos-release-checklist.md)；**只能人工做的验收项与第二台 Mac 复现步骤**见 [人工验收与多机复现](人工验收与多机复现.md)。

## 历史文档（已归档，仅供追溯）

`archive/` 目录下为讨论过程稿，**结论已并入 `技术方案.md`**：

- `archive/中文输入法调研.md` — Windows/macOS/Linux 中文输入法全景调研与隐私分析
- `archive/技术架构方案.md` — v0.1（通用架构）
- `archive/技术方案-v0.2-Rust.md` — Rust 化首稿
- `archive/技术方案-v0.3.md` — 竞品/码表/拼音调研
- `archive/技术方案-v0.4.md` — 命名/自建码表/混输
- `archive/技术方案-v0.5.md` — 术语/命名 rev2/许可证/配置

## 审核建议路径

1. 读 `技术方案.md` §1–§5（定位、产品、竞品、选型、架构）——判断方向；
2. 读 §6–§8（引擎、词库自建、拼音）——判断技术可行性；
3. 读 `配置架构.md` + `隐私与安全.md`——判断系统性与合规；
4. 读 `决策记录.md`——确认所有冻结项无异议；
5. 有异议 → 在对应文档提，或新增 ADR。

## 待确认 / 待调研（见 `决策记录.md` 待定项）

- TBD-1 ✅ 已定 `fxsjy/jieba`（D10，MIT；ADR-021）
- TBD-2 五笔98 / 新世纪 / 郑码数据源
- TBD-3 ✅ ADR-029：有界 TSV v1
- TBD-4 ✅ 英文/包名定为 `Lampyris`（ADR-056）

- [MVP单人验收清单](MVP单人验收清单.md)：用户手动走查、五工作日试用与独立核验材料（ADR-125）。

- [核心完整性与精简范围评估011](reviews/011-core-completeness-and-scope.md)：官方对照与21个私有默认配置FFI样例，当前调研不改变产品行为。

[核心输入收口第一批012](reviews/012-core-refinement.md)

[IT-25公开门禁与CI公证013](reviews/013-it25-ci-notary.md)

[常用多音读音质量014](reviews/014-pinyin-reading-quality.md)

[组合编辑/安全输入边界015](reviews/015-editing-boundary-audit.md)

2026-10-14用户批准ADR-165：基础UI纳入MVP，候选→设置/菜单→既有工具/反馈→外观/AX→重新锁最终包；功能基线66ab513保留，完整教学后移。实施见docs/design/mvp-ui.md及T-MVP-UI；历史“全UI延期”段落被本决策覆盖，新UI尚未原生验收。

[MVP基础UI工程验收018](reviews/018-mvp-ui-engineering.md)：UI01…04代码改造及22文件80离线测试完成，最终签名包实机门禁保持待验。

[全量五笔教学生成与自建结构库调研036](reviews/036-generated-wubi-teaching-research.md)：比较自建/外部结构事实、版本规则与教程复用；包含受限模板原型和准入边界，方案尚未采纳。

[结构模块体积与拆分边界037](reviews/037-structure-module-size-and-boundaries.md)：现有体积实测、运行资源分层与ADR-189；模块目录见modules/hanzi-structure。

[当前MVP剩余工作038](reviews/038-mvp-remaining-work.md)：ADR-190将自建库后移，区分未开始的真实验收、已完成工程及最终候选收口；优先于旧计划中的实施状态。

[控件标签与说明间距039](reviews/039-controls-labels-and-description-spacing.md)：按钮/菜单无省略号、模式系统符号、四项说明统一基线及亮暗原生渲染证据。

真实IMK的未执行准备材料见 [报告042](reviews/042-imk-acceptance-preparation.md)及[任务卡](tasks/T-IMK-ACCEPTANCE-PREP.md)。

正式包账号数据隔离前置及边界见 [报告043](reviews/043-formal-account-isolation-gate.md)。

候选/学习区单动作保护及候选收口见 [报告044](reviews/044-guarded-candidate-learning-actions.md)。

[标准模式菜单061](reviews/061-standard-native-mode-menu.md)：停止旧父项混合交互诊断，改用标准系统展开和显式选择，三级证据及实机发布边界。
