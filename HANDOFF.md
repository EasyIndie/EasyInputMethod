# HANDOFF — 会话交接文档

> **本文件记录"当前状态"，供任意 AI 工具在任意新会话中快速接手，防止背景信息丢失。**
> **每次会话结束时必须更新本文件**（规则见 `AGENTS.md` §6.1；操作见 Skill `update-handoff`）。
>
> 稳定背景（设计、决策、数据合规）在 `docs/`；**本文件只回答三件事：此刻在哪 / 下一步做什么 / 有什么坑。**
> 历史细节找 `git log` 与各 `docs/tasks/*.md`，**不要在本文件里堆流水账**。

---

## 0. 元信息

| 项 | 值 |
|---|---|
| 最后更新 | 2026-10-09（多会话共享词表） |
| 更新者 | Codex |
| 当前阶段 | **P1-M3 发布工程 + P1-M4 最终验收；日常独立窗口调试，系统输入法未安装** |
| 当前分支 | `codex/fix-macos-registration`；用户授权持续推进 macOS 发布 |
| 活跃 PR | 无 |
| 最近一次 `make verify` | ✅ 本轮完整通过：94 单测 + 1 doctest、fmt、Clippy、deny（公告/依赖/许可/来源）、125 产物零网络符号；Swift 预览构建/按键冒烟及桌面交互通过 |


## 1. 三十秒摘要

- **萤火虫**：跨平台、开源可审计、默认离线、只做核心输入的中文输入法（五笔优先，**默认混输**）。Rust 引擎 + 窄 C ABI + 平台薄宿主；**GPL-3.0-or-later**。
- **现在**：P1-M0（引擎骨架）、P1-M1（自建码表）、P1-M2（配置 + 拼音 + 混输）**全部完成**；P1-M3 已完成 `ime-ffi`（C ABI）与 **Swift/InputMethodKit 宿主**（编译/打包/FFI 冒烟通过）。
- **下一步**：T-M3-03 固化安装/签名/公证流程与 SBOM；T-M3-04 已配置、本地等价验证通过，远端待 PR。用户指定后续开发调试统一运行 `make macos-preview`；未经再次要求不重装系统输入法；经典 IMK 宿主已实机验证，无需 appex 改造。
- ⛔ 铁律：核心不联网、`forbid(unsafe_code)`（**仅 `ime-ffi` 例外**）、数据登记许可、配置只走 `ime-config`。

## 2. 已完成（按里程碑；细节见 `docs/tasks/` 与 ADR）

| 阶段 | 成果 | 关键文档 |
|---|---|---|
| 调研 / 方案 | 选型、权威方案、交叉审核（有条件通过） | `docs/技术方案.md`、`docs/reviews/001.md` |
| **P1-M0** | workspace + `ime-core`（Engine/InputMode/会话状态机）+ `ime-table` + `ime-cli` | — |
| **P1-M1** 自建码表 | `crates/wubi-encoder`（五笔86 全规则）+ `data/` 流水线；单字表 **27,823 字**（vs D3 99.98% / vs rime 98.77%，**GB2312 一级均 100%**）；词组多候选表；内置核心 `wubi86-core.tsv` **491,854 B ≤ 0.6MB** | ADR-016…021 |
| **P1-M2** 配置+拼音+混输 | `crates/ime-config`（Schema/`ArcSwap` 快照/原子写/广播）+ `crates/ime-pinyin`（`PinyinBackend` + 内置兜底）；混输（`ime-core` 已实现合并）。实测 `nihao→你好`、`wq→你` | `docs/配置架构.md`、ADR-008/009 |
| **P1-M3**（进行中） | `crates/ime-ffi`（会话 + 配置 C ABI）+ **`platforms/macos/` Swift 宿主**（纯代码 AppKit，可编译/打包，`build.sh` 产 `Yinghuo.app`） | `platforms/macos/README.md`、ADR-022、`docs/技术方案.md` §5.3、`docs/配置架构.md` §9 |

> 实验数据：`docs/experiments/`（派发策略：独立任务用「每卡新 worker」，整批实测省 token）。

## 3. 进行中

- 交互功能已实现：分页、实时配置、中文标点/全半角、用户词库与学习（ADR-025…029）。默认核心词表和有界查询降低内存；五会话引擎 ABI 探针约 16.6MiB / P95 0.48ms，不代表完整 GUI DoD。

