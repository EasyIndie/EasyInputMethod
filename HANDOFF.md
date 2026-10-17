# HANDOFF — 当前状态

## 0. 元信息

- 更新：2026-10-18 / pi（deepseek-flash）
- 分支：`main` @ `9a485c5`（已推送；无其它本地/远程分支、无额外工作树）
- 阶段：0.1.0 已签名公证并装 A/B；**MVP 发布门禁未全部关闭**
- 最近验证：`make verify` 全绿（180 产物）、离线 31 套件、本地 60 项；`macos-acceptance` 签名/公证成功；B 机同包实机验收通过核心输入/撤销/四状态/模式/设置/关于（报告 070）

## 1. 安装与数据

| 设备 | 系统 | 已装包 | 状态 |
|---|---|---|---|
| B（本机 `joker`） | arm64 / macOS 27.0.1 | `a234ef31…`（0.1.0，Developer ID + 公证） | 已验收（报告 070）；`mode=mixed`、config `6314f3f4…`（默认值）、词库 496 行 |
| A（`bot@pro` / 192.168.0.35） | Intel / macOS 13.7.8 | 同一 `a234ef31…` | 已装、已注册（TIS 选中成功、系统已请求菜单）；**验收未做** |

- 安装路径均为 `~/Library/Input Methods/Lampyris.app`；两机 `codesign --verify --deep --strict`、`stapler validate`、`spctl` 均通过。
- A 的 `config.toml` 只显式写了 `toggle_mode`，其余走 Schema 默认值（`⌃⇧.`/`⌃⇧T`/`⌃⇧L`/`⌃,`/`⌃⇧A` 自动生效）。
- A 的仓库在 `~/Documents/EasyInputMethod`，当前是旧提交 `d429cec`、工作树干净；**A 无 cargo**（只有 `swiftc` 5.8.1 / `make`），因此 A 上只做"拉代码 + 用预编译包验收 + 编探针"，不构建 Rust。

## 2. 本轮完成（2026-10-18）

- **菜单交互定稿（ADR-206/207/208）**：取消子菜单，恢复单行 `混输模式/五笔模式/拼音模式` 点击循环；标题实时反映模式；右侧为快捷键列；设置/关于新增可配置快捷键；默认快捷键 `⌃⇧M` / `⇧` / `⌃⇧Space` / `⌃⇧.` / `⌃⇧T` / `⌃⇧L` / `⌃,` / `⌃⇧A`。
- **正式包**：PR #53 合入 `main`（`ba6d796`）→ `macos-acceptance` 签名+公证+staple → 执行 SHA `a234ef31…`，zip 摘要/信任核验通过；A/B 均已安装。
- **B 机验收（报告 070）**：五笔 `wq`→你、拼音 `nihao`→你好、`kwwl`→中华人民共和国、`⌘Z` 撤销、四状态往返、模式三循环、设置/关于窗口、快捷键全部通过；测后状态已还原。
- **仓库清理**：合并后的分支已删除（本地+远程），stale worktree 已移除，仅剩 `main`；探针源码入库 `tools/macos-probe/`（报告 069 的 P6）。

## 3. 当前未决

- **A 机验收**：菜单外观、核心输入、撤销、四状态、模式循环、设置/关于、快捷键（报告 070 清单）。
- **正式报告**：`platforms/macos/build/final-menu-abdb83f/formal-report.json` 仍是旧包 `abdb83f` 的 1 PASS / 22 BLOCKED，需对 `a234ef31` 重跑。
- **发布门禁（均未关闭）**：
  - I0 安全验收（IT-01…03，需独立测试账号）
  - I1 输入可靠性（IT-04…09）
  - I2 产品体验（IT-10/11、16…22）
  - I3 日常与兼容（IT-12 性能、IT-14 兼容矩阵、IT-23 五工作日）
  - I4 分发（IT-13 附件 dry_run、IT-15 第三方独立复现、tag/Release 未创建）
- **未覆盖的实机项**：睡眠唤醒、多屏/缩放、物理键盘导航、VoiceOver、安全输入框/非 US 布局、客户端矩阵（Safari/Chrome/VSCode/微信/Terminal）、同包性能基线。
- **提速项（报告 069）**：P1 实机检查脚本、P2 宿主内建 trace、P3 VM 快照、P4 测试从 schema 派生、P5 CI paths 过滤、P7 证据等级门槛、P8 文档（守则已写）。

