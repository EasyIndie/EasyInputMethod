# T-STD86：LWS-86 标准落地后续（扩字 / 差异清单 / 对外发布）

- 状态：待认领
- 模型建议：pro（涉及口径判断与对外表述）
- 前置：ADR-381（标准已发布 1.0 草案）、T-ROOT86（根序补齐，提升 `full`）
- 目标：把 LWS-86 从"1.0 草案"推进到"可被第三方正式引用"的状态。

## 已完成（1.0 草案，2026-11-19）

`docs/standards/wubi86/{spec-1.0,conformance-1.0,CHANGELOG}.md` + `tools/wubi86-std-{bundle,check}.py`
+ `platforms/macos/tests/test-wubi86-standard.py`（自检 L4 通过、变异能被抓到）。

## 步骤

1. **差异清单**（S，1–2 天）：抽样 50–100 常用字，用王码官方软件/教材的拆法提示（**构建期 oracle，不入库**）
   与我们数据逐字对照，产出 `docs/standards/wubi86/wangma-diff.md`：一致率、差异字与我们的理由。
2. **数据包发布**（S）：`make wubi86-standard` 生成 `build/wubi86-std-1.0/`，附 `SHA256SUMS`；
   作为 Release 资产（与版本 tag 绑定），并在站点加一页"标准"入口（`site/`）。
3. **扩字覆盖**（M–L，依赖 T-ROOT86）：先 GB2312 二级（+3,008 字），再按需扩到 GB18030 常用子集；
   每次扩字必须重跑 L1–L4 与 `partial` 归因统计，写进 CHANGELOG。
4. **第三方可用性验证**（S）：用一个非本项目的实现（如 `ime-cli` 之外的最小解析器，或第三方码表）跑
   `wubi86-std-check.py --impl`，确认文档与实际判定一致；把结果写进 CHANGELOG（"已由 X 验证"）。
5. **1.0 转正**（S）：上述完成 + 至少一轮外部反馈后，把 `spec-1.0.md` 状态从"草案"改为"1.0 正式"，
   并在 `docs/standards/README.md` 与 README 首页登记。

## 验收

```sh
make wubi86-standard                # 生成数据包并自检 L4
make verify && make macos-offline-tests
python3 tools/wubi86-std-check.py --bundle build/wubi86-std-1.0 --level L4
```

## 禁止

- 不宣称"官方/权威/与王码 100% 一致"；不暗示王码/中研院背书；
- 不把无许可来源写进规范数据；不删/改已发布的版本数据（只增值与勘误）；
- 不为通过判定而放宽 R1–R10。

## 参考

`docs/standards/wubi86/spec-1.0.md`、`conformance-1.0.md`、ADR-381、报告 303/304。