**P1-M3**：T-M3-01、T-M3-02、T-M3-05 已完成；macOS CI 已配置并本地验证；安装/卸载及签名、公证、源码/SBOM 打包脚本已实现并通过静态/拒绝路径检查，本地审核包约14.3MB，完整源码/vendor/许可/SBOM/SHA；从实际 ZIP 离线重建的去签名可执行文件和默认数据逐字节一致。

- T-M3-05 独立窗口完成：`make macos-preview`；自动检查 `./platforms/macos/dev-preview.sh --smoke-test`。debug 增量构建，不需要公证/安装/重启；仍需正式宿主验证 IMK 系统集成。
- ADR-023 修正注册标识；此前签名、公证、系统安装及实机验收通过。当前已按用户要求卸载，见 §7。
- 用户重启后，TIS 稳定枚举 1/337，选择返回 0；用户实体键盘确认 TextEdit/Safari 的五笔 `wq→你`、拼音兜底 `nihao→你好` 正常。
- SIG-2 关闭，经典 `.app` 可用。详细证据及历史失败记录见 T-M3-02 任务卡。

## 4. 下一步（可执行，按优先级）

1. **P1-M4**：正式宿主会话/预编辑边界及多会话/GUI 性能检查；功能确认后重打最终候选。
2. **P1-M4**：发布候选包的正式 IMK 多应用交互、性能与用户词库验收；T-M3-04 远端检查待 PR。
3. **P1-M5**：准备可复现构建说明、SBOM、许可附件与零外联证据。

## 5. 待决 / 阻塞

| 编号 | 问题 | 是否阻塞 |
|---|---|---|
| REV-1…4 | 交叉审核已完成（`docs/reviews/001.md`） | 否 |
| TBD-1 | 词频数据源 — ✅ 已定 `fxsjy/jieba`（D10，MIT），ADR-021 | 否 |
| TBD-2 | 五笔98 / 新世纪 / 郑码数据源 | 否 |
| TBD-3 | ✅ ADR-029：有界 TSV v1，用户词库与学习已实现 | 否 |
| TBD-4 | 英文/包名（`yinghuo` vs `lampyris`） | 否 |
| TBD-5 | 结构/末笔**独立**数据源 — 暂无可用的 GPL-3 兼容来源；以多 oracle 交叉验证替代（ADR-019），字根来源用 D3 拆字（ADR-020） | 否 |
| **SIG-1** | **签名/公证要求**：✅ 已定 —— macOS 26/27 强制「Developer ID + hardened runtime + 公证」；未公证的 Developer ID 被 LaunchServices 判 `is not trusted`、TIS 静默不显示（Phase 1「不签名」前提不成立） | 不再阻塞；ADR-032 与签名/公证脚本已接入；新候选待实际验证 |
| **SIG-2** | ✅ 已关闭：ADR-023 新包重启后枚举/选择正常，TextEdit/Safari 用户实测通过；经典 IMK `.app` 可用 | 否 |

## 6. 必须知道的坑与硬约束

**铁律（见 `AGENTS.md` §2）**：核心不联网；`forbid(unsafe_code)`（仅 `ime-ffi`）；配置只走 `ime-config`（禁 `UserDefaults`/注册表/第二文件）；任何数据先登记许可。

**实操坑（本轮踩过，务必记住）**：

