# IT-22 自动覆盖映射与精简清单（报告 230）

> 目的：把 65 项的 IT-22 走查压到**真正需要人眼/人耳/真实设备**的那 18 项。
> 本文件是 `docs/tasks/T-ITER-22.md` 的配套映射；两者不一致时以本文件的映射为准，并修掉腐烂。
> 由 `platforms/macos/tests/test-acceptance-map.py` 在离线回归里校验：**这里引用的命令与文件必须真实存在**。

## 0. 一句话

- **自动**：`make verify`（13s）+ `make macos-offline-tests`（55 文件/293 例，6 并发 ~34s）+ 一键探针 `make macos-acceptance-full`（约 5 分钟）。
- **人工**：只剩 **17 项 + 1 项日常**——A 档每次换包 12 项（~12 分钟）、B 档每版一次 5 项（安装类 ~10 分钟）、C 档 1 项并入日常（11.1）。

## 1. 自动覆盖映射

| IT-22 条目 | 覆盖手段 | 怎么跑 |
|---|---|---|
| 1.1–1.3、1.7–1.12 上屏/标点/全角/简繁/模式/中英 | 热键探针 + 质量样本 | `make macos-auto-acceptance`（7 项）、`tools/macos-probe/quality-samples.sh`（13 项） |
| 1.4 翻页、1.5 方向键选择 | 组合导航单测 + 质量样本「翻页键不破坏输入」 | `make test`、`quality-samples.sh` |
| 2.1 长组合不丢字 | 质量样本「长文本不丢字」 | `quality-samples.sh` |
| 2.2–2.6 退格/Esc/Home/End/Delete/Tab | 核心与 FFI 单测（ADR-164） | `make test`（`ime-core`/`ime-ffi`） |
| 2.4 撤销 | 质量样本「撤销回到空态」 | `quality-samples.sh` |
| 2.8 失焦、2.9 切输入源 | 质量样本「失焦再回来不丢字」「切输入源不丢字」 | `quality-samples.sh` |
| 3.1–3.2 TextEdit / Safari | 客户端矩阵（AX 回读） | `client-matrix.sh` |
| 4.1–4.2 亮/暗、4.5 多页、4.6 边缘、4.7 HUD | 候选/光标几何单测 + 离屏快照对比度 | `make test`、`make macos-ui-contrast` |
| 4.3 长候选 | `test-candidate-presentation.py`（long 场景） | `make macos-offline-tests` |
| 5.1–5.4、5.6 设置面板结构与生效 | `test-settings-presentation.py` + 配置单测 | `make macos-offline-tests` |
| 6.1–6.5 词库增删/导入导出/反查 | `test-wubi-learning.py`（14 例）+ `ime-core` 单测 | `make macos-offline-tests` |
| 7.1–7.3 关于/复制诊断/反馈链接 | `test-tools-presentation.py`（含 link-fallback/link-success） | `make macos-offline-tests` |
| 9.4 VoiceOver 反例条件 | 已由报告 215 §1 条件 B 覆盖，无需重跑 | — |
| 10.1–10.2 多屏落点/缩放 | `multi-display.sh` + `test-caret-placement.py` | `make macos-multi-display` |
| 11.3 内存趋势 | 久用 + 内存门禁 | `make macos-soak`、`make macos-memory-gate` |
| 简码 25 键位首选 | 数据校验 + 评测 | `python3 tools/check-level1-codes.py`、`make eval-candidates` |

## 2. 人工必做（17 项 + 1 项日常）

### A 档：每次换包（12 项，约 12 分钟）

| # | 条目 | 为什么不能自动 | 判定 |
|---|---|---|---|
| A1 | 1.6 鼠标点选候选 | 需要真实鼠标轨迹 | 点哪上哪 |
| A2 | 2.7 CapsLock 开关 | 系统级状态，探针发不出真 CapsLock 语义 | 不出错字 |
| A3 | 2.10 睡眠→唤醒→输入 | 需要真实休眠 | 不重启即可输入 |
| A4 | 3.3 Chrome 文本框 | Chrome 侧回读不可靠（BLOCKED 已记账） | 上屏正常 |
| A5 | 3.4 VS Code 编辑器 | 同上（编辑器焦点差异） | 上屏正常 |
| A6 | 3.5 Terminal | 自动化会往用户 shell 打字，已从矩阵移除 | 上屏正常 |
| A7 | 3.6 其它常用 App | 无法枚举 | 上屏正常 |
| A8 | 4.4 悬停候选视觉 | 视觉判断 | 悬停态可辨 |
| A9 | 5.5 设置面板纯键盘操作 | 依赖系统「键盘导航」开关 | 可达、焦点可见 |
| A10 | 9.1–9.3 VoiceOver 播报/浏览/设置面板 | 需要人耳 | 播报正确、焦点不被夺 |
| A11 | 10.3 Space 切换后输入 | 需要真实切换 Space | 候选跟随 |
| A12 | 10.4 全屏 App 内输入 | 需要真实全屏 | 候选在屏内 |
| A13 | 11.2 放置 10 秒后首键 | 主观手感，配合 `perf-session` 数字判读 | 首键不卡 |

### B 档：每版一次（5 项，约 10 分钟，需换包授权）

| # | 条目 | 说明 |
|---|---|---|
| B1 | 8.1 安装提示 | 用该版 DMG/ZIP 实装 |
| B2 | 8.2 检查更新窗口 | 标题显示当前版本 |
| B3 | 8.3 卸载（保留数据） | `config.toml`/词库保留、`uninstalled/`+`updates/` 清掉 |
| B4 | 8.4 重装后配置与词库接上 | 无需重设 |
| B5 | 8.5 注销重登录无残留 | 输入法菜单/系统设置干净 |

### C 档：可并入日常使用（不单独安排）

- 11.1「打一段 50 字中英混排」本来就是日常行为，发现问题直接记本表，不必专项排时间。

## 3. 推荐执行顺序（一次换包内）

```sh
make verify                      # 13s，门禁
make macos-offline-tests         # ~34s，55 文件/293 例（JOBS 默认可并行）
make macos-acceptance-full       # ~5 分钟：preflight → 热键/上屏 → 客户端 → 质量样本 → 性能/网络
# 三个探针脚本都带 trap：结束时自动关闭自己开的 TextEdit 文档/浏览器标签/Xcode 窗口（报告231）
# 然后按 A 档 13 项人工走查（约 12 分钟），B 档只在发版时做
```

## 4. 与旧清单的差异（为什么能砍掉 47 项）

1. **同一件事此前被写了三遍**：`quality-samples.sh`（16 项）、`acceptance-auto.sh`（8 项）、IT-22 手工表（12 项重叠）。报告 230 之后两份脚本**按行为分工**：`quality-samples.sh` 断言打字产物（13 项），`acceptance-auto.sh` 断言热键状态语义（7 项），重复项已删并由 `test-acceptance-map.py` 守住不再回流。
2. **离屏单测已经断言了 GUI 结构**：候选/设置/关于/学习的布局与文案由 `test-*-presentation.py` 断言，手工"看一眼分组是否连续"不再重复。
3. **几何/落点类**（多屏、边缘、翻页位置）已有 `CaretPlacement` 与离屏快照对比度自动判定（ADR-301、报告 197）。
4. **安装类**从"每次走查"降为"每版一次"，因为它们只在换包时才有意义。

## 5. 防腐烂

- `platforms/macos/tests/test-acceptance-map.py` 校验本文件引用的命令/文件存在；
- 任何 IT-22 条目若判断"现在不能自动了"，必须先改本文件再改清单，不允许只改一边。
