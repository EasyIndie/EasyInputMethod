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
| 最后更新 | 2026-10-08（T-M3-02 已公证安装；待注销重登验收） |
| 更新者 | Codex |
| 当前阶段 | **P1-M3：ADR-023 修正经典 IMK 注册标识；新包构建通过，新包 Developer ID/公证/系统域安装通过；TIS 短暂枚举但无法选择，待重登验收** |
| 当前分支 | `codex/fix-macos-registration`；本轮注册修正及关联交接文档，包含接手时的装载记录与 plist 修正 |
| 活跃 PR | 无 |
| 最近一次 `make verify` | ✅ 本轮完整通过：82 单测 + 1 doctest、fmt、Clippy、deny（公告/依赖/许可/来源）、68 产物零网络符号 |


## 1. 三十秒摘要

- **萤火虫**：跨平台、开源可审计、默认离线、只做核心输入的中文输入法（五笔优先，**默认混输**）。Rust 引擎 + 窄 C ABI + 平台薄宿主；**GPL-3.0-or-later**。
- **现在**：P1-M0（引擎骨架）、P1-M1（自建码表）、P1-M2（配置 + 拼音 + 混输）**全部完成**；P1-M3 已完成 `ime-ffi`（C ABI）与 **Swift/InputMethodKit 宿主**（编译/打包/FFI 冒烟通过）。
- **下一步**：新包已签名/公证并装系统域；注销/重登后枚举 `org.yinghuo.inputmethod.Yinghuo`，验证 TextEdit/Safari。暂缓 appex 改造（未找到公开入口证据）。详见 `docs/tasks/T-M3-02.md` 第三轮。
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

**P1-M3**：`ime-ffi` ✅；**T-M3-02 代码完成且自测通过**（编译/打包；`run-ffi-smoke.sh` 实测 `wq→你`、`nihao→你好`）。

**T-M3-02 装载验收（第三轮 · Codex）**：
- 修正 bundle ID、模式 ID、连接名（ADR-023），构建/plist/ad-hoc 校验及 FFI 冒烟通过。
- Xcode 27 模板无 Input Method Extension；公开 SDK 未将 IMKServer 标弃用。内置 appex 不足以证明第三方必须迁移。
- 系统日志有拒绝连接名的错误，但对应 bundle ID 隐去；修正是优先实验，尚未证明根因。
- 用户明确批准后，Apple 公证 Accepted（submission `e416c923-0dc4-44f4-8aea-6625fb87489e`）；staple、系统域签名/票据/spctl 校验通过。
- `/Library/Input Methods/Yinghuo.app` 已替换为新 ID；旧包备份在 `/private/tmp/yinghuo-acceptance-backup/Yinghuo.app`。
- TISRegister 后曾枚举 1/337（已启用），但选择返回 -50；宿主启动后又为 0/335，设置搜索无结果。宿主能运行，不等于可输入。待注销/重登；TextEdit/Safari 打字未验收。
- 已恢复验收前的搜狗拼音（选择返回 0）；CLI 选择机制有可用基线。

## 4. 下一步（可执行，按优先级）

1. **T-M3-02**：用户保存工作并注销/重登（或重启）后，重新枚举 `org.yinghuo.inputmethod.Yinghuo.default`，从设置添加并选择，验证 TextEdit/Safari。新包已签名/公证/安装，无需重建。
2. 若仍失败：获取本次登录的 imklaunchagent 日志，区分注册、信任和连接错误；再考虑干净用户实验。未经公开 API 核验，不改 appex。
3. **T-M3-03**：验收后固化安装/签名/公证流程；将 SIG-1 策略并入 ADR 与总方案。
4. **T-M3-04**：CI 增加 macOS 编译检查。

## 5. 待决 / 阻塞

| 编号 | 问题 | 是否阻塞 |
|---|---|---|
| REV-1…4 | 交叉审核已完成（`docs/reviews/001.md`） | 否 |
| TBD-1 | 词频数据源 — ✅ 已定 `fxsjy/jieba`（D10，MIT），ADR-021 | 否 |
| TBD-2 | 五笔98 / 新世纪 / 郑码数据源 | 否 |
| TBD-3 | 用户词库存储格式 | 阻塞 P1-M4 |
| TBD-4 | 英文/包名（`yinghuo` vs `lampyris`） | 否 |
| TBD-5 | 结构/末笔**独立**数据源 — 暂无可用的 GPL-3 兼容来源；以多 oracle 交叉验证替代（ADR-019），字根来源用 D3 拆字（ADR-020） | 否 |
| **SIG-1** | **签名/公证要求**：✅ 已定 —— macOS 26/27 强制「Developer ID + hardened runtime + 公证」；未公证的 Developer ID 被 LaunchServices 判 `is not trusted`、TIS 静默不显示（Phase 1「不签名」前提不成立） | 不再阻塞；待并入 ADR + `build.sh` 参数化 |
| **SIG-2** | ADR-023 新包已公证安装，临时注册可枚举但选择失败；待重登扫描；经典 IMK 已弃用的假设无公开证据 | **阻塞 T-M3-02 人工验收** |