- ⚠️ **模型名要带 provider**：`deepseek-v4-pro` 在 8 个 provider 下**歧义** → 必须 `--provider cc-switch-deep-seek`；`deepseek-v4-flash` 不歧义。
- ⚠️ **> ~5 MB 的生成文件会让 `git push` 报 HTTP 400**：大表（`wubi86-phrases.tsv` 5.6MB、`pinyin-words.tsv` 8.4MB）**一律 gitignore**，由 `data/sources/fetch-*.sh` + `cargo run --example …` 复现。
- ⚠️ **macOS 输入法必须是 `.app`**（不是 `.inputmethod`），本机首次注册/注册元数据修正后需**注销/重启**完成登录扫描；普通代码热替换尚未验收；`killall TextInputMenuAgent` / 删 `IntlDataCache` / `lsregister -f` / `TISRegisterInputSource`（返回 `noErr`）都**不能**免重启触发重扫。日常功能迭代使用独立窗口（ADR-024），无需该流程。诊断：`platforms/macos/tools/`。
- ✅ **注册标识**：bundle ID 必须采用带 `.inputmethod.` 的形式；当前为 `org.yinghuo.inputmethod.Yinghuo`，连接名为 `${bundleID}_Connection`（ADR-023）。组合修正及重启后实机通过；不要再据早期失败推断必须 appex。
- ⚠️ **公证三件套**：`codesign --options runtime --timestamp` → `ditto` 打包 → `xcrun notarytool submit --keychain-profile <profile> --wait` → `xcrun stapler staple`；判定用 `spctl -a -vvv -t exec` 应为 `accepted / Notarized Developer ID`。首次常遇 `403 A required agreement is missing` → 需 Account Holder 在 App Store Connect 接受协议。
- ⚠️ **登录钥匙串**：后台/非 GUI 会话跑 `codesign` 会报 `errSecInternalComponent`（钥匙串锁定或不在 GUI 会话）；需在 GUI Terminal 跑一次并点“始终允许”。
- ⚠️ **LS 影子副本**：同一 bundle id 若在 `build/`、DerivedData 或已删路径有残留登记，Text Input 会绑定影子副本导致静默失败；装完务必 `lsregister -dump` 去重。
- ⚠️ **IMK Swift 事件方法叫 `handle(_:client:)`**（不是 `handleEvent`；后者在 Swift 3 被重命名）；`Info.plist` 输入模式清单在 `ComponentInputModeDict.tsInputModeListKey`（参照系统输入法实测）。
- **默认拼音为 `pinyin-core.tsv`（256KiB）**：全量词表作为生成输入、不默认装载；ADR-031 和 `docs/reviews/003-macos-performance.md` 记录性能边界。发布不得容忍数据缺失降级。
- ⚠️ **bash + 中文坑**：`$var` 后紧跟全角字符（如 `$model（`）会被当变量名 → 一律写 `${var}`。
- ⚠️ **许可地雷**：`Arphic Public License`（makemeahanzi / hanzi-writer）**GPL 不兼容**；`GPLv2-only` 与 GPL-3 不兼容；**极点五笔 provenance 存疑**（`rime-wubi86-jidian` 仅可测试）。
- ⚠️ **worker 产出不会自动提交**：派发后必须**人工复核 + `git add/commit/push`**（个别 worker 会自建 commit，要检查 `git log`/`git status`）。
- ⚠️ **派发工具**：`./scripts/dispatch-task.sh docs/tasks/<卡> --model <m> [--provider <p>] [--jobs N]`；用量自动记入 `docs/experiments/runs/usage.jsonl`（`./scripts/usage-report.sh` 汇总）。
- 提交前必须 `make verify` 全绿。

## 7. 环境快照

| 项 | 值 |
|---|---|
| 当前/验证机 | macOS **27.0**（26A428）、**Apple Silicon arm64**；Xcode **27.0**（27A266a）；用户 `joker`（admin） |
| 签名身份 | ✅ `Developer ID Application: Zhizhou Wang (2N62934Y28)` 与 `Apple Development: …`；公证凭据已存钥匙串 profile `yinghuo-notary` |
| Rust | ✅ 已装 rustup + **1.98.1**（`rust-toolchain.toml` 固定）；target `aarch64-apple-darwin` |
| 宿主工具链 | Xcode 27 的 `swiftc`/`codesign`/`xcrun notarytool 1.1.3`/`stapler`；`make` 可用 |
| 输入法现状 | 已从系统启用列表移除萤火虫并停止系统宿主；ABC/搜狗保留。系统及用户安装目录均无 Yinghuo.app；安装包已移至 `/private/tmp/yinghuo-uninstalled/Yinghuo.app`，TIS 匹配 0/335，无系统宿主进程；独立调试窗口保留 |
| 数据 | `data/generated/` 已生成 `wubi86-core.tsv` / `pinyin-chars.tsv` / `pinyin-words.tsv`（8.4MB 不入库；可由 fetch 脚本 + `ime-pinyin --example generate` 复现） |
| 代码 | ✅ crates：`ime-core` `ime-table` `ime-pinyin` `ime-config` `ime-ffi` `ime-cli` `wubi-encoder`；**94 单测 + 1 doctest**；`platforms/macos/` Swift 宿主 |

## 8. 接手清单（新会话开始时）

- [ ] 读 `AGENTS.md`（铁律 / 工作流 / 约定）
- [ ] 读本文件
- [ ] 看 `ROADMAP.md` 当前进度
- [ ] 读与本次任务相关的 `docs/`（P1-M3 看 `docs/技术方案.md` §5/§5.3、`docs/配置架构.md` §9）
- [ ] 先跑 `make verify` 确认基线
- [ ] 有歧义 → **先问，不要猜**

## 9. 会话日志（倒序，保留最近 10 条；更早见 git 历史）

