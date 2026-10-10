# MVP 收敛任务清单（T-MVP-01…11）

> 依据：[审计008](../reviews/008-multi-role-audit.md) 第 7 节 + [盘点007](../reviews/007-ux-and-tech-debt.md)。
> 原则：**行为不变或极小**、可独立验证；新功能面（设置界面/字根/简繁/emoji/i18n）**不在本清单**（P2）。
> 每条独立提交；`make verify` 全绿；行为/协议变更先补 ADR。

| ID | 任务 | 关联 | 规模 | 状态 |
|---|---|---|---|---|
| T-MVP-01 | 修 `ime_config_snapshot` 跨线程借用（改按线程保留借用）+ 并发烟雾测试 | SEC-01/ARCH-01/QA-07 | S | [x] |
| T-MVP-02 | 统一文件权限 0600（配置写入）+ 文档化锁策略差异 | SEC-02/SEC-03 | S | [x] |
| T-MVP-03 | `subscribe` 的 `user` 裸指针生命周期：限制/文档化 | SEC-05 | S | [x] |
| T-MVP-04 | 加 `ime_abi_version()`，宿主启动校验 | ARCH-02 | S | [x] |
| T-MVP-05 | 菜单加「关于/版本（构建）」 | PROD-02 | S | [x] |
| T-MVP-06 | 候选窗**鼠标点选** + **中英/全角/模式状态指示** | PROD-03/04 | M | [x] |
| T-MVP-07 | 词库写入不去 fsync（会话末 flush）+ 用户候选 BTreeMap 前缀 range | ARCH-04/TD-01/02 | M | [x] |
| T-MVP-08 | fuzz 短跑进 CI + 定时 `cargo deny` + 固定 `cargo-deny` 版本 | QA-01/SEC-07/08/OPS-06/07 | S | [x] |
| T-MVP-09 | 性能基线归一（`run-perf` 为准，`render-perf` 标参考） | QA-02 | S | [x] |
| T-MVP-10 | 文档同步：报告005 / HANDOFF / 发布指引合并 | DOC-01/02/08 | S | [x] |
| T-MVP-11 | 分支保护 + Release/Pages（**已公开，保护/Pages 已就绪**） | OPS-01/03 | S | [x] |

## 验收约定

- 每项：新增/更新单测或冒烟断言；`make verify` 全绿；必要时更新对应文档与 ADR。
- T-MVP-06/07 改动面较大：先补几何/基准证据，再改。
- 本清单完成即"MVP 工程收敛"；P2 项另立 backlog。

## 顺序

先做 **S 且零行为变更**的：01 → 02 → 03 → 04 → 05 → 08 → 09 → 10；再做 06 → 07；11 待转公开。
