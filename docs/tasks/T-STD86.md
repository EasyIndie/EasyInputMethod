# T-STD86：LWS-86 标准落地后续（扩字 / 差异清单 / 对外发布）

- 状态：**已完成（2026-11-20，随 1.4.0 发布；ADR-388）**
- 模型建议：pro（涉及口径判断与对外表述）
- 前置：ADR-381（标准已发布 1.0 草案）、T-ROOT86（根序补齐，提升 `full`）
- 目标：把 LWS-86 从"1.0 草案"推进到"可被第三方正式引用"的状态。

## 已完成（1.0 草案，2026-11-19）

`docs/standards/wubi86/{spec-1.0,conformance-1.0,CHANGELOG}.md` + `tools/wubi86-std-{bundle,check}.py`
+ `platforms/macos/tests/test-wubi86-standard.py`（自检 L4 通过、变异能被抓到）。

## 步骤

1. ~~差异清单~~ **不做**（ADR-382）：86 专利已过期、王码无免费数据许可、也不抄其表格；规范只声明"独立制定、
   不宣称与官方一致"，不再产出 `wangma-diff.md`。
2. ~~数据包发布~~ ✅ **已完成**：`make wubi86-package` 生成可复现 zip + `.sha256`，Release 工作流作为 tag 绑定资产
   （缺了会拒绝发布）；站点新增 `site/standards.html`（S-2），首页导航有入口。
3. **扩字覆盖**（M–L，依赖 T-ROOT86）：先 GB2312 二级（+3,008 字），再按需扩到 GB18030 常用子集；
   每次扩字必须重跑 L1–L4 与 `partial` 归因统计，写进 CHANGELOG。
4. ~~第三方可用性验证~~ ✅ **已完成**（S-3）：`tools/lws86-reference-impl.py` 只读规范、不引用判定器，
   重算全码与识别码后 **3,746 / 3,755 逐字一致、0 失败**；暴露并要求修掉两处缺口（R2-note 多键位字根、
   R9e 扩到 4 例），见 ADR-388 与 CHANGELOG。
5. ~~1.0 转正~~ ✅ **已完成**（S-4，2026-11-20）：`spec-1.0.md` 状态改「1.0 正式」，
   `docs/standards/README.md` 与站点登记；同时写明覆盖范围（GB2312 一级）与一级外 27 字 `partial`。

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
