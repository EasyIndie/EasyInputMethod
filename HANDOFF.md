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
| 最后更新 | 2026-10-08（图标资产归档，V4 当前首选） |
| 更新者 | Codex |
| 当前阶段 | **P1-M3：T-M3-01 / T-M3-02 / T-M3-05 ✅；独立调试窗口可直接迭代。下一项 T-M3-03 安装/签名/公证脚本** |
| 当前分支 | `codex/fix-macos-registration`；本轮独立 AppKit 调试窗口（ADR-024） |
| 活跃 PR | 无 |
| 最近一次 `make verify` | ✅ 本轮完整通过：82 单测 + 1 doctest、fmt、Clippy、deny（公告/依赖/许可/来源）、71 产物零网络符号；Swift 预览构建/按键冒烟及桌面交互通过 |


## 1. 三十秒摘要

- **萤火虫**：跨平台、开源可审计、默认离线、只做核心输入的中文输入法（五笔优先，**默认混输**）。Rust 引擎 + 窄 C ABI + 平台薄宿主；**GPL-3.0-or-later**。
- **现在**：P1-M0（引擎骨架）、P1-M1（自建码表）、P1-M2（配置 + 拼音 + 混输）**全部完成**；P1-M3 已完成 `ime-ffi`（C ABI）与 **Swift/InputMethodKit 宿主**（编译/打包/FFI 冒烟通过）。
- **下一步**：T-M3-03 固化安装/签名/公证流程；T-M3-04 增加 macOS 构建 CI。用户指定后续开发调试统一运行 `make macos-preview`；未经再次要求不重装系统输入法；经典 IMK 宿主已实机验证，无需 appex 改造。
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

**P1-M3**：T-M3-01、T-M3-02、T-M3-05 已完成；macOS CI 已配置并本地验证；安装发布脚本尚未完成。

- T-M3-05 独立窗口完成：`make macos-preview`；自动检查 `./platforms/macos/dev-preview.sh --smoke-test`。debug 增量构建，不需要公证/安装/重启；仍需正式宿主验证 IMK 系统集成。
- ADR-023 修正注册标识；此前签名、公证、系统安装及实机验收通过。当前已按用户要求卸载，见 §7。
- 用户重启后，TIS 稳定枚举 1/337，选择返回 0；用户实体键盘确认 TextEdit/Safari 的五笔 `wq→你`、拼音兜底 `nihao→你好` 正常。
- SIG-2 关闭，经典 `.app` 可用。详细证据及历史失败记录见 T-M3-02 任务卡。

## 4. 下一步（可执行，按优先级）

1. **T-M3-03**：固化安装/签名/公证流程；将 SIG-1 策略并入 ADR 与总方案。
2. **P1-M4**：候选翻页与输入交互；T-M3-04 配置完成，远端检查待 PR。
3. **P1-M4**：按任务卡完善交互（用户词库存储待定）。

## 5. 待决 / 阻塞

| 编号 | 问题 | 是否阻塞 |
|---|---|---|
| REV-1…4 | 交叉审核已完成（`docs/reviews/001.md`） | 否 |
| TBD-1 | 词频数据源 — ✅ 已定 `fxsjy/jieba`（D10，MIT），ADR-021 | 否 |
| TBD-2 | 五笔98 / 新世纪 / 郑码数据源 | 否 |
| TBD-3 | 用户词库存储格式 | 只阻塞 P1-M4 用户词库/学习，不阻塞候选交互 |
| TBD-4 | 英文/包名（`yinghuo` vs `lampyris`） | 否 |
| TBD-5 | 结构/末笔**独立**数据源 — 暂无可用的 GPL-3 兼容来源；以多 oracle 交叉验证替代（ADR-019），字根来源用 D3 拆字（ADR-020） | 否 |
| **SIG-1** | **签名/公证要求**：✅ 已定 —— macOS 26/27 强制「Developer ID + hardened runtime + 公证」；未公证的 Developer ID 被 LaunchServices 判 `is not trusted`、TIS 静默不显示（Phase 1「不签名」前提不成立） | 不再阻塞；待并入 ADR + `build.sh` 参数化 |
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
- ⚠️ **`pinyin-words.tsv`（8.4MB）不入库**：`build.sh` 缺失时宿主降级（无拼音/单音节），复现见 `platforms/macos/README.md`。
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
| 代码 | ✅ crates：`ime-core` `ime-table` `ime-pinyin` `ime-config` `ime-ffi` `ime-cli` `wubi-encoder`；**82 单测 + 1 doctest**；`platforms/macos/` Swift 宿主 |

## 8. 接手清单（新会话开始时）

- [ ] 读 `AGENTS.md`（铁律 / 工作流 / 约定）
- [ ] 读本文件
- [ ] 看 `ROADMAP.md` 当前进度
- [ ] 读与本次任务相关的 `docs/`（P1-M3 看 `docs/技术方案.md` §5/§5.3、`docs/配置架构.md` §9）
- [ ] 先跑 `make verify` 确认基线
- [ ] 有歧义 → **先问，不要猜**

