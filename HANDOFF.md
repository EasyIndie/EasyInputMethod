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
| 最后更新 | 2026-10-09（组织签名凭据接入） |
| 更新者 | Codex |
| 当前阶段 | **P1-M3 发布工程 + P1-M4 最终验收；日常独立窗口调试，系统输入法未安装** |
| 当前分支 | `codex/fix-macos-registration`；用户授权持续推进 macOS 发布 |
| 活跃 PR | 草稿 PR #1：https://github.com/EasyIndie/EasyInputMethod/pull/1；66a2d87 远端 Linux/macOS 全绿；运行37851494863 |
| 最近一次 `make verify` | ✅ 本轮完整通过：99 单测 + 1 doctest、fmt、Clippy、deny（公告/依赖/许可/来源）、125 产物零网络符号；Swift 预览构建/按键冒烟及桌面交互通过 |


## 1. 三十秒摘要

- **萤火虫**：跨平台、开源可审计、默认离线、只做核心输入的中文输入法（五笔优先，**默认混输**）。Rust 引擎 + 窄 C ABI + 平台薄宿主；**GPL-3.0-or-later**。
- **现在**：P1-M0（引擎骨架）、P1-M1（自建码表）、P1-M2（配置 + 拼音 + 混输）**全部完成**；P1-M3 已完成 `ime-ffi`（C ABI）与 **Swift/InputMethodKit 宿主**（编译/打包/FFI 冒烟通过）。
- **下一步**：T-M3-03 固化安装/签名/公证流程与 SBOM；T-M3-04 本地及远端 Linux/macOS 已通过。用户指定后续开发调试统一运行 `make macos-preview`；未经再次要求不重装系统输入法；经典 IMK 宿主已实机验证，无需 appex 改造。
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

- 交互功能已实现：分页、实时配置、中文标点/全半角、用户词库与学习（ADR-025…029）。默认核心词表和有界查询降低内存；五会话空词库约16.6MiB；满容量合成用户词库共享快照后约22.1MiB / P95 0.775ms，学习最大13.196ms；不代表完整 GUI DoD。

**P1-M3**：T-M3-01、T-M3-02、T-M3-05 已完成；macOS CI 本地及远端已通过；安装/卸载及签名、公证、源码/SBOM 打包脚本已实现并通过静态/拒绝路径检查，最新66a2d87本地审核包14,343,472字节（packaging/out/candidate-arm64.YG35db），完整源码/vendor/许可/SBOM/SHA；实际 ZIP 离线重建的去签名程序和默认数据逐字节一致。

- T-M3-05 独立窗口完成：`make macos-preview`；自动检查 `./platforms/macos/dev-preview.sh --smoke-test`。debug 增量构建，不需要公证/安装/重启；仍需正式宿主验证 IMK 系统集成。
- ADR-023 修正注册标识；此前签名、公证、系统安装及实机验收通过。当前已按用户要求卸载，见 §7。
- 用户重启后，TIS 稳定枚举 1/337，选择返回 0；用户实体键盘确认 TextEdit/Safari 的五笔 `wq→你`、拼音兜底 `nihao→你好` 正常。
- SIG-2 关闭，经典 `.app` 可用。详细证据及历史失败记录见 T-M3-02 任务卡。

## 4. 下一步（可执行，按优先级）

1. **P1-M3**：仓库已在 EasyIndie（private），组织7个APPLE_* Secrets可见，证书/密码已添加；ADR-044映射工作流并兼容p8文本/Base64，待合入main首次实际签名公证。公开初审见 docs/reviews/004-public-readiness.md，未修改可见性。
2. **P1-M4**：ADR-041 后满容量五会话22000键预检27.24MiB、首键5.420ms / 最大8.718ms，IP连接采样为空；重打审核包并进行正式 IMK 多应用验收。
3. **P1-M4**：发布候选包的正式 IMK 多应用交互、性能与用户词库验收；T-M3-04 远端检查已通过。
4. **P1-M5**：准备可复现构建说明、SBOM、许可附件与零外联证据。

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

### 本次候选与执行状态

- 当前审核包：`packaging/out/candidate-arm64.YG35db/Yinghuo-0.1.0-arm64.zip`，源码66a2d87，14,343,472字节，SHA-256 `e6fd3bd3cf02095c95250f541a3c8f824459ee3df643f8c929ea98e4d1ed85f3`；unsigned，仅供审核。离线重建逐字节一致。
- 旧a9bf912已签名公证待传ZIP保留为历史审核资产；已被新的性能优化取代，不应上传旧包作为最新版。用户改用 GitHub Actions 团队 API 密钥，按 CI-ACCEPTANCE.md 一次配置后在 main 自动构建/签名/公证当前版本。
- 用户2026-10-09明确授权本次公证上传、当前用户临时安装验收后移除。用户指定不采用 App 专用密码，改用 CI 的团队 API 密钥，仓库配置待完成；授权仍有效，系统/用户目录均无 Yinghuo.app。
- 用户已明确授权 GitHub 上传，分支推送成功并创建草稿 PR #1；HTTP 400 通过固定长度 HTTP 请求解决。未合并或发布。

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
| 代码 | ✅ crates：`ime-core` `ime-table` `ime-pinyin` `ime-config` `ime-ffi` `ime-cli` `wubi-encoder`；**99 单测 + 1 doctest**；`platforms/macos/` Swift 宿主 |

## 8. 接手清单（新会话开始时）

- [ ] 读 `AGENTS.md`（铁律 / 工作流 / 约定）
- [ ] 读本文件
- [ ] 看 `ROADMAP.md` 当前进度
- [ ] 读与本次任务相关的 `docs/`（P1-M3 看 `docs/技术方案.md` §5/§5.3、`docs/配置架构.md` §9）
- [ ] 先跑 `make verify` 确认基线
- [ ] 有歧义 → **先问，不要猜**

