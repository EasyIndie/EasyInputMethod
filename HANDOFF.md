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
| 最后更新 | 2026-10-09（恢复宿主执行权限，菜单模板适配推进） |
| 更新者 | Codex |
| 当前阶段 | **P1-M3 发布工程 + P1-M4 最终验收；日常独立窗口调试，当前用户临时安装正式候选验收** |
| 当前分支 | `codex/fix-acceptance-input-boundaries`；用户授权持续推进 macOS 发布 |
| 活跃 PR | PR #4已合并，main c447760d，CI37880942501全绿；PR #1 已按用户授权合并：https://github.com/EasyIndie/EasyInputMethod/pull/1；main efa4b59；PR #2/#3已合并；main 7d9cf788，验收CI 37877336887全绿，Apple Accepted及Gatekeeper通过 |
| 最近一次 `make verify` | ✅ 本轮完整通过：100 单测 + 1 doctest、fmt、Clippy、deny（公告/依赖/许可/来源）、125 产物零网络符号；Swift 预览构建/按键冒烟及桌面交互通过 |


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

1. **P1-M3**：仓库已在 EasyIndie（private），组织7个APPLE_* Secrets可见，证书/密码已添加；ADR-044映射工作流并兼容p8文本/Base64，用户保持private并配置仓库Secrets；ADR-045修复钥匙串搜索/指纹签名后，37877336887自动签名/公证/staple/Gatekeeper/离线重建/附件上传全通过。已临时安装并添加/选中正式候选，宿主启动；用户实体键盘确认TextEdit候选/“你你好”；AX撤销/重做通过；其余多应用及退格/Esc/失焦等待用户测试，见报告005。公开初审见 docs/reviews/004-public-readiness.md，未修改可见性。
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

- 当前正式验收包：CI37880942501，源码c447760d，8,369,098字节，SHA-256 `2e751fbd9001f08786b7f99978cb1edbcb3651e477087d9172620c6c67e900f7`；已公证/离线复现通过；上次Python解压丢失执行权限导致重启仍无法输入，已恢复0755且宿主PID2380启动，实体键盘待确认。
- 旧a9bf912已签名公证待传ZIP保留为历史审核资产；已被新的性能优化取代，不应上传旧包作为最新版。用户改用 GitHub Actions 团队 API 密钥，按 CI-ACCEPTANCE.md 一次配置后在 main 自动构建/签名/公证当前版本。
- 用户2026-10-09明确授权本次公证上传、当前用户临时安装验收后移除。用户指定不采用 App 专用密码，改用 CI 的团队 API 密钥，仓库Secrets已生效；授权仍有效，当前仅用户目录临时安装c447760d，验收结束须移除。
- 用户已明确授权 GitHub 上传，分支推送成功并创建草稿 PR #1；HTTP 400 通过固定长度 HTTP 请求解决。PR #1–4已合并，未公开Release。

## 6. 必须知道的坑与硬约束

**铁律（见 `AGENTS.md` §2）**：核心不联网；`forbid(unsafe_code)`（仅 `ime-ffi`）；配置只走 `ime-config`（禁 `UserDefaults`/注册表/第二文件）；任何数据先登记许可。

**实操坑（本轮踩过，务必记住）**：

- ⚠️ 发行ZIP必须用Finder/ditto保留执行权限；Python zipfile.extractall把程序变0644，签名仍通过但无法启动。安装器现拒绝损坏权限。

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
| 输入法现状 | 当前临时安装 ~/Library/Input Methods/Yinghuo.app（c447760d），系统设置已重新添加并选中，旧宿主已停止，新宿主未自动启动，需重登/重启；旧7d9cf788用户确认退格/Esc、多应用、模式、反查通过，失焦失败；修复7756082/5faa281经PR #4合并，CI37880942501全绿，c447760d已安装待重登回归。ABC/搜狗保留；验收结束须移除输入源与用户域bundle，保留配置/词库 |
| 数据 | `data/generated/` 已生成 `wubi86-core.tsv` / `pinyin-chars.tsv` / `pinyin-words.tsv`（8.4MB 不入库；可由 fetch 脚本 + `ime-pinyin --example generate` 复现） |
| 代码 | ✅ crates：`ime-core` `ime-table` `ime-pinyin` `ime-config` `ime-ffi` `ime-cli` `wubi-encoder`；**100 单测 + 1 doctest**；`platforms/macos/` Swift 宿主 |

