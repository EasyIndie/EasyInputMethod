# HANDOFF — 当前状态

## 0. 元信息

- 更新：2026-10-18 / pi（deepseek-flash）· **交接给 B 设备做重启后的实机验收**
- 分支：`main` @ `8f14754`（已推送，工作树干净；无其它本地/远程分支、无额外工作树）
- 阶段：**新包已出（源码 `6494eab`，执行 SHA `8984c223…`）**，A 已核验但**未安装**；B 待升级（现在还是 `a234ef31…`）；MVP 发布门禁未全部关闭
- 最近验证：`make verify` 全绿（212 产物隐私断言）
- 交接：`make handoff SCENARIO=compact|session|agent|device PROMPT=1` 采集状态并出提示词骨架（流程见 `.agents/skills/update-handoff/SKILL.md`、模板见 `docs/交接提示词模板.md`）；CI `check` + `macOS Acceptance Package` 对 `6494eab` 均通过（run `39088753850`，出包 artifact `Lampyris-macos-acceptance-6494eab746949fc89282d13f38b194bbd0c9eeae`）

## 1. 安装与数据

| 设备 | 系统 | 已装包 | 状态 |
|---|---|---|---|
| A（本机 `bot`，Intel / macOS 13.7.8） | x86_64 | `a234ef31…`（**旧**） | 报告 071 验收通过；`config` SHA `907998e6…`（显式 `mode=wubi`、`full_width=true`）、输入源已还原 ABC；**未做全新安装** |
| B（`joker`，arm64 / macOS 27） | arm64 | `a234ef31…`（**旧**） | 报告 070 验收通过；`config` 里是报告 068 时代写死的 8 项显式 `ctrl+shift*`、词库 496 行；**待升级到 `6494eab`** |

- 新包（A 上已下载核验，`packaging/out/` 被 gitignore，不入库）：
  `packaging/out/clean-install/candidate-80z8RZ/extracted/Lampyris-0.1.0-universal/Lampyris.app`
  zip `0325ef9d…`、执行 SHA `8984c223…`、`spctl` = Notarized Developer ID、`stapler validate` 通过。
  B 上可从 CI 重新取：`gh run download 39088753850 -n Lampyris-macos-acceptance-6494eab746949fc89282d13f38b194bbd0c9eeae`。
- B 的旧 `config.toml` 是**显式** `ctrl+shift*`：不清理就永远看不到新默认值，所以 B 必须先 `--purge-data` 全新安装（报告 076）。

## 2. 本轮完成（`a234ef31` 之后合入的改动）

| 提交 | 内容 | 报告 |
|---|---|---|
| `2a863e1` | 关于页「反馈问题」下拉按固有尺寸收窄、两按钮按行中心对齐（macOS 13 上原来宽 157pt、错位 4pt） | 072 |
| `7b3a49d` | 候选窗去掉多余的 22pt 底部预留（无 hint 时 74→64pt，上下留白 8/8） | 073 |
| `c337a89` | `make macos-ui-snapshots`（离屏 UI 截图，缓存后 5s）+ 组合键「事件必须晚于最近修饰键变化」的防误判 | 074 |
| `7e2edc7` | **默认快捷键改 Option 语义前缀**（ADR-209）：`⌥M` 模式 / `⇧` 中英 / `⌥Space` 全半角 / `⌥P` 标点 / `⌥T` 简繁 / `⌥L` 学习区 / `⌥,` 设置 / `⌥A` 关于 | 075 |
| `4a48443` | `uninstall.sh --purge-data`：旧包与旧 config/词库移入 `uninstalled/`（移动不删除） | 076 |
| `8f14754` | 不注销验收三档（快照 / 隔离实窗 / 已装包）+ `scripts/clean-install.sh` / `make macos-clean-install` | 077 |

## 3. 当前未决

