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
| 最后更新 | 2026-10-08 |
| 更新者 | pi |
| 当前阶段 | **P1-M3：T-M3-01 ✅；T-M3-02 代码 ✅，装载验收移交「有 Xcode + 开发者帐号」的另一台设备** |
| 当前分支 | `main`（⚠️ **有本轮未推送 commit**，见 `git log --oneline origin/main..HEAD`；接手前先 push 或迁移仓库） |
| 活跃 PR | 无 |
| 最近一次 `make verify` | ✅ 全绿（fmt + clippy -D warnings + **82 单测 + 1 doctest** + cargo-deny + 隐私断言） |

## 1. 三十秒摘要

- **萤火虫**：跨平台、开源可审计、默认离线、只做核心输入的中文输入法（五笔优先，**默认混输**）。Rust 引擎 + 窄 C ABI + 平台薄宿主；**GPL-3.0-or-later**。
- **现在**：P1-M0（引擎骨架）、P1-M1（自建码表）、P1-M2（配置 + 拼音 + 混输）**全部完成**；P1-M3 已完成 `ime-ffi`（C ABI）与 **Swift/InputMethodKit 宿主**（编译/打包/FFI 冒烟通过）。
- **下一步**：在**另一台有 Xcode + Apple 开发者帐号的 Mac** 上，用**真实签名**（Developer ID / Apple Development）构建并装载 `platforms/macos/`，验证输入法出现且能打字；结论回写 `docs/tasks/T-M3-02.md`。详见本文件 §4。
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

**P1-M3**：`ime-ffi` ✅；**T-M3-02 代码完成且自测通过**（编译/打包；`run-ffi-smoke.sh` 实测 `wq→你`、`nihao→你好`），**装载验收已移交到另一台设备**。
> ⛔ 本机（macOS 13.7.8 / 仅 CLT / **0 个签名身份**）**无法完成装载**：系统不枚举非 Apple 签发的输入法（我们的 ad-hoc、自签+系统信任、甚至苹果原版 Ainu 副本都不出现；只有 Developer-ID 签名的搜狗可见）。完整证据/结论见 `docs/tasks/T-M3-02.md`「人工验证记录」。
> ⚠️ **接手前必须先拿到本轮 commit**（push 到 origin，或直接拷整个仓库到验证机）——见 §4 第 1 条。

## 4. 下一步（可执行，按优先级）

1. **【交接第一优先】拿到本轮 commit**：本机 `main` 领先 `origin/main`（`git log --oneline origin/main..HEAD`）。在验证机上 `git fetch/pull` 后，确认 T-M3-02 这组 commit 都在（`feat(ffi): load real data…`、`feat(macos): add Swift InputMethodKit host…`、`fix(macos): ship .app bundle…`、`fix(macos): use standard IMK plist…`、`docs(macos): record T-M3-02 install blocker…`、`docs(handoff): hand T-M3-02 install verification…`）。
2. **T-M3-02 装载验收（在「有 Xcode + 开发者帐号」的 Mac 上）**：
   - `./platforms/macos/build.sh` → 产 `build/Yinghuo.app`（当前默认 ad-hoc 签名）；
   - **改用真实身份签名**（不要 ad-hoc）：`codesign --force --deep --sign "Developer ID Application: <你的名字/团队>" build/Yinghuo.app`（或 `Apple Development:`）；
   - 拷到 `~/Library/Input Methods/`（或 `/Library/Input Methods/`），注销/重登；**确保同一 bundle id 只有一份**（别把 `build/` 里的副本也留在机器上被 LaunchServices 登记）；
   - 系统设置 → 键盘 → 文字输入 → 输入法 → 添加「萤火虫」；TextEdit 试 `wq→你`、`nihao→你好`；
   - 佐证：`./platforms/macos/tools/diagnose.sh yinghuo`（看有无 `yinghuo`）；
   - **判定目标**：换真实签名后能否出现 → 确认是否“必须 Apple 签发证书”。
3. **回写结论**：`docs/tasks/T-M3-02.md`；若确需签名 → 新增/更新 ADR（签名策略）、`build.sh`（签名身份可配）、`docs/技术方案.md`。
4. **清理本机残留（当前机器）**：`/Library/Input Methods/` 已只剩 Sogou（无需清）；自签证书信任可能仍在系统钥匙串：`sudo security delete-certificate -c "Yinghuo Local Dev" /Library/Keychains/System.keychain`。
5. **T-M3-03**：安装脚本 + Gatekeeper/手动装载说明（待签名结论明确后）。
6. **T-M3-04**：CI 加 macOS runner（编译 `build.sh`，不装载）。
7. **P2 参考**：自研 FSA 拼音引擎（ADR-008 终局）；修复内置兜底贪心切分漏检超长整句。

## 5. 待决 / 阻塞