## 4. 下一步

1. **A 机按报告 070 验收**（详见下节"在 A 上继续"）。
2. 之后优先落地 **P1/P2**（`make macos-live-check` + 默认关闭的菜单/命令 trace），把剩余实机项做成可重复脚本。
3. 按迭代计划 I0→I1→I2→I3→I4 收敛门禁；最后再跑 `validate-release.py` dry_run 与 `v0.1.0` tag/Release。

### 在 A 上继续（给下一位 agent）

```sh
cd ~/Documents/EasyInputMethod
git fetch origin && git checkout main && git pull --ff-only     # d429cec → 9a485c5
make -C tools/macos-probe                                        # 编 Intel 版探针
# 应用已装好（a234ef31…），无需重装、无需重启
```

验收步骤（每步记录结果，失败即停）：

1. 激活：打开 TextEdit 任意文档，按一次普通字符键（否则菜单只显示系统项）。
2. 菜单：`bin/axmenu open && bin/axmenu dump`，确认 8 行与右侧快捷键。
3. 输入：`bin/axtext clear <TextEdit pid>` 后用 `bin/typekeys` 逐键输入 `wq` + 空格 → 应得「你」；`nihao` + 空格 → 「你好」。
4. 撤销：`bin/keymod 6 cmd` 后确认回到上一条。
5. 状态：`bin/axmenu press '[7]'`（中英）、`'[8]'`（全半角）、`'[9]'`（简繁）、`'[10]'`（标点），每次往返并回读 `config.toml`。
6. 模式：`bin/axmenu press '[6]'` 三次，`mode` 应为 mixed→wubi→pinyin→mixed。
7. 窗口：`'[12]'` 设置、`'[13]'` 关于；`bin/windows` 核对。
8. 还原：`mode=mixed`、标点=中文、字形=简体、输入源回原值。

> A 是 Intel + macOS 13.7.8：若菜单/快捷键与 B 不一致，先查系统版本差异，不要直接套 B 的结论；SSH 进程没有辅助功能授权，远程读不到 AX，必须在 A 的图形会话里跑探针。

## 5. 授权与边界

- 不自动注销/重启/解锁；需要重登时由用户执行。
- 配置只经 `ime-config`（`ime-cli --config <真实路径>`）读写；不手工改 `config.toml`，不在 `UserDefaults`/注册表/环境变量另存。
- 不覆盖未知并发改动；不创建全量备份；不操作用户真实文档；客户端矩阵中微信等涉及用户数据，须按 IT 卡单独授权。
- 实机动作前核对自有文档、输入源、宿主与焦点；失配立即停止。用户截图/口头确认不能补记为正式 PASS。
- 探针遵守 `tools/macos-probe/README.md` 的守则（先按键激活、逐键输入、不热替换、测后还原）。

## 9. 会话日志

- 2026-10-18 / pi：0.1.0 发布 + B 验收 + 仓库清理。PR #53 → `ba6d796`，签名包 `a234ef31…` 装 A/B；B 实测核心输入/撤销/四状态/模式/设置/关于通过（报告 070）；删除已合并分支与 stale worktree，探针入库 `tools/macos-probe/`；交接给 A 继续验收。
- 2026-10-18 / pi：报告 069 复盘（迭代代价、根因、P1–P8 提速项），实机验证守则写入 `docs/开发工作流.md`。
- 2026-10-18 / pi：报告 067/068。带日志诊断证明子菜单子项命令不下发；ADR-206 改为单行循环，ADR-207/208 增加设置/关于快捷键并统一下拉默认值；本地 60 项、离线 31 套件、四项 CI 全绿。
- 2026-10-18 / pi：报告 065/066。查明"菜单消失"是读菜单前未按键激活控制器；候选菜单其实完整；顶层命令可用、子菜单子项不可用。
- 2026-10-17 / pi：报告 063/064。热替换与未激活污染结论，候选判定撤回；建立"A/B/A 对照 + 按键激活"的采集方法。