## 6. 必须知道的坑与硬约束

**铁律（见 `AGENTS.md` §2）**：核心不联网；`forbid(unsafe_code)`（仅 `ime-ffi`）；配置只走 `ime-config`（禁 `UserDefaults`/注册表/第二文件）；任何数据先登记许可。

**实操坑（本轮踩过，务必记住）**：

- ⚠️ **模型名要带 provider**：`deepseek-v4-pro` 在 8 个 provider 下**歧义** → 必须 `--provider cc-switch-deep-seek`；`deepseek-v4-flash` 不歧义。
- ⚠️ **> ~5 MB 的生成文件会让 `git push` 报 HTTP 400**：大表（`wubi86-phrases.tsv` 5.6MB、`pinyin-words.tsv` 8.4MB）**一律 gitignore**，由 `data/sources/fetch-*.sh` + `cargo run --example …` 复现。
- ⚠️ **macOS 输入法必须是 `.app`**（不是 `.inputmethod`），且**换 bundle 后必须注销/重启**——只在登录时扫描；`killall TextInputMenuAgent` / 删 `IntlDataCache` / `lsregister -f` / `TISRegisterInputSource`（返回 `noErr`）都**不能**免重启触发重扫。诊断：`platforms/macos/tools/`。
- ⛔ **Xcode 机实测（macOS 27）**：即便 **Developer ID + hardened runtime + 公证 + 系统域 `/Library/Input Methods` + 布尔 plist + LS 单一登记**，扫描器重建的 `.kbdx` 缓存仍**只收搜狗不收我们** → 不能断言经典机制失效；先验 ADR-023 注册修正（§5 SIG-2 / T-M3-02 卡）。
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
| 输入法现状 | `/Library/Input Methods/Yinghuo.app`（新 ID、系统域、已公证、hardened runtime）；旧包备份在 `/private/tmp/yinghuo-acceptance-backup/` |
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

### 2026-10-08 · Codex（用户批准公证并实机验收）
- 公证 Accepted、staple/spctl/严格签名校验通过；新包已装系统域，旧包备份在 /private/tmp。
- 临时注册曾枚举 1/337，但选择 -50；宿主可启动，之后列表恢复 0/335，系统设置无结果。
- 已恢复搜狗拼音；待用户保存工作后注销/重登，实际打字验收未通过。

### 2026-10-08 · Codex（T-M3-02 注册标识排查）
- 核查 SDK/Xcode 模板与 Apple 文档，暂缓无公开入口证据的 appex 改造。
- ADR-023：修正 bundle/mode ID 与连接名，同步本地化；保留接手时未提交改动。
- 完整 make verify、新包构建/plist/ad-hoc 校验、FFI 冒烟通过；人工装载待重新签名/公证/安装及重登。

### 2026-10-08 · pi（T-M3-02 第二轮：Xcode 机装载，仍未通过 → 交接 Codex）
- Xcode 机（macOS 27 / arm64）：装 Rust 1.98.1 + 生成数据表；构建 + FFI 冒烟 `wq→你`/`nihao→你好` ✅。
- 查实：未公证的 Developer ID 被 LaunchServices 判 `is not trusted` → 必须 **hardened runtime + 公证**；已 `Developer ID` 重签、`notarytool` Accepted、`staple`、`spctl`=Notarized Developer ID（SIG-1 结案）。
- 装系统域 `/Library/Input Methods` + 布尔 `tsInputMode*Key` + `DT*` + LS 去重后**仍不被 TIS 枚举**（`0/335`，`.kbdx` 只收搜狗）→ 新阻塞 **SIG-2**（疑需 ExtensionKit appex）。
- 未提交：`platforms/macos/Info.plist`（布尔 ts* + DT*）。证据/下一步见 `docs/tasks/T-M3-02.md`「第二轮」与 §4。

### 2026-10-08 · pi（T-M3-02 交接：转 Xcode 机验证）
- 本机装不了：系统不枚举非 Apple 签发的输入法（ad-hoc / 自签 / 苹果 Ainu 副本均不可见；只有 Developer-ID 的搜狗可见）。
- 已确认：`.inputmethod` 不被 macOS 13 扫描 → 必须 `.app`；引擎侧 `run-ffi-smoke.sh` 实测 `wq→你`、`nihao→你好`。
- **交接要点**：本机 `main` 有 **6 个未推送 commit**；下一步在有 Xcode + 开发者帐号的 Mac 上，用**真实签名**构建、装载、验证。
- 证据/步骤/待办已写入 `docs/tasks/T-M3-02.md` 与本文件 §3/§4/§5（SIG-1）。

