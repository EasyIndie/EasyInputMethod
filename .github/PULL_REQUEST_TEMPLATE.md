# Pull Request

## 改了什么

<!-- 一句话说明本 PR 的改动。一次只做一件事。 -->

## 为什么

<!-- 关联 ROADMAP 编号（如 P1-M0）或 ADR 编号。 -->

- ROADMAP: 
- ADR: 

## 如何验证

<!-- 列出复现验证步骤；CI 之外的手动验证也写在这里。 -->

```sh
make verify
```

## 铁律自检（AGENTS.md §2）

- [ ] 未引入网络/遥测（`make verify-no-network` 通过）
- [ ] 核心 crate `#![forbid(unsafe_code)]`（unsafe 仅在 `ime-ffi`）
- [ ] 配置只走 `ime-config`，未写 `UserDefaults`/注册表
- [ ] 新增数据已在 `docs/数据来源与许可.md` + `data/sources.toml` 登记
- [ ] 未实现非目标功能
- [ ] 新依赖通过 `cargo deny check`
- [ ] 需要设计变更时已先提交 ADR
- [ ] 文档已同步更新

## 风险 / 未决问题

<!-- 有任何不确定性都写在这里，不要隐瞒。 -->
