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
| 最后更新 | 2026-10-09（首版实现全面梳理完成，新增待办与交接） |
| 更新者 | Codex |
| 当前阶段 | **macOS首版收尾：报告006发现需求/实现差距，先按待办补齐；实机验收由用户稍后安排** |
| 当前分支 | `codex/fix-acceptance-input-boundaries`；用户授权持续推进 macOS 发布 |
| 活跃 PR | PR #7已合并；main `6d7e8435`；定稿公证CI `37918189811`全绿；仓库保持private，无公开Release |
| 最近一次 `make verify` | ✅ 本轮完整通过：100 单测 + 1 doctest、fmt、Clippy、deny（公告/依赖/许可/来源）、125 产物零网络符号；Swift 预览构建/按键冒烟及桌面交互通过 |


## 1. 三十秒摘要

- **萤火虫**：跨平台、开源可审计、默认离线、只做核心输入的中文输入法（五笔优先，**默认混输**）。Rust 引擎 + 窄 C ABI + 平台薄宿主；**GPL-3.0-or-later**。
- **现在**：P1-M0（引擎骨架）、P1-M1（自建码表）、P1-M2（配置 + 拼音 + 混输）**全部完成**；P1-M3 已完成 `ime-ffi`（C ABI）与 **Swift/InputMethodKit 宿主**（编译/打包/FFI 冒烟通过）。
- **下一步**：读 `docs/reviews/006-macos-mvp-gap-review.md`；先闭环TSV/排序数组与原设计差异（MVP-01），再按顺序补候选来源、配置即时刷新与错误反馈。用户本轮要求先记录待办和交接，之后继续实施。
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

- 官方图标/6d7e8435候选已定稿；用户确认实体输入、图标及分页/取消/失焦/原码回车等正常。签名公证、11.25MB包体、实际ZIP离线复现已通过，无正式Release。
- 核心功能已实现不等于首版完整验收；新增MVP-01…14待办见报告006，重点是候选来源显示、配置即时刷新/错误反馈、数据结构约定及解析器fuzz缺口。
- 完整verify最近通过100单测+1 doctest、125产物扫描；满容量五会话22000键AppKit预检最大13.331ms、结束27.86MiB，非正式IMK端到端结果。
- 用户已安排词库/重启/长时间多应用等实机验收稍后进行；候选暂留用户域，验收结束移除，日常开发仍独立窗口。

## 4. 下一步（可执行，按优先级）

1. **MVP-01/12**：对照报告006与ADR-015明确实际TSV/排序数组是否保留，追加决策并同步方案；不要先迁移引擎或直接勾选.imedict交付。
2. **MVP-02→03→04**：逐项补候选来源显示、无按键配置刷新、错误反馈。协议/行为变更先ADR，配置任务读配置Skill；每项独立验证及PR。
3. **MVP-06…10**：解析器fuzz、组合长度/资源边界、词库锁恢复、正式数据加载诊断、CI审计完整性；先复现，避免操作真实词库。
4. **MVP-11/05**：发布材料与长期保管；实机DoD由用户安排稍后。C级兼容/空闲优化不扩首版范围。

## 5. 待决 / 阻塞

| 编号 | 问题 | 是否阻塞 |
|---|---|---|
| REV-1…3 | 交叉审核有条件通过；REV-4/TBD-4名称仍未正式关闭 | 否 |
| TBD-1 | 词频数据源 — ✅ 已定 `fxsjy/jieba`（D10，MIT），ADR-021 | 否 |
| TBD-2 | 五笔98 / 新世纪 / 郑码数据源 | 否 |
| TBD-3 | ✅ ADR-029：有界 TSV v1，用户词库与学习已实现 | 否 |
| TBD-4 | 英文/包名（`yinghuo` vs `lampyris`） | 否 |
| TBD-5 | 结构/末笔**独立**数据源 — 暂无可用的 GPL-3 兼容来源；以多 oracle 交叉验证替代（ADR-019），字根来源用 D3 拆字（ADR-020） | 否 |
| **SIG-1** | **签名/公证要求**：✅ 已定 —— macOS 26/27 强制「Developer ID + hardened runtime + 公证」；未公证的 Developer ID 被 LaunchServices 判 `is not trusted`、TIS 静默不显示（Phase 1「不签名」前提不成立） | 不再阻塞；ADR-032 与签名/公证脚本已接入；新候选待实际验证 |
| **SIG-2** | ✅ 已关闭：ADR-023 新包重启后枚举/选择正常，TextEdit/Safari 用户实测通过；经典 IMK `.app` 可用 | 否 |

### 本次候选与执行状态

