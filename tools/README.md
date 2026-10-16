# tools/

数据生成与开发辅助工具（**不属于运行期核心**）。

计划内容：

| 工具 | 职责 | 阶段 |
|---|---|---|
| `wubi-encoder` | 五笔编码器：字根序列 → 五笔码（键名字/成字字根/合体字/末笔字型识别码） | P1-M1 |
| 码表生成 | 由拆字数据 + 编码器生成单字码表 → `.imedict` | P1-M1 |
| 词组生成 | 由词表 + 词组规则生成词组码（见 `docs/技术方案.md` §7.1） | P1-M1 |
| 词典编译器 | 源数据 → 紧凑二进制（`cedarwood` 双数组 Trie） | P1-M1 |

规则：

- 工具**必须可复现**：同输入产出同输出；
- 生成用到的源数据必须已在 `data/sources.toml` 登记；
- 工具的输出不提交（除非是有意发布的数据包）。

## 五笔教学覆盖审计

`python3 tools/audit-wubi-learning-coverage.py --output platforms/macos/build/learning-coverage-review/coverage.json`只读既有登记码表/词频/教学，输出分型覆盖、输入SHA和优先缺口队列。词频优先层不是实际输入统计；不会修改数据或把部分说明算完整，见报告034与T-MVP-LEARNING-COVERAGE。