| 编号 | 问题 | 是否阻塞 |
|---|---|---|
| REV-1…4 | 交叉审核已完成（`docs/reviews/001.md`） | 否 |
| TBD-1 | 词频数据源 — ✅ 已定 `fxsjy/jieba`（D10，MIT），ADR-021 | 否 |
| TBD-2 | 五笔98 / 新世纪 / 郑码数据源 | 否 |
| TBD-3 | 用户词库存储格式 | 阻塞 P1-M4 |
| TBD-4 | 英文/包名（`yinghuo` vs `lampyris`） | 否 |
| TBD-5 | 结构/末笔**独立**数据源 — 暂无可用的 GPL-3 兼容来源；以多 oracle 交叉验证替代（ADR-019），字根来源用 D3 拆字（ADR-020） | 否 |
| **SIG-1** | **输入法签名要求**：本机实测非 Apple 签发签名不被枚举；是否必须 Developer ID / Apple Development？ | **阻塞 T-M3-02 装载验收 / Phase 1「不签名」前提** |

## 6. 必须知道的坑与硬约束

**铁律（见 `AGENTS.md` §2）**：核心不联网；`forbid(unsafe_code)`（仅 `ime-ffi`）；配置只走 `ime-config`（禁 `UserDefaults`/注册表/第二文件）；任何数据先登记许可。

**实操坑（本轮踩过，务必记住）**：

- ⚠️ **模型名要带 provider**：`deepseek-v4-pro` 在 8 个 provider 下**歧义** → 必须 `--provider cc-switch-deep-seek`；`deepseek-v4-flash` 不歧义。
- ⚠️ **> ~5 MB 的生成文件会让 `git push` 报 HTTP 400**：大表（`wubi86-phrases.tsv` 5.6MB、`pinyin-words.tsv` 8.4MB）**一律 gitignore**，由 `data/sources/fetch-*.sh` + `cargo run --example …` 复现。
- ⚠️ **无 Xcode**（仅 CLT）→ **不能用 IB / Asset Catalog**（`actool`/`ibtool` 是 stub）→ **纯代码 UI**。
- ⚠️ **macOS 输入法必须是 `.app`**（不是 `.inputmethod`），且**换 bundle 后必须注销/重登**（只在登录时扫描，`killall TextInputMenuAgent` 无效）。诊断：`platforms/macos/tools/`。
- ⛔ **当前机器实测：macOS 只枚举 Apple 签发的输入法**（ad-hoc / 自签均不可见；连苹果原版 Ainu 副本也不可见），而 Developer-ID 签名的搜狗可见；本机 `security find-identity -v -p codesigning` 为 0。**→ 换到有开发者帐号的机器验证（见 §4），不要再在当前机器上反复重试**。
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
| 硬件（当前机，已阻塞装载） | macOS **13.7.8**、**Intel x86_64**；2 物理核 / 4 逻辑核，16 GB 内存；**仅 CLT、无 Xcode、0 签名身份** |
| 验证机（接收方） | **有 Xcode + Apple 开发者帐号**（可签发 Apple Development / Developer ID） |
| Rust | 1.98.1（`rust-toolchain.toml` 固定）；target `x86_64-apple-darwin` |
| 宿主工具链 | 当前机：Swift 5.8.1 + InputMethodKit 可编译/链接（实测）；`codesign` ad-hoc 可用；**验证机用 Xcode 自带的 swiftc/codesign** |
| 构建 | `make` 可用（无 `just`）；`cargo-deny`、`cargo-fuzz` 已装 |
| 代码 | ✅ crates：`ime-core` `ime-table` `ime-pinyin` `ime-config` `ime-ffi` `ime-cli` `wubi-encoder`；**82 单测 + 1 doctest**；`platforms/macos/` Swift 宿主 |

## 8. 接手清单（新会话开始时）

- [ ] 读 `AGENTS.md`（铁律 / 工作流 / 约定）
- [ ] 读本文件
- [ ] 看 `ROADMAP.md` 当前进度
- [ ] 读与本次任务相关的 `docs/`（P1-M3 看 `docs/技术方案.md` §5/§5.3、`docs/配置架构.md` §9）
- [ ] 先跑 `make verify` 确认基线
- [ ] 有歧义 → **先问，不要猜**

## 9. 会话日志（倒序，保留最近 10 条；更早见 git 历史）

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

### 2026-10-08 · pi（P1-M0 引擎骨架）
- Rust workspace + `ime-core`（Engine/InputMode/会话状态机）+ `ime-table` + `ime-cli`；11 测试；`make verify` 全绿。
- 发现 `yada` 无预测搜索 → 改定 `cedarwood`（ADR-015）。

### 2026-10-08 · pi（工具链体检 + 派发基建）
- 设备确认：**仅 CLT、无 Xcode**；Swift + InputMethodKit 可编译链接（实测）→ P1-M3 可在本机做（纯代码 UI）。
- 量测/派发：`scripts/dispatch-task.sh`、`usage-report.sh`、`bench-session-vs-workers.sh`；`docs/experiments/` 结论——**独立任务用「每卡新 worker」更省**（N=5 中位数：独立 fresh 37.9k vs reuse 43.6k；强依赖 reuse 快 4.4×）。
- 防护：`--jobs`（CARGO_BUILD_JOBS）+ 磁盘预检（默认 ≥3 GiB）。
