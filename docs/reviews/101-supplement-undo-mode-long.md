# 101 补测 — undo / 四状态与模式 / 长组合（候选 `07bbb2f`）

2026-10-19，A 机，候选仍是已装 `07bbb2f`（执行 `681fb1c8…`）。用 ADR-215 私有数据根 + 自建 TextEdit 文档，
每批发键前执行 `tools/macos-probe/guard-focus.sh TextEdit`（焦点闸门，报告 099 事故后的铁律）。

| 项 | 结果 |
|---|---|
| `⌘Z` 撤销 | **PASS**：`nihao`+空格 → 「你好」，`⌘Z` → 文档回空 |
| 四状态 + 模式循环（菜单点击） | **PASS**：简/繁、中/英标点、全/半角往返；模式 混输→五笔→拼音→混输，每次回读私有 config（`chinese_variant`、`mode` 同步） |
| 长组合 | **PASS（分级记录）**：8 字母 `zhongguo` → 组合+候选窗口（输入码 `zhongguo`）；14/20/23 字母 → 保留 marked text、无候选窗口、**不崩溃不误上屏**，Esc 干净取消；无候选时空格按设计原样上屏 |
| 还原 | 输入源 ABC、`LAMPYRIS_SUPPORT_DIR` 已清、TextEdit 已退出 |

## 取证注意（发现一处流程风险，已记录）

- `typekeys a b c` 会以**空格连接**参数逐字发送（等于 `a␣b␣c`），做长组合必须用**单个参数** `typekeys zhongguorenmin`；
  本轮第一次长组合测试因此误把每个字母后都带了空格（已作废重测）。
- `launchctl unsetenv` 只影响**之后**启动的宿主；本轮先 unset 再 kill，导致随后新起的宿主用回真实数据根，
  真实 `user-dictionary.tsv` 在补测期间由 2242B 变为 3312B/202 行（SHA `d6054fc7…` → `3a6871a5…`）。
  无法区分是用户日常学习还是这次窗口期写入；学习数据只增不减，**未擅自回滚**，如实记录。
  正确顺序：**先 kill 宿主 → 再 unsetenv → 再让宿主在需要时以真实数据根启动**。
