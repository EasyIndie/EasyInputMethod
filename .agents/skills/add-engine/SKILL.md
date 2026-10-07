---
name: add-engine
description: 为萤火虫输入法新增一个输入引擎或拼音后端（如五笔、拼音、仓颉、郑码）。当任务涉及 Engine/PinyinBackend trait、新输入方案、候选生成时使用。
---

# 新增引擎 / 后端

引擎边界见 `docs/技术方案.md` §6、§8。

## 步骤

1. **选择抽象**：
   - 码表类（五笔/郑码/仓颉）→ 实现 `ime-table` 的码表引擎；
   - 拼音类 → 实现 `PinyinBackend` trait；
   - 新类别 → 先写 ADR 定义新 trait，不要往现有 trait 里塞特例。
2. **保持纯逻辑**：新引擎不得依赖平台、UI、网络、文件系统（数据通过参数注入）。核心 crate 需 `#![forbid(unsafe_code)]`。
3. **数据与代码分离**：词典/码表来自 `data/`，遵循 `add-data-source` skill。
4. **接入混输**：若属于默认混输的一部分，在 `ime-core` 的合并逻辑中注册，并携带正确的 `CandidateSource` 标记。
5. **排序**：遵守"两层排序"（`base_sort` + `user_frequency`），不要自创排序旁的旁路。
6. **测试**：
   - 单测：精确/前缀查询、边界（空输入、超长、非法字符）；
   - 若解析数据文件 → 加 fuzz 目标；
   - 性能：单次 `convert` 在预算内（<16ms）。
7. **文档**：更新 `docs/技术方案.md` §6/§8 与（如涉及）ADR。
8. **自检**：
   - [ ] 不引入网络/平台依赖；
   - [ ] `#![forbid(unsafe_code)]`；
   - [ ] 数据已登记许可；
   - [ ] 有单测（+ 解析则 fuzz）；
   - [ ] `make verify` 通过。

## 禁止

- 在 `ime-core` 里为某个具体引擎写 `if engine == "wubi"` 之类的特判；
- 让引擎直接读配置文件（应通过 trait 参数注入）；
- 引入 GPL 前端（weasel/squirrel）的代码。