## 9. 会话日志（倒序，保留最近 10 条；更早见 git 历史）

### 2026-10-09 · Codex（组织凭据接入）
- 用户已添加证书/密码，确认组织APPLE_*共7项可见；ADR-044将5项映射到签名脚本。
- API私钥兼容完整PEM或Base64；模拟成功/失败/清理及PEM路径通过，make verify全绿。
- 专用工作流尚不在main，真实签名公证仍待合入后首跑；未合并/公开/安装。

### 2026-10-09 · Codex（组织与公开初审）
- 确认仓库已属 EasyIndie，private，无需迁移；604个本地历史blob常见凭据模式扫描无命中。
- 组织可见5个APPLE_*名称与CI要求不同，缺可见p12/密码；签名链路尚未具备。
- 可公开但待日志/个人信息复核、CI加固与分支保护；报告004，本次无公开/合并/发布。
- 仅文档记录，未提交；沿用上轮验证，本轮未重跑make verify。

### 2026-10-09 · Codex（自动验收出包）
- ADR-043：PR 上传无凭据审核包；main 专用 CI 使用 p12 + 团队 API p8 自动签名/公证/复现并上传验收附件，不公开 Release。
- Secrets 仅签名步骤提供，临时钥匙串/私钥退出与 always 清理，PR/fork 不使用密钥。
- YAML/脚本语法、缺失凭据拒绝/空清理、本地 make verify 全绿；08f2486 远端 CI 全绿（37854155174），审核包上传/相对SHA/清理模拟通过；真实密钥链路仍待首次跑通。
- 签名身份变量已配置，5个Secrets待用户一次添加；说明 packaging/macos/CI-ACCEPTANCE.md，未安装或上传 Apple。

### 2026-10-09 · Codex（无凭据性能推进）
- 收缩词表构建容量；ADR-041 拼音索引共享音节/词文本，公开接口与排序/首选读音不变。
- 满容量五会话窗口预检28.24MiB、首键6.465ms / 最大6.272ms；99单测、窗口冒烟、make verify 全绿。
- 修正探针主循环/释放池；无收益借用排序与固定视图实验保留临时源码/补丁（ADR-042未采纳），无新增依赖。
- 持续探针修正整段释放池后22000键稳定27.24MiB、最大8.718ms，IP采样为空；新版66a2d87审核包14,343,472字节，离线重建逐字节一致，远端CI全绿；公证等凭据。

### 2026-10-09 · Codex（发布授权与远端验证）
- 用户明确授权 GitHub 上传/草稿 PR、本次 Apple 公证及临时用户域安装验收后移除；PR #1 已创建。
- 公证因钥匙串缺少 yinghuo-notary profile 尚未上传；用户选择先推进其他准备，未安装。
- 首轮 CI 工具链缺参已修复；a053314 远端 Linux40秒/macOS1分35秒全绿，包含真实 AppKit 冒烟与源码离线重建。
- 满容量内存与正式 IMK 验收待完成；无合并或公开发布。

### 2026-10-09 · Codex（用户词库共享快照）
- ADR-039：有界 Weak 快照缓存，写入发布新 Arc，失焦释放旧版本；激活预加载，配置仍唯一。
- 满容量合成词库/五会话22.09MiB，按键最大9.075ms；学习最大13.196ms，失焦后27.73MiB。
- 98单测、两宿主构建、真实 AppKit 冒烟与 make verify 全绿；完整 GUI/正式客户端仍待验收。
- ADR-040 复用标签/激活预热：满词库首键5.968ms、P95 4.356ms / 最大5.682ms、32.61MiB；内存与正式 IMK 待验收，未安装或上传。

### 2026-10-09 · Codex（最大词库查询边界）
- ADR-038：用户前缀最多256个借用条目后再分配，频次每候选只计算一次；排序优先级与精确命中保留。
- 10000条/1.98MB合成词库五会话：最大按键从19.43降至10.86ms；稳态仍36.67MiB，下一步共享用户词库快照。
- 96单测、两宿主构建/独立冒烟、make verify 全绿；性能 DoD 仍不勾选。

### 2026-10-09 · Codex（长候选边界）
- ADR-037：超宽候选自动竖排，长词截断/tooltip；整窗尺寸及原点限制于可见屏幕，选字文本完整。
- 真实 AppKit 冒烟通过窄屏/边缘长词与普通横排回退；两宿主构建、make verify 通过。
- 下一步最大用户词库与候选渲染性能检查，正式客户端 DoD 保持未完成。

### 2026-10-09 · Codex（预编辑取消边界）
- ADR-036：正式菜单操作同步清除客户端 marked text/组合/候选；模式保存失败不切换。独立面板前也取消组合。
- 失焦/显式复位重置引号配对，不改变模式/临时中英全半角；普通选字和取消不重置配对。
- 94单测、两宿主构建、真实预览及 make verify 全绿；正式客户端仍待最终安装验收。

### 2026-10-09 · Codex（多会话内存）
- ADR-035：Arc 共享默认只读词表，FFI 最多4组 Weak 缓存；组合/选项/用户词库独立。
- 五会话稳态从65.89降至16.64MiB；2200键 P95 0.481ms。快照更新、选项隔离与释放测试通过。
- 两宿主构建/真实预览及 make verify 全绿；CLI 临时文件隔离修复单独提交。
- 下一步正式宿主预编辑边界与 GUI 性能；完整 DoD 未完成，未重新安装或上传。

