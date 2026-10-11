# MVP-05：macOS 实机 DoD 验收矩阵（可直接填写）

- **状态**：⏸ 待用户实机验收（唯一剩余 A 类关门项）
- **目的**：逐项记录「系统/机型 + 应用版本 + 步骤 + 结果 + 证据」，据此关闭 `docs/技术方案.md` §12 / P1-M4 验收。
- **关联**：报告 [006](../reviews/006-macos-mvp-gap-review.md)（MVP-05）、[发布清单](../macos-release-checklist.md)、[发布说明](../发布说明.md)。
- **说明**：本文件是 13 项矩阵的**唯一填写处**；发布清单只保留指针，避免两处维护。

## 0. 填写约定

- 「结果」二选一勾选：`通过` / `不通过`；不通过必须在「证据 / 备注」写明**现象 + 最小复现**。
- 「证据」可填：命令输出摘要、截图/录屏路径、日志片段（`log show --last 5m --predicate 'eventMessage CONTAINS "萤火虫"'`）。
- 亮色与深色外观若表现不同，**分别记录**；未注明即视为当前外观通过。
- 验收期间保持**最新构建**（包内 `Contents/Resources/SOURCE-COMMIT` = 下表环境里的 commit）。

## 1. 验收环境（先填）

| 项 | 值 |
|---|---|
| 构建 commit | `c4c4b20`（`cat ~/Library/Input\ Methods/Lampyris.app/Contents/Resources/SOURCE-COMMIT`） |
| macOS 版本 / 机型 | ________（`sw_vers`；`uname -m`） |
| 外观 | ☐ 浅色　☐ 深色 |
| 安装形态 | `~/Library/Input Methods/Lampyris.app`（ad-hoc） |
| 验收人 / 日期 | ________ / ________ |

## 2. DoD 矩阵（13 项）

> **自动化已覆盖项**（标“自动”）由 `platforms/macos/tests/run-imk-acceptance.sh` 连跑两遍、结果一致得出；其余项待人工。

| # | 项目 | 应用 | 操作步骤 | 预期结果 | 结果 | 证据 / 备注 |
|---|---|---|---|---|---|---|
| 1 | 五笔基础 | TextEdit | 输入 `wq` → 空格或数字选「你」 | 上屏「你」 | ✅ 通过（自动） | `wq`+空格/数字1 → 你（两轮一致） |
| 2 | 拼音兜底 | TextEdit | 输入 `nihao` → 选「你好」 | 上屏「你好」 | ✅ 通过（自动） | `nihao`+空格 → 你好（两轮一致） |
| 3 | 混输来源标注 | TextEdit | 输入产生多来源候选 | 候选后标「五笔／拼」 | ✅ 通过（自动） | 输入 `shi` → 候选含「五笔」「拼」 |
| 4 | 三模式持久化 | TextEdit | 菜单切「仅五笔」→ 注销重登 → 再输入 | 仍为五笔 | ✅ 通过（自动，含重启宿主） | `ctrl+shift+m` → `mode = "wubi"` 已写盘；重启后可输入且状态徽标「五笔」 |
| 5 | 配置实时生效 | TextEdit | 输入中外部改 `candidate.count` | 候选数**无需按键**即时变 | ✅ 通过（自动） | count 5→3 未按键即变（两轮一致） |
| 6 | 配置错误提示 | TextEdit | 写坏 `config.toml` | 照常输入 + 提示行号，同一错误仅一次 | ✅ 通过（自动，opt-in） | 弹窗含「第 1 行」；同一错误不重复；坏配置下仍可输入 |
| 7 | 用户词库 | TextEdit（菜单/面板） | 新增词条 → 输入 → 注销重登 | 词条与频次保留 | ◐ 逻辑自动（preview 冒烟，FFI）<br>☐ 面板 GUI 待人工 | `ime_session_dictionary_add` → 输入即上屏；跨会话持久化由 `ime-dict` 单测覆盖 |
| 8 | 导入 / 导出 | TextEdit（面板「词库」） | 导出 → 清空 → 导入 | 词条恢复 | ◐ 逻辑自动（preview 冒烟，FFI）<br>☐ 面板 GUI 待人工 | `export`→`import` 往返 + 坏文件拒绝（冒烟断言） |
| 9 | 拼音反查 | TextEdit（面板「词库」） | 反查「你好」 | 得 `ni hao` | ◐ 逻辑自动（preview 冒烟，FFI）<br>☐ 面板 GUI 待人工 | `ime_session_reverse_lookup("你好") == "ni hao"`（冒烟断言） |
| 10 | 五应用稳定 | TextEdit / Safari / VS Code / 微信 / Terminal | 各应用长文本、光标定位、`Cmd+Z` | 无错位/残留，撤销正常 | ☐ 通过<br>☐ 不通过 | |
| 11 | 性能 / 内存 | 宿主进程 | 长时间输入；`ps` / `vmmap` | 按键 <16ms、常驻 ≤30MB | ✅ 通过（自动） | 物理足迹 ~17.5MB ≤30MB；引擎按键 p95 **1.2ms** / max ~4ms（`run-perf.sh`） |
| 12 | 零外联采样 | 宿主进程 | 持续输入期间采样 `lsof` | 无网络连接 | ✅ 通过（自动，空闲 + 输入期间） | 空闲 6 次 + 输入期间 8 次采样，均 0 连接 |
| 13 | 亮 / 暗主题 | 系统外观 | 切浅/深色，看菜单与候选窗 | 清晰可读 | ☐ 通过<br>☐ 不通过 | 视觉项 |