- **B 机全新安装与重启后验收**（本次交接的主任务，见 §4）。
- **A 机同样待全新安装**（本轮没做）：A 的 `config.toml` 仍是显式 `mode=wubi`、`full_width=true`，看不到新默认值。
- **发布门禁（均未关闭）**：I0 安全（IT-01…03）／I1 可靠性／I2 体验／I3 性能与兼容（IT-12/14/23）／I4 分发（IT-13 dry_run、IT-15 第三方复现、tag/Release）。
- **A 机遗留差异**（报告 071/073）：D2 = macOS 13 上设置面板首次打开落在「候选」分区（B 上是「输入」，需在 macOS 27 复核是否仅旧系统）；D3 = 紧随 AX 点击工具栏后点「关于」有一次未出窗（未稳定复现）。
- **翻页组视觉空隙**（报告 073）：上一页/页码/下一页之间 4pt frame + 24pt 点击区 → 视觉约 17pt，偏松；收紧需改 ADR-183 的点击区契约，待用户决定。
- **A 的 Swift 5.8.1 编译不了 `tools-presentation.swift`/`candidate-presentation.swift`**（`LocalAcceptanceEvidence` 异构字典字面量）：macOS 13 上的这部分离线断言只在 CI 跑；建议单开一张卡修兼容性。
- **正式报告**：`platforms/macos/build/final-menu-abdb83f/formal-report.json` 仍是旧包 `abdb83f` 的 1 PASS/22 BLOCKED。

## 4. 下一步：B 机重启后的全新安装 + 验收

> 顺序不能颠倒：**先移除输入源、再重启**，重启回来后再卸载/安装（守则 2：不要在同一登录里热替换 bundle）。

### 4.1 重启前（用户手动）

1. 切到 **ABC**；
2. 系统设置 → 键盘 → 文字输入 → 移除「萤火虫」。

### 4.2 重启后（agent 执行，逐条记录，失败即停）

```sh
cd ~/Documents/EasyInputMethod
git fetch origin && git checkout main && git pull --ff-only      # 到 8f14754
make -C tools/macos-probe                                        # arm64 探针
# 取包（若本地没有）：gh run download 39088753850 -n Lampyris-macos-acceptance-6494eab746949fc89282d13f38b194bbd0c9eeae -D packaging/out/clean-install
shasum -a 256 packaging/out/clean-install/*/Lampyris-0.1.0-universal.zip   # 期望 0325ef9d…
make macos-clean-install APP=packaging/out/clean-install/candidate-*/extracted/Lampyris-0.1.0-universal/Lampyris.app
```

`macos-clean-install` 会：卸载旧包（`--purge-data`，旧 config/词库进 `uninstalled/`）→ 装新包 → 校验签名/公证/执行 SHA（期望 `8984c223…`）→ 尝试选中输入源。

若脚本拒绝自动选中输入源：在系统设置里添加「萤火虫」后 `bin/selsrc cn.jokerhub.inputmethod.Lampyris.default`。

### 4.3 验收清单（同报告 071 + 本轮新增项）

先打开**自建** TextEdit 文档（`/tmp/lampyris-b/…`，不要动用户文档），按键一次激活控制器，然后：

1. **菜单**：`bin/axmenu open && bin/axmenu dump`。产品行 7 行；**右侧快捷键应为 `⌥M` / `⇧` / `⌥空格` / `⌥T` / `⌥P` / `⌥,` / `⌥A`**（AX 上 option 位 = mods 10）。先 dump 再按索引点击，不要照抄 A（A 上整体小 2）。
2. **全新配置**：`config.toml` 应只有使用中写入的键，`mode=mixed`、无显式 `hotkey.*`；`~/Library/Application Support/Lampyris/uninstalled/data.*/` 里能找到被移走的旧 config 与 496 行词库。
3. **输入**：`wq`+空格 → 你；`nihao`+空格 → 你好；`kwwl` → 中华人民共和国（四码唯一 auto_commit）。
4. **撤销**：⌘Z。**注意**：TextEdit 会把「程序化清空 + 随后提交」并进同一撤销组，要先打字→方向键断开组→再 ⌘Z（见报告 071 的坑）。
5. **四状态**往返（中英/全半角/简繁/标点），每步回读 `config.toml`；**模式**连点三次 mixed→wubi→pinyin→mixed。
6. **设置/关于**窗口：设置页「快捷键」分区应显示 `⌥M/⇧/⌥空格/⌥P/⌥T/⌥,/⌥A/⌥L`；关于页两个按钮宽度应接近（描边约 75/80pt）、文字行中心对齐（报告 072 的修正）。
7. **候选窗底部留白**（报告 073）：5 候选 + `1/N` 翻页时面板内容高 **64pt**，上下留白 8/8；带附行时才变 92pt。可直接和 `make macos-ui-snapshots` 的离屏图对照。
8. **⌃Space 误切回归**（报告 074）：保持英文模式，按 `⌃Space` 切到萤火虫后**立刻**按一下 Shift —— 应切中英，**不得**变成全角。
9. **A 的 D2/D3 复核**：设置面板首次打开落在哪个分区；「关于」是否稳定出现。
10. 结束时还原：`mode=mixed`、标点=中文、字形=简体、输入源回原值；核对 `config.toml` 字节、宿主 PID、包未被替换。

