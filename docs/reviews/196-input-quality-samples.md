# 196 固定输入质量样本集（已执行）

## 1. 用途

MVP 标准要求「固定典型输入与质量样本集逐项通过」。此前验收是零散断言（报告190-192），换包后无法逐条复跑；现在固化成 `tools/macos-probe/quality-samples.sh` 的一张表，一条命令跑完并逐项 PASS/FAIL。

## 2. 结果（0.1.13 / build 21，执行 `c3b533e4…`，air）

`./tools/macos-probe/quality-samples.sh` → **16/16 PASS**（约 4 分钟）

| 分组 | 用例 | 按键 | 实得 |
|---|---|---|---|
| 核心输入 | 五笔四码自动上屏 | `wqiy` | 你 |
| | 五笔一级简码 | `r ` | 的 |
| | 混输拼音兜底（两字） | `nihao ` | 你好 |
| | 全拼双字词 | `zhongguo ` | 中国 |
| | 拼音长词 | `zhonghuarenmingongheguo ` | 中华人民共和国 |
| 标点与形态 | 中文句号 / 逗号 | `nihao .` / `nihao ,` | 你好。 / 你好， |
| | 成对引号交替 | `';'` | ‘’ |
| | 全角往返 | `opt+f;1;opt+f;1` | １1 |
| | 简繁往返 | `opt+t;xuexi ;opt+t;xuexi ` | 學習学习 |
| 中英与健壮性 | 单 Shift 英文直通 | `shiftc;abc` | abc |
| | 翻页不破坏输入 | `nihao ,,,` | 你好，，， |
| | 撤销回空态 | `wqiy;cmd+z` | （空） |
| | 长文本连续输入 | 5 组词 + 五笔 | 你好×4 + 你 |
| 切换与焦点 | 切输入源不丢字 | 萤火虫五笔 → ABC 英文 → 切回拼音 | `你abc` + `你好` |
| | 失焦再回来不丢字 | 提交后切 Safari 再回来 | 你好 |

## 3. 重要发现：测试窗口对长拼音不可靠（已改用真实客户端）

- 在**探针自建窗口**里输入 `zhonghua `、`zhonghuarenmingongheguo ` 会得到截断的裸 ASCII（`zhonghu`、`zhonghua`），一度像产品缺陷。
- 同样的按键在**文本编辑**里完全正确（`中华`、`中华人民共和国`）。
- 结论：本脚本改为在 TextEdit 里键入 + AX 回读；探针窗口只用于延迟测量（`--self-post`）与短码用例。这条已写进 `tools/macos-probe/README.md`。

## 4. 脚本设计要点

- 自带前置检查（`acceptance-preflight.sh`，退出码 78 = SKIP）与中文态归位（否则上一轮 Shift 会把后续用例打成英文）。
- 每条用例都先清空文本、`guard-focus` 确认前台，再按 250/800ms 节奏落键——慢节奏是为了避免 IME 合并输入。
- 断言用谓词（`exact/endswith/contains/ascii/unicode/empty`），避免把候选排序差异写成假失败；放宽判定必须写明理由。
- **切源后要新建文档**：用 TIS 把当前源切回萤火虫后，已开文档的输入上下文不会立即跟随，新建文档才会取到当前源；这也是"切输入源后打不出中文"这类误报的根因。
- 脚本里含中文的字符串紧跟变量时必须写 `${var}`：`$var，` 会被 bash 当成变量名的一部分，`set -u` 下直接报 `unbound variable`。

## 5. 同一构建的完整回归（同日复跑）

`make macos-auto-acceptance`（`ROUNDS=10`）在 0.1.13 上全绿：热键/上屏 8 项、客户端 5/5、160 键 **p50 1.48 ms / p95 6.99 ms**、稳态 5.5 MiB、0 条 TCP/UDP。