## 2.1 自动化入口（可复现）

```sh
# 前提：终端 App 已获「辅助功能」；萤火虫已安装并启用。
./platforms/macos/tests/run-imk-acceptance.sh                     # 主用例（14 项）
IMK_ACCEPTANCE_PERF=1    ./platforms/macos/tests/run-imk-acceptance.sh  # 加引擎按键时延（run-perf.sh，较慢）
IMK_ACCEPTANCE_RESTART=1 ./platforms/macos/tests/run-imk-acceptance.sh  # 加「重启宿主后仍生效」
IMK_ACCEPTANCE_CONFIG_ERROR=1 ./platforms/macos/tests/run-imk-acceptance.sh  # 加配置错误弹窗（模态，一次性）
```

- 主用例（连跑两遍均 `SUMMARY pass=14 fail=0`）：①五笔 ②拼音 ③来源标注 ⑤配置实时 ⑫输入期间零外联 ⑪内存 + 状态徽标 / 数字选字 / Esc / 模式写盘。
- 全选项（`PERF=1 RESTART=1`，`pass=16 fail=0`）：额外 **④ 重启后仍生效** 与 **⑪ 引擎按键 p95 <16ms**。
- 配置错误弹窗（`IMK_ACCEPTANCE_CONFIG_ERROR=1`）：弹窗文本含行号、同一错误不重复、坏配置下仍可输入（模态，建议只跑一次）。
- 脚本只在新开的空 TextEdit 文档里输入；会临时改 `config.toml` 并结束时**自动还原**；`RESTART` 会重启宿主、`CONFIG_ERROR` 为模态。
- 脚本新建的 TextEdit 文档会在退出时**自动关闭**（`trap` 里仅关自己的文档，不动你原本打开的），不残留窗口。
- ⑦⑧⑨ 的**逻辑**已由 `dev-preview.sh --smoke-test`（FFI 级：增词 / 导出 / 导入 / 反查 / 坏文件拒绝）覆盖；**面板 GUI 点击**仍建议人工过一遍。
- **不覆盖（人工/视觉）**：⑩ 五应用 + `Cmd+Z`、⑬ 亮/暗主题、⑦⑧⑨ 的面板按钮点击。
  → **逐步操作手册**（含第二台 Mac 复现）：[人工验收与多机复现](../人工验收与多机复现.md)。

## 3. 证据获取命令

```sh
# 宿主进程
pid=$(pgrep -x Lampyris); echo "pid=$pid"

# 内存（KB；常驻 = RSS，排除 mmap）
ps -o rss=,vsz= -p "$pid"
vmmap "$pid" | grep -i 'physical footprint'

# 零外联：应无任何输出
lsof -nP -a -p "$pid" -i

# 引擎按键时延（引擎级；不含 IMK 渲染）：应 p95 < 16ms
./platforms/macos/tests/run-perf.sh

# 配置与数据
cat ~/Library/Application\ Support/Lampyris/config.toml
```

- 菜单状态：输入法菜单各项（输入模式 / 中·英 / 全·半角 / 中·英标点 / 简·繁，含快捷键）。
- 反馈 / 版本信息：输入法菜单「版本信息」（独立小窗：诊断 + 「复制信息」/「反馈问题」/「反馈漏洞」按钮，点击才跳转）。
- 异常状态行仅在出错时出现（配置错误 / 数据文件错误 / 用户词库读写失败）。

## 4. 结论

- 通过项数：____ / 13
- 阻塞问题（附最小复现）：____________________
- 结论：☐ 通过，可关闭 MVP-05　☐ 不通过，需修复后重测
- 验收人签名 / 日期：____________________

## 5. 验收后收尾

- [ ] 将本表结果归入报告 005，勾选 `ROADMAP.md` P1-M4 验收项。
- [ ] 记录最终「版本说明 / 已验环境 / 已知限制」入 [发布说明](../发布说明.md)（附件 SHA 对应最终源码）。
- [ ] 移除临时输入源与用户域应用，**保留配置与词库**，日常继续用 `make macos-preview`。

> **不在本表内**：P1-M5「独立第三方按包内说明复现并核验零外联」需外部人员；MVP-14（其他 macOS 版本 / Icon Composer 分层图标）需机器 B。
