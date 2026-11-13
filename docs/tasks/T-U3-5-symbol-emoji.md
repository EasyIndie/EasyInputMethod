# T-U3-5 符号 / emoji（进行中）

- 状态：进行中（ADR-349）；候选 `1c6eddb` 已装 air，GUI 复验因屏幕锁定 BLOCKED，待解锁后补跑
- 模型建议：pro
- 前置：无
- 目标：提供「⌥S 面板 + 反引号候选前缀」两种符号/emoji 入口，共享全量 Unicode emoji 与中英文搜索数据。
- 步骤：
  1. `data/symbols.tsv`（D23）与 `data/generated/emoji.tsv`（D21/D22 派生）；`fetch-emoji-data.sh` 固定 SHA 下载。
  2. `SymbolCatalog` 懒加载、分类、搜索；`SymbolPickerWindow` 面板（分类 + 搜索 + 表格，双击/回车插入）。
  3. `SymbolComposition`：反引号进入宿主侧候选，分类 → 条目分页；emoji 分类打开面板。
  4. 配置 `hotkey.open_symbols`（默认 `alt+s`）；设置页「快捷键」分组。
  5. `build.sh` 打包 `symbols.tsv` / `emoji.tsv`；回归守数据、搜索、面板与前缀状态。
- 验收：
  - `make verify`、`make macos-offline-tests`、`build.sh --strict`、预览冒烟全绿；
  - 真机：⌥S 打开面板，搜索「笑」「heart」并插入；反引号打开分类，选符号上屏，Esc 取消；
  - 关闭热键后无行为；核心候选排序与简码不变。
- 铁律提醒：零网络（铁律 1）、配置唯一（铁律 3）、数据先登记（铁律 4）、扩展只做数据包（ADR-346）。
- 禁止：运行期联网、引入第三方可执行插件、改变五笔/拼音候选排序、把 `fh` 当前缀。
- 参考：`docs/决策记录.md` ADR-349、`docs/数据来源与许可.md` U3-5 节、报告 274。