### 2026-10-08 · pi（T-M3-02 装载验收：环境/签名阻塞）
- 多次重登/重启后，TIS 仍不枚举我们的 `.app`（ad-hoc 与“自签+系统信任”均试过）。
- 差分实验：**苹果原版 Ainu 副本**（user 与 /Library）同样不可见；唯一可见的第三方是 **Developer ID 签名**的搜狗；`imklaunchagent` 持续报 `inputSourceTableCountSys 0`。
- 结论：极可能需 **Developer ID** 签名，或本机（OCLP）发现机制异常；仓库内无法解决。
- 已把证据/结论写入 `docs/tasks/T-M3-02.md`；新增 `tools/diagnose.sh`；待办含清理自签证书/系统目录副本。

### 2026-10-08 · pi（T-M3-02 装载排查：`.app` 仍不可见）
- 用户实测：`.inputmethod` 不认（macOS 13 LaunchServices `-10811`）→ 改 `.app`；修正后的 `.app` 在**登录前**就位仍不被 TIS 枚举。
- 证据：`TISCreateInputSourceList` 282 源含 Sogou，唯独无我们；`TISFileInterrogator` 报 `inputSourceTableCountSys 0`；系统内 IME 均为 `.app` + Developer ID。
- 本次改：`Info.plist` 双写顶层 `tsInputModeListKey` + `ComponentInputModeDict`、加 `LSBackgroundOnly`、per-mode 图标；bundle 名改 ASCII `Yinghuo.app`。
- 待验证：重启/重登后能否出现；否则下一步试 `/Library/Input Methods/`（sudo）。

### 2026-10-08 · pi（T-M3-02 Swift/IMK 宿主）
- 新建 `platforms/macos/`：`main.swift`/`InputController.swift`/`CandidateWindow.swift`（纯代码 `NSPanel`）/`ImeSession.swift`/`Config.swift` + `build.sh` + `Info.plist` + README + 诊断工具 + FFI 冒烟。
- 扩展 `ime-ffi`（ADR-022）：`ime_session_new_with_data` / `_buffer` / `_set_mode` / `ime_config_init`；`ime_session_key` 成功返回 `IME_KEY_*`。
- 验证：`build.sh` 产出并 ad-hoc 签名；`run-ffi-smoke.sh` 实测 `wq→你`、`nihao→你好`；`make verify` 全绿（82 单测）。
- **人工装载发现**：`.inputmethod` 不被 macOS 13 扫描（LaunchServices `-10811`）→ 改产 **`.app`**（+ `PkgInfo`/图标/本地化），且换 bundle 必须**注销/重登**。
- 遗留：注销/重登后的实际添加 + TextEdit 打字仍待人工确认；`TBD-4` 包名暂定。

### 2026-10-08 · pi（T-M3-01 `ime-ffi` C ABI）
- 新建 `crates/ime-ffi`（cdylib+staticlib）：会话 ABI + 配置 ABI；入口全部 `catch_unwind`、坏输入返回错误码。
- `include/ime.h` + `module.modulemap`；C 冒烟（clang 链 staticlib）+ Swift `import ime` typecheck 均通过。
- 真实 `unsafe` 严格只在 `ime-ffi`（其余 crate `forbid`）。`make verify` 全绿（78 单测；135 产物零网络符号）。
- 遗留：FFI 会话暂用内置样本引擎（真实数据路径留 T-M3-02）；`ime_session_page` 为 no-op（翻页属 P1-M4）。

### 2026-10-08 · pi（P1-M2 完成：T-M2-01…04）
- `ime-config`（配置子系统，四条铁律 R1–R4）+ `ime-pinyin`（`PinyinBackend` + 内置兜底）+ 反查首选 + `ime-config` 接入 `ime-cli`（改 config 即时生效）。
- `inputx-pinyin` spike：**不接入**（体积 4.2–22.8 MiB ≫ 0.6 MB 预算），终局自研 FSA（ADR-008 复核）；报告 `docs/reviews/002`。
- 验收通过：`nihao→你好`、`wo→我`、`nh→你好`、`wq→你`（混输）；`make verify` 全绿。

### 2026-10-08 · pi（P1-M1 完成：自建码表）
- 编码器全规则 + 单字表（27,823 字，双 oracle GB1 100%）+ 词组多候选表（jieba 词频）+ 内置核心 491,854 B ≤ 0.6MB。
- 关键决策：ADR-016（自建 + oracle）、ADR-017/018/019（结构/末笔独立来源不可得 → 多 oracle 验证）、ADR-020（字根来源改 D3 拆字）、ADR-021（多候选）。
- `ime-table`/`ime-cli` 接入正式码表；`wq→你`、`kwwl→中华人民共和国` 实测通过。
