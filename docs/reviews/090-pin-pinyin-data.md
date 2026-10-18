# 090 — 固定 pinyin-data 到 commit，修复 CI 的 SHA 漂移

2026-10-18。CI 的「Reproduce licensed pinyin data」因上游 `mozillazg/pinyin-data` 的 `master`
变更而失败：期望 `621f8ca9…`，实际 `7365b877…`。

## 原因

- 我们的 `D5` 数据实际对应 **Unicode 17.0.0**（上游 commit `923b108d`，2026-02-23），
  但下载脚本指向 `master`；上游在 2026-10-18 更新到 **Unicode 18.0.0**（commit `9e5e9bd`，+237 行改动），
  同一 URL 内容变化导致 SHA 校验失败。
- 仓库里生成的 `pinyin-chars.tsv` / `pinyin-core.tsv` 仍是 17.0.0 的结果。

## 修复

把 D5 的下载地址从 `master` 改为 **固定 commit `923b108d` 的 raw 文件**，SHA-256 保持
`621f8ca9eff8519f47e2b17b564fd318161e13bca07eea8c8e04993cd5d3b52e` 不变：

- `data/sources/fetch-pinyin-data.sh`：URL + 注释
- `data/sources.toml`：`url` 与 `notes`（标明固定 commit，而非 master）
- `docs/数据来源与许可.md`：D5 行与下载说明

不升级到 Unicode 18.0.0：本轮只修 CI 稳定性，数据/行为零变化；升级需要单独评估 237 处读音修正。

## 验证

- 按 CI 步骤重跑：`fetch-*` → `generate_pinyin` → `prepare-pinyin-core.py` →
  `git diff --exit-code data/generated/{pinyin-chars,pinyin-core,pinyin-core-report}`：**无 diff**。
- `make verify` 全绿（182 产物隐私断言）。
- 许可未变（MIT），未新增数据文件；仅改变下载 URL 的不可变性。