### 4.4 收尾

- 报告 `docs/reviews/078-device-b-clean-install-6494eab.md`（PASS/FAIL/BLOCKED + 证据文件名，证据放 `platforms/macos/build/acceptance-b-078/`，该目录被 gitignore）。
- 同步本文件（§1/§3/§4/§9）与 `ROADMAP.md`；`make verify` 后提交推送。

## 5. 授权与边界

- 不自动注销/重启/解锁；重启与登录由用户执行，agent 只做重启后的卸载/安装/验收。
- 配置只经 `ime-config`；不手改 `config.toml`、不写 `UserDefaults`。全新安装靠 `uninstall.sh --purge-data` 把文件**移出**活动目录，不删除。
- 不覆盖未知并发改动；不创建全量备份；不操作用户真实文档；微信等真实会话须按 IT 卡单独授权。
- 实机动作前核对自有文档、输入源、宿主与焦点；失配立即停止。用户截图/口头确认不能记为正式 PASS。
- 一轮只测一个包，不热替换；探针遵守 `tools/macos-probe/README.md`。

## 9. 会话日志

- 2026-10-18 / pi：交接标准化。新增 `scripts/handoff-status.sh`（只读采集分支/包 SHA/config/词源/CI/工具会话，`--for=compact|session|agent|device`，`--prompt` 出骨架）与 `make handoff`；`update-handoff` skill 改为四场景矩阵 + 五步流程 + HANDOFF 契约 + 反例；新增 `docs/交接提示词模板.md`（四份模板）并接入 AGENTS §6.1 与 docs 索引。
- 2026-10-18 / pi：交接 B 机重启后验收。本轮完成 ⌥ 默认值（ADR-209）、候选窗底部留白、关于页按钮、组合键防误判、离屏截图工具、`--purge-data` 与 `scripts/clean-install.sh`；新包 `6494eab` 已出（exec `8984c223…`）并在 A 核验，A 未安装。B 重启后按 §4 执行 `make macos-clean-install` 并写报告 078。
- 2026-10-18 / pi：无注销验收三档 + 一条命令全新安装（报告 077）。`make macos-ui-snapshots` 增设设置四分区截图并打印默认 ⌥ 绑定文本；新增 `scripts/clean-install.sh` / `make macos-clean-install`（卸载→安装→校验，缺 `--input-source-removed` 只打印清单）；明确只有「签名包+真实 IMK」需要一次注销。
- 2026-10-18 / pi：出包 + 交接全新安装。`7e2edc7`/`4a48443` 的 CI 因学习区快捷键用例仍按 `⌃⇧L` 而红，修好并重跑（`6494eab` 全绿）；新包下载核验（zip `0325ef9d…`、执行 `8984c223…`、Notarized Developer ID）。
- 2026-10-18 / pi：默认快捷键改 Option 语义前缀（ADR-209 / 报告 075）。实测系统无「仅 ⌥+字母」快捷键、⌥E/N/U/I 为死键；默认改为 ⌥M/⌥Space/⌥P/⌥T/⌥L/⌥,/⌥A（中英仍单 ⇧）。
- 2026-10-18 / pi：`make macos-ui-snapshots` + 快捷键误判修正（报告 074）。组合键匹配要求事件时间戳晚于最近修饰键变化（20ms 容差），修 `⌃Space` 切换后重投递旧空格被当成 `⌃⇧Space` 而误切全/半角。
- 2026-10-18 / pi：候选窗底部留白修正（报告 073）、关于页 macOS 13 布局修正（报告 072）。
