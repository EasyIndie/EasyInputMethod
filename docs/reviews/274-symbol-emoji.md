# 274 — 符号 / emoji 输入（U3-5，ADR-349）

> 2026-11-14，air（arm64 / macOS 27.2）。最终候选 `d779186`（PR #291，ZIP `02fec3fe…`、源码 `936ef4f3…`、
> 执行 `a184fc1e…`）已装 air；⌥S 面板、反引号前缀、emoji 插入、零外联均 PASS，核心样本 29/30 PASS（失焦项因 TextEdit AppleScript 挂起 BLOCKED）。
> 中途两次因屏幕锁定导致 GUI 项 BLOCKED，已解锁后重跑。

## 1. 做了什么

- **⌥S 面板**：新增 `hotkey.open_symbols`（默认 `alt+s`）。非模态、非激活面板 = 分类下拉 + 搜索 + 虚拟化表格；
  客户端焦点不丢，键盘事件由输入法控制器转发（字符进搜索、↑/↓ 选行、回车插入、Esc 关闭、Cmd+V 粘贴中文）；
  双击 / 回车插入；面板关闭时零行为。
- **反引号前缀**：中文、非组合状态下按 `` ` `` 进入宿主侧符号候选：标点 / 数学 / 货币 / 箭头 / 序号 / 其他 / emoji。
  数字、方向键、回车选择；`-`/`=`（及 `[`/`]`、`,`/`.`）翻页；Esc 取消；选 emoji 打开面板。
- **数据**：
  - `data/symbols.tsv`（D23）：项目自编 277 个符号，六个分类，中英文搜索词。
  - `data/generated/emoji.tsv`（D5/D21/D22 派生）：3,781 个 fully-qualified emoji，9 个分组，全部有中文名、
    英文名、中英文搜索词与拼音搜索词（`xiao` → 笑）；CLDR 未收录的肤色/发型/旗帜组合由项目规则回退配名，**缺中文名 0**。
  - `data/sources/fetch-emoji-data.sh` 固定 Unicode 16.0 / CLDR release-47 版本与 SHA；运行期不联网。
- **许可**：符号表 CC-BY-SA-4.0；Unicode/CLDR 数据为 Unicode License V3（MIT 类，与 GPL-3 兼容）；
  原始文件下载不入库，派生 TSV 随包。
- **架构**：面板与前缀共用一个目录；前缀完全在宿主侧，不进入核心引擎，不改变候选排序与简码。

## 2. 为什么不用 `fh`

用户最初提议 `fh` 作前缀；实测五笔核心表中 `fh` 是「直」的完整码，且有 **304 条**以 `fh` 开头。
用它会让这些字打不出来，因此改为不占用五笔/拼音键位的反引号 `` ` ``。

## 3. 验证

| 项 | 结果 |
|---|---|
| `make verify` | PASS（504 产物零网络符号） |
| `make macos-offline-tests` | **65 文件 / 342 例 PASS**（新增 5 例） |
| `build.sh --strict` | PASS（`symbols.tsv` / `emoji.tsv` 已进 `Contents/Resources`） |
| 预览冒烟 | PASS（设置项数量 33） |
| `test-symbol-emoji-data.py` | 4 例 PASS：分类/覆盖/搜索词/许可/SHA |
| `test-symbol-picker.py` | PASS：目录、中文/英文/拼音搜索、面板分类、插入回调、前缀状态 |
| 安装 | 候选 `d779186` 已装 air：执行 `a184fc1e…`、1.3.0/43、universal、公证；`emoji.tsv`（980 KB）/`symbols.tsv` 在 Resources |
| 真机 ⌥S | PASS：`opt+s` 打开面板；搜索 `xiao`→205 项、`heart`→159 项、`grinning`→10 项；分别插入 `≤`、`♥`、`😀` 到 TextEdit |
| 真机反引号前缀 | PASS：`` `11 `` → `，`；`` `42 `` → `→`；`` `7 `` 打开 emoji 面板；Esc 关闭面板/取消前缀 |
| 键盘路由 | PASS：非激活面板下，客户端保持焦点；字符进搜索、↑/↓ 选行、回车插入、Esc 关闭 |
| 零外联 | PASS：面板打开并搜索时 `lsof -p <host> -i` 0 条 TCP/UDP |
| 核心样本回归 | **29/30 PASS**；第 30 项「失焦再回来不丢字」BLOCKED：`quality-samples.sh` 在 TextEdit `make new document` 处挂起，终止后已清理/还原私有根 |
| 用户数据 | 面板测试走真实数据根：词库 1838→1862 行（真实键入学习）；`config.toml` 被质量脚本恢复取值后重写（SHA `3aea2bca…`→`888ed018…`，`mode=wubi`/中文标点/半角/简体不变）；练习 `2512f4…` 未变 |
| 安装备份 | `updates/install-backup-20261114T015521Z/`（前一候选）、`…T015522Z/` |

## 4. 已知限制

- 中文状态下不能直接输入反引号（切英文可输入）。
- 组合中按 ⌥S 会先提交当前候选再打开面板。
- 前缀模式只做分类浏览；搜索在面板内完成。
- emoji 渲染依赖系统字体；肤色组合使用生成的中文名（如「握手（浅肤色、中等肤色）」）。
- 面板首次打开才读取 emoji TSV（约 980 KB / 3,781 行），不进入核心常驻内存。
- 面板是非激活窗口，键盘请求由当前输入法控制器转发；切到英文输入源或关闭输入法时，面板需用鼠标或 Esc 操作。

## 5. 真机复验记录（已完成）

1. ⌥S 打开面板；分类、搜索（`xiao`/`heart`/`grinning`）、回车插入均 PASS。
2. 反引号分类/翻页/插入 PASS；`` `7 `` 打开 emoji 面板；Esc 关闭面板与前缀。
3. 零外联 PASS；核心样本 29/30 PASS（失焦项因 TextEdit AppleScript 挂起 BLOCKED）。
4. 未单独测试「关闭 `hotkey.open_symbols`」的热键禁用路径；代码只受配置开关约束。