## 9. 会话日志（倒序，保留最近 10 条；更早见 git 历史）

### 2026-10-08 · Codex（T-M3-04 macOS CI）
- 新增独立 macOS job：Rust/隐私验证、正式构建、登记数据复现、独立窗口冒烟、图标校验；不安装或公证。
- YAML 静态解析、本机等价构建及 make verify 通过；远端实际运行待 PR。
- 用户授权持续推进 macOS 发布；下一步候选翻页，保留完整 DoD 验收门槛。

### 2026-10-08 · Codex（进度核对与推进建议）
- M0–M2 核心完成，M3 剩安装发布脚本与 macOS CI；翻页 ABI 仍为 no-op，M4 未完整交付。
- 建议先补 macOS CI，再在独立窗口完善候选翻页；安装发布脚本原任务卡与实机签名要求冲突，执行前需修订。
- 文档存在历史状态漂移：README/AGENTS 仍称未编码、T-M1-09 未勾选、ROADMAP 隐私 CI 项已实际接入；后续逐项核对。
- 本轮仅只读检查及交接纠偏，沿用前一轮完整验证结果。

### 2026-10-08 · Codex（V4 应用图标）
- 用户指定 V4 暂作项目及应用图标；README 展示与两个 macOS 构建脚本接入多尺寸 ICNS。
- V1–V5 全部保留；菜单栏模板图标暂沿用现有资源。未安装系统输入法。
- 两应用构建、预览冒烟、ICNS 回读与资源一致性、完整 make verify 均通过。

### 2026-10-08 · Codex（图标资产归档）
- V1–V5 原图及提示词统一收录 assets/icons/，补充版本索引与使用场景说明。
- 用户当前首选 V4 单线风格；其余版本保留，应用资源尚未替换。
- 原图完整性与文档链接检查通过；无代码或依赖变更。

### 2026-10-08 · Codex（项目图标设计稿）
- 按用户要求生成简洁萤火虫图标，深蓝/青绿/暖黄配色；原始 PNG 与提示词保存于 assets/icons/yinghuo-icon-concept-v1.*。
- 已目视检查；新增 V2 几何、V3 立体、V4 单线、V5 纸感四版及提示词（assets/icons/yinghuo-icon-variants.md），用户当前首选 V4；V4 已暂时接入项目 README 及两种 macOS 应用图标，无代码或依赖变更。

### 2026-10-08 · Codex（移除系统输入源）
- 按用户要求在系统设置移除萤火虫输入源，保留 ABC/搜狗；停止系统宿主。
- 后续开发调试统一使用 make macos-preview，未经再次要求不重装系统输入法。
- 后续只读复查确认安装包已移至 /private/tmp/yinghuo-uninstalled；系统/用户目录均无包，TIS 0/335，无系统宿主。
- 仅更新交接，无代码变更；沿用上一轮完整验证结果。

### 2026-10-08 · Codex（T-M3-05 独立调试窗口）
- ADR-024：普通 AppKit 应用复用真实引擎、FFI 与候选窗，debug 构建直跑，无系统安装/公证/重启。
- 五笔/拼音、选字、退格/Esc、清空及模式切换桌面验证通过；自动预览冒烟、完整 make verify 通过。
- 本机缓存后构建约 4.25 秒；IMK 系统集成仍走正式宿主验收。下一项 T-M3-03。

### 2026-10-08 · Codex（T-M3-02 实机验收完成）
- 重启后枚举/选择正常；用户实体键盘确认 TextEdit/Safari 的「你」「你好」候选和上屏正常。
- T-M3-02 完成，SIG-2 关闭；保留经典 IMK .app；同步 ROADMAP/任务卡/README。
- 本轮仅文档收尾，沿用此前完整 make verify 通过结果；下一项 T-M3-03。

### 2026-10-08 · Codex（用户批准公证并实机验收）
- 公证 Accepted、staple/spctl/严格签名校验通过；新包已装系统域，旧包备份在 /private/tmp。
- 临时注册曾枚举 1/337，但选择 -50；宿主可启动，之后列表恢复 0/335，系统设置无结果。
- 已恢复搜狗拼音；待用户保存工作后注销/重登，实际打字验收未通过。

### 2026-10-08 · Codex（T-M3-02 注册标识排查）
- 核查 SDK/Xcode 模板与 Apple 文档，暂缓无公开入口证据的 appex 改造。
- ADR-023：修正 bundle/mode ID 与连接名，同步本地化；保留接手时未提交改动。
- 完整 make verify、新包构建/plist/ad-hoc 校验、FFI 冒烟通过；人工装载待重新签名/公证/安装及重登。
