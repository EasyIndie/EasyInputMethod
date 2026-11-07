# 251 — 1.2.0 B1 批（工程收口）：签名 tag、CI 数据、footprint 门禁、站点盖章、延迟分段

- 日期：2026-11-06　｜　批次：B1（见 [`迭代计划-1.2.0`](../迭代计划-1.2.0.md)）　｜　改动：D1/D2/D5/D6/D4/E2
- 原则：本批**不改任何输入行为**，只补门禁与自动化。

## D1 签名 tag（SSH key）

- 用户 2026-11-06 定：**签名用 SSH key**（`~/.ssh/id_ed25519.pub`）。
- 新增 `packaging/git-allowed-signers`（principal = tagger 邮箱 `824219521@qq.com`）。
- 本地仓库配置（`.git/config`，不进版本库）：
  `gpg.format=ssh`、`user.signingkey=~/.ssh/id_ed25519.pub`、`tag.gpgsign=true`、`gpg.ssh.allowedSignersFile=packaging/git-allowed-signers`。
- 实测：`git tag -s tmp && git tag -v tmp` → `Good "git" signature for 824219521@qq.com with ED25519 key`。
- `release.yml` 早就有校验分支，**文件一出现即从"警告"转为"失败"**；文档补进 `docs/更新发布流程.md` 与发布清单。

## D2 CI 数据 bootstrap

- 现象：`test-hanzi-structure-b0.py` 在 CI 一直 skip——CI 不下载 D2（拆字）也不持有 D17（简码）表。
- 处置：
  1. `data/sources/wubi86-level1-codes.tsv` / `-level2-codes.tsv`（自编，CC-BY-SA-4.0，共 7.5 KB）**纳入版本库**（`.gitignore` 加白名单例外）；
  2. `ci.yml` 在离线回归前执行 `./data/sources/fetch-wubi-chaizi.sh`（固定 SHA，校验失败即红）。
- 结果：B0 独立重算在 CI **不再 skip**，后续 B2/B6 的数据改动有自动防线。

## D5 内存硬顶改 footprint

- 现象：`ps rss` 在 macOS 27 计入共享页（同宿主 footprint 33 MiB / rss 95 MiB），`RSS_HARD_MB=96` 贴近误判。
- 处置：`perf-session.sh` 与 `soak-session.sh` 的**绝对硬顶**统一改为 `vmmap` physical footprint
  （`FOOTPRINT_HARD_MB`，默认 40）；rss 仍采样但只作参考，泄漏信号继续看"相对热身段增长"。

## D6 站点版本行自动化

- 现象：`site/index.html` 版本行硬编码 → 1.1.0 发布后 dispatch Pages 部署的还是 1.0.2 页面（报告 250）。
- 处置：
  1. 源文件改为占位符 `{{VERSION}}` / `{{BUILD}}` / `{{SIZE_MB}}`；
  2. 新增 `tools/stamp-site.py`（校验 X.Y.Z、构建号、体积；替换后仍有 `{{…}}` 即失败）；
  3. `pages.yml` 先读**已发布 Release**（tag + appcast 的 `sparkle:version` + ZIP 体积）盖章，再上传 `site-out`；
  4. `test-site-version.py` 重写：源文件不得硬编码版本；盖章结果必须自洽；非法输入必须报错。

## D4 延迟统计分段

- 现象：只统计 `wq nihao xuexi .`，长编码与翻页没有数据。
- 处置：`perf-session.sh` 支持 `SEGMENTS='名|按键;…'`，默认三段 **basic / long-code（`trnt wqiy khk`）/ paging（`wq = = - .`）**，
  JSON 输出加 `segments` 明细；门禁仍只看总稳态 p95。

## E2 久用档

- `soak-session.sh` 支持 `MINUTES=30`（发布候选档）；README 写明档位与 footprint 门禁。

## 验证

- `make verify` PASS（206 产物零网络符号）
- `make macos-offline-tests` **61 文件 / 323 例 PASS**（新增站点盖章 7 例）
- 未换包、未改配置、未触碰用户输入源；`perf/soak` 的实测要等 B2 之后的候选包再做。

## 关联

ADR-307、报告 229/248/250、[`迭代计划-1.2.0`](../迭代计划-1.2.0.md)、`docs/更新发布流程.md`、`tools/macos-probe/README.md`。