### 2026-10-09 · Codex（预编辑取消边界）
- ADR-036：正式菜单操作同步清除客户端 marked text/组合/候选；模式保存失败不切换。独立面板前也取消组合。
- 失焦/显式复位重置引号配对，不改变模式/临时中英全半角；普通选字和取消不重置配对。
- 94单测、两宿主构建、真实预览及 make verify 全绿；正式客户端仍待最终安装验收。

### 2026-10-09 · Codex（多会话内存）
- ADR-035：Arc 共享默认只读词表，FFI 最多4组 Weak 缓存；组合/选项/用户词库独立。
- 五会话稳态从65.89降至16.64MiB；2200键 P95 0.481ms。快照更新、选项隔离与释放测试通过。
- 两宿主构建/真实预览及 make verify 全绿；CLI 临时文件隔离修复单独提交。
- 下一步正式宿主预编辑边界与 GUI 性能；完整 DoD 未完成，未重新安装或上传。

### 2026-10-08 · Codex（反查与源码包验证）
- ADR-034：现有拼音反查经通用 Engine/Session 与拥有字符串 ABI 接入正式菜单/独立窗口；只读无记录。
- 单测验证 ABI 生命周期/非法输入/候选不变，两宿主构建与真实预览通过；完整 make verify 通过。
- 5b232d0 审核 ZIP 14.3MB 从真实归档离线重建成功，去签名程序/数据逐字节一致；新功能完成后再重打最终包。
- 尚未上传/安装；正式多应用、GUI/多会话内存、动态零外联与新公证仍待。

### 2026-10-08 · Codex（同环境载荷复现）
- ADR-033：源码归档不要求 .git，Rust 路径映射、Swift 相对路径/WMO、链接调试信息去除；显式 macOS 13 目标。
- registry 构建与 vendor 离线重建的 Rust staticlib、完整 ad-hoc 可执行文件逐字节一致；正式包验证脚本 run-repro.sh 接入。
- 首包约14.3MB；最终干净提交候选需重打并运行归档重建，签名/公证及完整 DoD 仍待。

### 2026-10-08 · Codex（发布流程脚本）
- ADR-032 取代早期不签名前提；严格构建、可信安装、保留数据卸载、显式签名/公证与本地发布附件实现。
- CycloneDX、完整源码/vendor、原始依赖与数据许可、SHA 清单；准备脚本要求 clean git，同一源码提交。
- bash/参数/未签名拒绝、严格宿主构建、make verify 通过；候选打包/离线复现与真实安装验收待完成。

### 2026-10-08 · Codex（性能预算）
- ADR-030/031：码表查询改有界 top-k，默认拼音词表 256KiB；保留全量生成输入及登记许可/SHA。
- 可复现 C ABI 探针：2200 按键、稳态约 17MiB / P95 0.47ms；完整宿主与最大用户词库仍待测。
- 两宿主构建、预览与 FFI 冒烟、词表复现、make verify 通过；下一步安装/签名/公证与发布附件。

### 2026-10-08 · Codex（用户词库与学习）
- ADR-029：ime-dict 零依赖有界 TSV、原子写与锁、学习排序、新增/导入/导出；两宿主入口接入。
- 专项并发/坏数据保护、隔离真实预览词条与重建会话保留、两宿主构建、make verify 通过。
- TBD-3 关闭，M4 功能已实现；下一步性能/发布工程与完整跨应用验收。

### 2026-10-08 · Codex（中英、标点、全半角）
- ADR-028：核心统一标点/成对引号/全角；新增两项 Schema；共享快捷键消费。
- 核心回归、Swift 实际适配器快捷键/标点冒烟、两宿主构建、make verify 通过。
- M4 交互项完成实现；用户词库与学习、跨应用完整 DoD、发布工程尚未完成。

### 2026-10-08 · Codex（引擎选项消费）
- ADR-027：已有 auto_commit、z_key、fuzzy 选项通过共享 FFI 按键前读取快照，接入真实引擎。
- 专项开关/通配/模糊音回归、两宿主构建、预览冒烟、make verify 通过。
- 下一步中英切换、标点、全半角；用户词库与发布工程未完成。

### 2026-10-08 · Codex（实时配置与候选外观）
- ADR-026：FFI 接入已有文件监听；正式宿主按键读取最新模式/候选数，候选窗实时主题及屏幕边界限制。
- 隔离预览验证外部配置编辑与候选数生效，避免修改用户配置；独立模式仍只影响会话。
- 两宿主构建、预览冒烟和 make verify 通过；下一步引擎配置消费与日用输入交互。
