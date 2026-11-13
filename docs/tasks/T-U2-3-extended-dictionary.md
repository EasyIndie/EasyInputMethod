# T-U2-3 可选扩展词库（进行中）

- 状态：进行中（ADR-348）
- 模型建议：pro（涉及数据生成、宿主会话重载与内存门禁）
- 前置：无
- 目标：新增默认关闭的 `dict.extended` 开关，开启时整体装载随包扩展码表（全量五笔词组 + 前 50k 拼音词），
  关闭时与核心档完全一致；第三方词库继续走本地用户词库导入。
- 步骤：
  1. 生成 `data/generated/wubi86-extended.tsv` 与 `data/generated/pinyin-extended.tsv`，登记 `data/sources.toml` 与许可文档。
  2. Schema 增加 `dict.extended`（默认 `false`），设置页「五笔与拼音」分组渲染。
  3. `InputController.makeSession()` 按开关选择核心/扩展两份表；文件缺失回退核心档并显示错误。
  4. 配置变化时在空闲按键重建会话；组合中延迟，不丢编码。
  5. `build.sh` 打包两份扩展文件；回归守体积、覆盖、报告 SHA。
- 验收：
  - `make verify`、`make macos-offline-tests`、`build.sh --strict` 全绿；
  - 扩展档真机：候选出现核心表没有的词组；关闭后恢复核心表；切换不打断组合；
  - `LIMIT_MB=64 ./tools/macos-probe/memory-gate.sh` 在扩展档 PASS（核心档仍 24 MiB）。
- 铁律提醒：零网络（铁律 1）、配置唯一（铁律 3）、数据先登记（铁律 4）、扩展只做数据包（ADR-346）。
- 禁止：下载第三方词库、实现可执行插件、把全量 341k 拼音词表默认装载、改动核心排序规则。
- 参考：`docs/决策记录.md` ADR-348、`docs/数据来源与许可.md` U2-3 节、报告 273。