## 8. 接手清单（新会话开始时）

- [ ] 读 `AGENTS.md`（铁律 / 工作流 / 约定）
- [ ] 读本文件
- [ ] 看 `ROADMAP.md` 当前进度
- [ ] 读与本次任务相关的 `docs/`（P1-M3 看 `docs/技术方案.md` §5/§5.3、`docs/配置架构.md` §9）
- [ ] 先跑 `make verify` 确认基线
- [ ] 有歧义 → **先问，不要猜**

## 9. 会话日志（倒序，保留最近 10 条；更早见 git 历史）

### 2026-10-09 / Codex：恢复执行权限与菜单模板
- 重启失败根因为程序0644；恢复0755并启动PID2380，签名有效且无IP连接，实体输入待确认。
- ADR-050安装权限防护、ADR-051原生模板/18pt菜单图标；完整verify通过，实机亮暗回归待新候选。

### 2026-10-09 · Codex（修复候选等待重登）
- PR #4本地/远端验证及审核ZIP离线复现通过，合入main c447760d；签名公证CI37880942501全绿。
- 新ZIP8,369,098字节/SHA核验通过；旧源移除/旧宿主停止并备份，新包用户域安装/重新添加。
- 版本/ICNS/菜单PNG一致；热替换后宿主未启动，无新项目崩溃报告，需用户重登/重启后实体回归。
- 当前暂留安装，复测失焦/回车字母/a分页/菜单标志；结束移除，private保留，无Release。

### 2026-10-09 · Codex（验收缺陷与图标修复）
- 用户确认退格/Esc、多应用、模式切换、反查通过；失焦失败，回车强制中文，分页不明。
- ADR-046–048：统一回车提交原码、补组合结束/客户端失活清理、多页页码提示；真实a翻页/回车预览及100单测/make verify通过。
- ADR-049：V1–V5去白框修订保留原稿，V4 ICNS/透明菜单模板接入，源码归档仅排除非构建图稿。
- 7756082/5faa281分别提交输入/图标修复，新包待CI及实体回归；旧用户域临时安装仍保留。

### 2026-10-09 · Codex（正式候选临时安装）
- CI包14,086,071字节，SHA及本机签名/公证/Gatekeeper通过，按授权临时安装用户域。
- 系统设置添加后TIS选中，正式宿主PID57928启动，初始RSS约27.15MB/IP连接采样空。
- 用户实体键盘确认TextEdit候选/你你好，AX撤销/重做通过；其余应用待测，报告005。
- 六次IP采样空，物理占用24.0M/峰24.9M；临时安装保留，结束须移除；未发布。

### 2026-10-09 · Codex（自动公证链路跑通）
- 诊断确认身份有效；ADR-045扩展临时钥匙串搜索列表并按唯一指纹签名，退出恢复列表。
- PR #2/#3检查全绿后合并；本地make verify/模拟清理/身份拒绝/恢复测试通过。
- main7d9cf788 CI37877336887全部成功：Apple Accepted、staple、Gatekeeper、离线逐字节复现及附件上传。
- 附件11592738352已下载/private/tmp/yinghuo-ci-acceptance-37877336887，SHA通过；private保留，未安装/公开Release。

### 2026-10-09 · Codex（仓库凭据首验）
- 用户决定保持private，7项APPLE_*仓库Secrets可见，重跑37873545347。
- 验证/构建通过，5项Secrets已传入，p12成功导入1个身份；codesign找不到配置的Developer ID身份。
- 尚未访问Apple或产验收包，临时材料清理成功；需核对导出证书名称/有效性。

### 2026-10-09 · Codex（main 首次出包）
- 用户授权后确认16c77ac的Linux/macOS检查全绿，PR #1已合并到main efa4b59。
- 首次验收CI 37873545347验证/构建/清理通过；5项组织Secrets全部为空，在签名前拒绝。
- 符合Free组织私有仓库组织Secrets限制；尚未访问Apple，未出签名包/安装/公开。
- 待决定仓库Secrets、组织升级或公开后的路径；本次只读跟进及交接记录。

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