- 当前正式验收包：CI37918189811，源码6d7e8435，11,251,870字节；SHA-256 `16b8105382d43780e7dbe35fe3b1a78386ab52b96f92475858bb5b882d75a3b2`。签名/staple/Gatekeeper与离线复现通过，ditto保留0755，用户域安装、重新添加并选中，安装当轮PID4838运行，图标一致/IP采样为空；旧包备份bundle.iOIE1M。用户确认实体输入和图标正常；未单独明确亮暗模式逐项结果。
- 旧a9bf912已签名公证待传ZIP保留为历史审核资产；已被新的性能优化取代，不应上传旧包作为最新版。用户改用 GitHub Actions 团队 API 密钥，按 CI-ACCEPTANCE.md 一次配置后在 main 自动构建/签名/公证当前版本。
- 用户2026-10-09明确授权本次公证上传、当前用户临时安装验收后移除。用户指定不采用 App 专用密码，改用 CI 的团队 API 密钥，仓库Secrets已生效；授权仍有效，当前仅用户目录临时安装6d7e8435，验收结束须移除。
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
| 当前/验证机 | macOS **27.0**（26A428）、**Apple Silicon arm64**；Xcode **27.0**（27A266a） |
| 签名身份 | ✅ `Developer ID Application: <证书名称> (<Team ID>)` ；CI仓库Secrets签名/API公证已验证，本机profile不作为依赖 |
| Rust | ✅ 已装 rustup + **1.98.1**（`rust-toolchain.toml` 固定）；target `aarch64-apple-darwin` |
| 宿主工具链 | Xcode 27 的 `swiftc`/`codesign`/`xcrun notarytool 1.1.3`/`stapler`；`make` 可用 |
| 输入法现状 | 用户域临时安装6d7e8435；用户确认实体输入和图标正常，上一轮采样PID1007；PID会随重启变化。ABC/搜狗保留；验收结束移除临时输入源与bundle，保留配置/词库 |
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

### 2026-10-09 / Codex：文档提交前敏感信息检查
- 本次11份文档未发现密钥/令牌；扫描708个本地历史blob的命中均为格式判断或fixture，未发现实际凭据。
- 本次文档个人目录/具体签名身份改通用示例；private确认，完整verify通过；准备提交推送当前分支。
- 此检查未覆盖远端独有引用及Actions日志/附件；未重写历史，既有公开证书身份不属于私钥。

### 2026-10-09 / Codex：首版要求对照与交接
- 报告006建立功能/验收矩阵及MVP-01…14待办；发现来源显示、配置刷新/错误反馈、fuzz及数据结构决策缺口。
- ROADMAP/backlog链接新队列，已冻结官方设计与当前公证候选保持；实机验收由用户后续安排。
- 本轮完整make verify通过（100单测+1 doctest、125产物扫描）；仅文档，未改代码/配置/词库/安装；下一轮先MVP-01。

### 2026-10-09 / Codex：发布清单与文档收尾
- 用户安排实机验收稍后进行；新增发布清单，区分已有证据、实机待办与后续增强。
- 修正宿主README的翻页/主题/架构旧说明和CI首次公证旧状态，任务卡补充现有证据。
- 已安装公证候选同版本预检通过且不写目录；无代码或配置改动，无Release，暂留候选。

### 2026-10-09 / Codex：定稿反馈与压力复核
- 用户确认实体输入与图标正常；正式宿主PID1007物理占用27MB/峰28MB，IP样本为空。
- 完整verify通过；满容量五会话22000键无超16ms，P95 5.912ms、最大13.331ms，结束27.86MiB。
- 词库持久化/导入导出保护测试通过；正式菜单及重启保留、长期多应用IMK待验收，保持临时安装。

### 2026-10-09 / Codex：定稿候选安装
- 用户确认设计定稿；修正CI旧V4比较路径，完整verify和两宿主资源核验通过，PR #7合入main6d7e8435。
- CI37918189811签名公证/离线复现全绿；11.25MB包本机核验后临时安装，选中且安装当轮PID4838运行。
- IP采样为空；RSS单次33.1MiB，菜单实际亮暗、实体输入及完整性能/词库DoD待验收。

### 2026-10-09 / Codex：官方配色与macOS导出
- ADR-054采用深松石绿/浅玉白/柔金，保留旧深蓝；官方1024不透明母版及透明外围macOS导出分开保存。
- 生成脚本/ICNS/图标文档同步；完整verify及两宿主构建冒烟通过，PR #7更新；未替换已安装包。
- 配色参照Apple HIG；Icon Composer分层外观资源未交付，菜单实际暗黑着色仍未验收。

### 2026-10-09 / Codex：官方标识统一
- 用户确认状态栏V5已刷新，要求其成为官方标识；ADR-053统一项目/两宿主图标，历史版本保留。
- 安装包菜单字节一致及模板标记true；暗黑样式不变的颜色/对比细节已询问，尚不判定故障或验收通过。
- 官方应用PNG/ICNS已生成，完整verify和构建验证进行；已安装包不替换。

### 2026-10-09 / Codex：V5安装复核准备
- 按用户要求核验/安装bd7162d5公证包，旧版备份bundle.aPvadq，配置词库保留。
- 重新添加并选中萤火虫，PID9915运行、0755、模板标记及资源一致，无IP连接；TextEdit准备就绪。
- 实体输入及系统菜单亮暗清晰度待用户复核，未判定通过。

### 2026-10-09 / Codex：菜单选定V5
- 用户选择菜单V5，ADR-052接入18pt/2x模板；应用仍为V4，保留全部备选。
- 发布源码保留V5母版，生成脚本同步；完整verify与PR #6检查通过；CI37912811458签名/公证/离线复现/附件全绿，已安装2fba8a02暂未替换。

### 2026-10-09 / Codex：交互验收通过与菜单版本比选
- 用户确认失焦清理、翻页选择、回车原码及空格中文全部通过，报告005同步。
- 新增菜单V3–V5，连同V2统一亮暗/18pt对比；透明母版及18/36px资源留assets/icons，等待用户选型，未替换已安装包。
- 图标衍生/AppKit预览及文档差异检查通过；完整DoD其他项仍未完成。
