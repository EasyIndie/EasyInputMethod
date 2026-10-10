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
| 最后更新 | 2026-10-11（反馈入口改为完全本地，不打开浏览器，ADR-074） |
| 更新者 | pi |
| 当前阶段 | **功能集已补齐，进入体验打磨 / P2 迭代**；A/B 类 MVP 全部闭环，仅剩 **MVP-05（用户实机）** 与 **MVP-14（外部环境）**；仓库已公开、可发布 |
| 当前分支 | `main`，与 origin 同步（见 `git log --oneline -5`） |
| 活跃 PR | 见 GitHub；仓库**已公开**，**无正式 Release**（首版 `v0.1.0` 待打 tag） |
| 最近一次 `make verify` | ✅ 全绿：122 项测试（含 doctest）、fmt、Clippy、deny、184 产物零网络符号；预览冒烟（含多屏选屏/悬停断言）、宿主构建、离线重建、`make fuzz` 三目标均通过 |

## 1. 三十秒摘要

- **萤火虫 / Lampyris**：跨平台、开源可审计、默认离线、只做核心输入的中文输入法（五笔优先，**默认混输**）。Rust 引擎 + 窄 C ABI + 平台薄宿主；**GPL-3.0-or-later**。
- **现在**：P1-M0…M3 全部完成；**首版功能集已补齐**（五笔/拼音/混输、反查、用户词库与学习、中英/全半角/中英标点/简繁/三模式切换、候选点选与来源标注、配置即时刷新与错误可见、帮助面板）；**MVP 工程收敛 11/11** 完成；仓库公开、Pages 上线、Release/Pages 工作流就绪。
- **下一步**：**体验打磨**（候选窗高分屏/多屏实测、首次引导、点选手感等）＋ **MVP-05 用户实机验收** → 打 `v0.1.0` 发布。
- ⛔ 铁律：核心不联网、`forbid(unsafe_code)`（**仅 `ime-ffi` 例外**）、数据登记许可、配置只走 `ime-config`。

## 2. 已完成（按里程碑；细节见 `docs/tasks/` 与 ADR）

| 阶段 | 成果 | 关键文档 |
|---|---|---|
| 调研 / 方案 | 选型、权威方案、交叉审核（有条件通过） | `docs/技术方案.md`、`docs/reviews/001.md` |
| **P1-M0** | workspace + `ime-core`（Engine/InputMode/会话状态机）+ `ime-table` + `ime-cli` | — |
| **P1-M1** 自建码表 | `crates/wubi-encoder`（五笔86 全规则）+ `data/` 流水线；单字表 **27,823 字**（vs D3 99.98% / vs rime 98.77%，**GB2312 一级均 100%**）；内置核心 `wubi86-core.tsv` **491,854 B** | ADR-016…021 |
| **P1-M2** 配置+拼音+混输 | `crates/ime-config`（Schema/`ArcSwap`/原子写/广播）+ `crates/ime-pinyin`（内置兜底）；混输合并 | `docs/配置架构.md`、ADR-008/009 |
| **P1-M3** macOS 宿主 | `crates/ime-ffi`（会话 + 配置 C ABI）+ `platforms/macos/` Swift/IMK 宿主（`build.sh` 产 `Lampyris.app`） | `platforms/macos/README.md`、ADR-022/023/055 |
| **MVP 收敛** | T-MVP-01…11 全部完成（安全/一致性/性能/CI/文档） | `docs/tasks/mvp-hardening.md`、ADR-061…066 |
| **首版功能集** | 中英（单独 Shift）/全半角（Shift+空格）/标点（Ctrl+.）/简繁（Ctrl+Shift+F）/三模式；候选点选 + 来源标注 + 状态徽标；帮助面板 | ADR-057/067/068/069 |
| **发布工程** | 二进制不含源码 + 同页源码包（GPL §6(d)）、Release + Pages 工作流、仓库公开、分支保护 | ADR-064/065、`.github/workflows/` |

## 3. 进行中

- **✅ 三 PR 已合并 main 并通过统一验收（2026-10-11，pi）**：#9 候选窗 A/C → #10 设置面板 → #11 反馈入口依次合并（合并 commit）；`make verify`、预览冒烟、完整宿主 `build.sh`、main push 的 CI 与 macOS Acceptance Package 均成功。**下一步：实机重装 main 构建做统一真机验收**。
- **✅ 用户反馈入口（T-P2-03，ADR-071，2026-10-11，pi）**：输入法菜单「反馈问题与建议…」→ AppKit 提示 + 本地诊断信息（版本/构建/提交/系统/架构，不含隐私），用户可「复制」或**主动**用系统浏览器打开公开 GitHub Issues；App 自身**零网络、不预填 URL、不上报**；敏感漏洞指向 `SECURITY.md` 私下渠道。
- **✅ 偏好设置面板（T-P2-02，ADR-070，2026-10-11，pi）**：`platforms/macos/Sources/Settings.swift` 非模态 `NSPanel`，**完全由 `ime_config_schema()` 驱动**（零硬编码）；入口＝输入法菜单「偏好设置…」(⌘,)。`OptionSpec`/C ABI 追加 `title_zh`/`enum_labels_zh`；写入只经 `ime_config_set`；`ConfigWatcher` 支持多观察者。顺带修正 enum 列表“空串终止”约定。
- **✅ 体验打磨 A/C（2026-10-11，pi）**：候选窗选屏改为「相交面积最大 → 光标中心 → 首屏」兜底（`CandidateWindow.bestScreenIndex`），修正副屏（负坐标）/跨屏/边缘定位；候选标签加**鼠标悬停高亮**（`CandidateLabel` + `NSTrackingArea`）；两者均补入预览冒烟隔离断言。**B（首次激活轻量引导）未做**，见 §4。
- **✅ T-P2-01 简繁转换（ADR-069，2026-10-10，pi）**：OpenCC `STCharacters`+`STPhrases`（Apache-2.0，固定 commit）→ `data/generated/variant-s2t.tsv`（42,430 条 / 841KB，随包）；配置 `input.chinese_variant` + 快捷键 `hotkey.toggle_variant`（默认 `ctrl+shift+f`）；FFI 边界最长匹配简→繁，引擎/学习仍存简体。登记 D11/D12 + 派生项。
- **✅ MVP 工程收敛 11/11（ADR-061…066）**：见 `docs/tasks/mvp-hardening.md`。
- **✅ 仓库公开 + 发布渠道就绪（ADR-064/065）**：仓库 **public**；Pages 上线 <https://easyindie.github.io/EasyInputMethod/>；main 分支保护（必需 `check`/`macos`/`fuzz`，禁强推/删除）；`release.yml`（tag/手动，二进制+源码同页）/`pages.yml` 就绪；**`v0.1.0` 待打 tag**。
- **⏸ MVP-05 待用户实机**：`docs/macos-release-checklist.md` 有 **13 项实机 DoD 矩阵**（系统/应用/步骤/预期/结果/证据），用户实机后照填即可关闭。不催重启/重装。
- **⏸ MVP-14 待外部环境**：更多 macOS 版本 + Icon Composer 分层图标（需其他机器 / Xcode 27）。
- **⏸ MVP-11 收尾**：二进制包 + 源码包归档到长期位置、确定分发渠道/接收范围（工作流已就绪，待用户操作）。

## 4. 下一步（可执行，按优先级）

**本地迭代（不依赖签名机）**：日常 `make macos-preview`；阶段真机 `./platforms/macos/build.sh --strict --universal` → 拷到 `~/Library/Input Methods/` 并删 `build/` 副本（避影子）→ 选中「萤火虫」实打。macOS 13 上 ad-hoc 即可（ADR-055）。

1. **体验打磨**：**A/C 已完成**（候选窗多屏定位加固 + 悬停高亮，见 §3）；剩 **B 首次激活轻量引导**（提示“按 Shift 切中英”，需确定“只提示一次”的持久化，可能先补 ADR）与候选窗**高分屏/多屏真机实测**（需用户实机；`docs/reviews/007-ux-and-tech-debt.md` §A2 留了栏位）。
2. **MVP-05 实机 DoD 矩阵**：用户按 `docs/macos-release-checklist.md` 逐项填写（唯一剩余 A 类门槛）。
3. **发布 `v0.1.0`**：`git tag v0.1.0 && git push origin v0.1.0` → `release.yml` 建 Release（二进制 + 源码同页）。可先手动 `dry_run` 演练。
4. **P2 迭代**：**设置界面（ADR-070）与用户反馈入口（ADR-071）已完成**；剩字根提示、i18n、emoji 等（见报告 008 §8）；MVP-14 需外部环境。

> **A/B 类缺口（MVP-01…04、06…13）与 MVP-11 已全部闭环**（ADR-057…069）；MVP-05 验收与 MVP-14 依赖用户或外部环境。

## 5. 待决 / 阻塞

| 编号 | 问题 | 是否阻塞 |
|---|---|---|
| REV-1…3 | 交叉审核有条件通过；TBD-4 名称已由 ADR-056 关闭 | 否 |
| TBD-1 | 词频数据源 — ✅ 已定 `fxsjy/jieba`（D10，MIT），ADR-021 | 否 |
| TBD-2 | 五笔98 / 新世纪 / 郑码数据源 | 否 |
| TBD-3 | ✅ ADR-029：有界 TSV v1，用户词库与学习已实现 | 否 |
| TBD-4 | ✅ ADR-056：英文/包名定为 `Lampyris`，bundle `cn.jokerhub.inputmethod.Lampyris` | 否 |
| TBD-5 | 结构/末笔**独立**数据源 — 暂无可用的 GPL-3 兼容来源；以多 oracle 交叉验证替代（ADR-019），字根来源用 D3 拆字（ADR-020） | 否 |
| **SIG-1** | **签名/公证要求**：✅ 已澄清（ADR-055）—— macOS 13 本地 ad-hoc 即可（用户已验收）；分发与 macOS 26/27 仍强制 Developer ID + hardened runtime + 公证 | 不再阻塞；本地迭代无需签名机 |
| **SIG-2** | ✅ 已关闭：ADR-023 新包重启后枚举/选择正常，TextEdit/Safari 用户实测通过；经典 IMK `.app` 可用 | 否 |

### 本次候选与执行状态

- 当前 CI 公证候选：`Lampyris-macos-acceptance-1c08956…`（universal；二进制 ZIP + 源码包 + SHA，约 12.1MB）；签名/staple/Gatekeeper 与离线复现通过。
- 本机（macOS 13 Intel）为**用户域 ad-hoc 安装**（`cn.jokerhub.inputmethod.Lampyris`），已装到最新提交；用户已实体输入验收。
- 仓库**已公开**（2026-10-10）；**无正式 Release**（首版 `v0.1.0` 待打 tag）；Pages 上线、main 分支保护已设。CI 签名/公证凭据配置见 `packaging/macos/CI-ACCEPTANCE.md`（不在本文件记录凭据细节）。

## 6. 必须知道的坑与硬约束

**铁律（见 `AGENTS.md` §2）**：核心不联网；`forbid(unsafe_code)`（仅 `ime-ffi`）；配置只走 `ime-config`（禁 `UserDefaults`/注册表/第二文件）；任何数据先登记许可。

**实操坑（本轮踩过，务必记住）**：

- ⚠️ 发行ZIP必须用Finder/ditto保留执行权限；Python zipfile.extractall把程序变0644，签名仍通过但无法启动。安装器现拒绝损坏权限。
- ⚠️ **模型名要带 provider**：`deepseek-v4-pro` 在 8 个 provider 下**歧义** → 必须 `--provider cc-switch-deep-seek`；`deepseek-v4-flash` 不歧义。
- ⚠️ **> ~5 MB 的生成文件会让 `git push` 报 HTTP 400**：大表（`wubi86-phrases.tsv` 5.6MB、`pinyin-words.tsv` 8.4MB）**一律 gitignore**，由 `data/sources/fetch-*.sh` + `cargo run --example …` 复现。
- ⚠️ **macOS 输入法必须是 `.app`**（不是 `.inputmethod`），本机首次注册/注册元数据修正后需**注销/重启**完成登录扫描；普通代码热替换尚未验收；`killall TextInputMenuAgent` / 删 `IntlDataCache` / `lsregister -f` / `TISRegisterInputSource`（返回 `noErr`）都**不能**免重启触发重扫。日常功能迭代使用独立窗口（ADR-024）。诊断：`platforms/macos/tools/`。
- ✅ **注册标识**：bundle ID 必须带 `.inputmethod.`；当前 `cn.jokerhub.inputmethod.Lampyris`，连接名 `${bundleID}_Connection`（ADR-023/056）。
- ⚠️ **IMK 事件掩码**：IMK 默认**只转发 `keyDown`**；修饰键变化（`flagsChanged`，单独 Shift 必需）必须重写 `IMKInputController.recognizedEvents` 显式声明，并接管 `leftMouseDown` 保留"点击组合外结束组合"。`recognizedEvents` 的 Swift 返回类型是 **`Int`**（写成 `UInt` 会编译失败→装成旧包）。见 ADR-067。
- ⚠️ **`ImeConfig.setString` 会加引号**：只适合字符串/枚举；bool/int 等要用 `ImeConfig.setToml`（裸字面量），否则 `ime_config_set` 返回类型错误、设置静默失败。
- ⚙️ **Swift/Swift 链接坑**：`-whole-module-optimization` 下不能把 `.a` 作位置参数（Swift 5.8 当源码）也不能用 `-L … -lime_ffi`（会链到 cdylib 并把绝对构建路径写进 `LC_LOAD_DYLIB`）；必须 `-Xlinker <lib.a>`。见 ADR-055。
- ⚙️ **universal 构建**：需 `rustup target add aarch64-apple-darwin x86_64-apple-darwin`，再 `./platforms/macos/build.sh --strict --universal`（Rust 用 `aarch64`、Apple 用 `arm64`）。
- ⚠️ **构建后务必看退出码**：`build.sh` 编译失败时不会替换旧 `.app`；只看 `tail -1` 容易把**旧包**当新包装上（本会话踩过）。
- ⚠️ **公证三件套**：`codesign --options runtime --timestamp` → `ditto` 打包 → `xcrun notarytool submit --keychain-profile <profile> --wait` → `xcrun stapler staple`；判定 `spctl -a -vvv -t exec` 应为 `accepted / Notarized Developer ID`。首次常遇 `403` → Account Holder 需在 App Store Connect 接受协议。
- ⚠️ **登录钥匙串**：后台/非 GUI 会话跑 `codesign` 会报 `errSecInternalComponent`；需在 GUI Terminal 跑一次并点"始终允许"。
- ⚠️ **LS 影子副本**：同一 bundle id 若有残留登记，Text Input 会绑定影子副本导致静默失败；装完 `lsregister -dump` 去重。
- **默认拼音为 `pinyin-core.tsv`（256KiB）**：全量词表作为生成输入、不默认装载（ADR-031）；发布不得容忍数据缺失降级。
- ⚠️ **bash + 中文坑**：`$var` 后紧跟全角字符会被当变量名 → 一律写 `${var}`。
- ⚠️ **许可地雷**：`Arphic Public License`（makemeahanzi / hanzi-writer）**GPL 不兼容**；`GPLv2-only` 与 GPL-3 不兼容；**极点五笔 provenance 存疑**（`rime-wubi86-jidian` 仅可测试）。新增数据先登记 `docs/数据来源与许可.md` + `data/sources.toml`。
- ⚠️ **worker 产出不会自动提交**：派发后必须人工复核 + `git add/commit/push`。
- ⚠️ **派发工具**：`./scripts/dispatch-task.sh docs/tasks/<卡> --model <m> [--provider <p>] [--jobs N]`；用量记 `docs/experiments/runs/usage.jsonl`。
- 提交前必须 `make verify` 全绿；第三方 Actions 升级方法见 `CONTRIBUTING.md` §9。

## 7. 环境快照

| 项 | 值 |
|---|---|
| 本机 A（本地迭代/真机验收） | macOS **13.7.8**、**Intel x86_64**；仅 CLT（Swift 5.8.1、无 Xcode）；`security find-identity` 为 0；已加 `aarch64-apple-darwin` + `x86_64-apple-darwin` target |
| 机器 B（签名/新版系统） | macOS **27.0**（26A428）、**Apple Silicon arm64**；Xcode **27.0**（27A266a）；Developer ID 身份与 CI 公证凭据 |
| Rust | ✅ 1.98.1（`rust-toolchain.toml` 固定）；target `x86_64-apple-darwin` + `aarch64-apple-darwin` |
| 宿主工具链 | A：CLT `swiftc`/`codesign`；B：Xcode 27 `swiftc`/`codesign`/`notarytool`/`stapler`；`make` 均可用 |
| 输入法现状 | 本机 A 用户域 ad-hoc 安装（`cn.jokerhub.inputmethod.Lampyris`），已装到最新提交；分发/公证候选由 CI 出 universal |
| 数据 | `data/generated/`：`wubi86-core.tsv` / `pinyin-chars.tsv` / `pinyin-core.tsv` / **`variant-s2t.tsv`**（简繁，841KB，随包）；`pinyin-words.tsv` 8.4MB 不入库，可由 fetch 脚本复现 |
| 代码 | ✅ crates：`ime-core` `ime-table` `ime-pinyin` `ime-config` `ime-ffi` `ime-cli` `wubi-encoder`；**122 项测试（含 doctest）**；`platforms/macos/` Swift 宿主；`fuzz/` cargo-fuzz |

## 8. 接手清单（新会话开始时）

- [ ] 读 `AGENTS.md`（铁律 / 工作流 / 约定）
- [ ] 读本文件
- [ ] 看 `ROADMAP.md` 当前进度
- [ ] 读与本次任务相关的 `docs/`（宿主看 `platforms/macos/README.md`、`docs/配置架构.md` §9、`docs/技术方案.md` §5.3）
- [ ] 先跑 `make verify` 确认基线
- [ ] 有歧义 → **先问，不要猜**

## 9. 会话日志（倒序，保留最近 10 条；更早见 git 历史）

### 2026-10-11 / pi：反馈入口改为完全本地（ADR-074）
- 面板不再调用 `NSWorkspace.open`：只展示诊断信息 + 链接文本，唯一动作是「复制反馈信息」。
- 移除可用性门控，菜单入口**始终显示**（离线可用，无死入口）。
- 文档：ADR-074、`隐私与安全.md` §6、T-P2-03。

### 2026-10-11 / pi：反馈入口卡死修复（异步打开 + 可用性门控；ADR-073）
- 修复：`FeedbackUI` 主线程**同步** `NSWorkspace.open(url)` → 异步 `openExternally`（关闭代理/GitHub 不可达时点菜单不再卡死）。
- 门控：菜单「反馈问题与建议…」仅在 `FeedbackUI.isAvailable`（本地 LaunchServices 判据，**不联网**）时显示。
- 审计：全仓库仅此一处外部打开；其余 `runModal()` 均为用户可关闭模态，无同类阻塞。
- 已知边界：网络层不可达（代理致 GitHub 打不开）在零网络前提下无法识别，入口仍显示但不再卡死。

### 2026-10-11 / pi：开发工作流（分层 CI + DCO + 本地 hooks；ADR-072）
- 新增 `docs/开发工作流.md` + ADR-072；`ci.yml` 分层：`check` 恒跑，`macos`/`fuzz` 仅⾜代码相关变更执行（job 仍上报，避免必需检查卡住）。
- 新增 `make fast` / `make hooks`（pre-push→verify）、`scripts/ci-detect-code-changes.sh`、`.github/workflows/dco.yml`（Signed-off-by，**可见不阻断**）。
- 团队化（CODEOWNERS / 必需 review / merge queue / 覆盖率与基准门禁）**延后**到 MVP 后或首个外部贡献者；未改动现有必需检查与分支保护。

### 2026-10-11 / pi：三 PR 合并 + main 统一验收
- #9（候选窗 A/C）→ #10（设置面板 ADR-070）→ #11（反馈入口 ADR-071）依次以 merge commit 合并；堆叠分支同步 main 后 CI（check/macos/fuzz）全绿。
- main 统一验收：`make verify` ✅、预览冒烟 ✅、完整宿主 `build.sh` ✅；main push 的 CI 与 macOS Acceptance Package 均 success。
- 遗留：本机安装仍是旧构建；需重装 main 产物做**真机验收**（菜单入口/面板/反馈）。

### 2026-10-11 / pi：用户反馈入口（T-P2-03，ADR-071）
- 输入法菜单加「反馈问题与建议…」→ `platforms/macos/Sources/Feedback.swift`：展示本地诊断信息（版本/构建/提交/系统/架构，不含隐私），可复制或**主动**用浏览器打开公开 GitHub Issues；敏感漏洞指向 `SECURITY.md`。
- App 自身零网络、不预填 URL、不上报；`隐私与安全.md` §1 补充说明。冒烟新增链接/诊断断言；`make verify` ✅。

### 2026-10-11 / pi：偏好设置面板（T-P2-02，ADR-070）
- 新增 `platforms/macos/Sources/Settings.swift`：非模态 `NSPanel`，由 `ime_config_schema()` 动态建表（bool/stepper/下拉/文本框），菜单「偏好设置…」(⌘,) 打开；写入只经 `ime_config_set`。
- Schema/ABI：`OptionSpec` 与 `ImeConfigSchemaOption` 追加 `title_zh`/`enum_labels_zh`；修正 `build_schema` enum 列表“空串终止”约定（旧单测只测 mode，靠相邻内存为 0 未暴露）。
- `ConfigWatcher` 改为多观察者（宿主 + 设置面板）。冒烟新增设置断言；`make verify` ✅（184 产物零网络符号）。

### 2026-10-11 / pi：体验打磨 A/C（多屏定位加固 + 悬停高亮）
- A：`CandidateWindow.bestScreenIndex` 按相交面积选屏（副屏负坐标/跨屏/边缘），`show` 用 frame 选屏、visibleFrame 钳制；补预览冒烟选屏 + 负坐标/右下角几何断言。
- C：`CandidateLabel` 加 `NSTrackingArea` 悬停高亮（复用标签时复位），补 `simulateHover`/`isHovered`/`isHoverRenderable` 断言。
- 验证：`dev-preview.sh --smoke-test` ✅、`build.sh` 宿主编译 ✅、`make verify` ✅（184 产物零网络符号）。距排 B（首次激活引导）与真机实测。

### 2026-10-10 / pi：T-P2-01 简繁转换（功能集补齐）
- 数据：OpenCC `STCharacters`+`STPhrases`（Apache-2.0，固定 commit `8cf737a4`）→ `data/generated/variant-s2t.tsv`（42,430 条 / 841KB，随包）；登记 D11/D12 + 派生项、`数据来源与许可.md` §1.9；`fetch-opencc.sh` / `tools/prepare-variant.py`。
- 配置 `input.chinese_variant` + 快捷键 `hotkey.toggle_variant`（默认 `ctrl+shift+f`，写回）；FFI 边界最长匹配简→繁，引擎/学习仍存简体；菜单状态与帮助面板新增简/繁。
- ADR-069；预览冒烟新增简繁断言；`make verify` 122 passed（含 doctest）。

### 2026-10-10 / pi：快捷键帮助面板（菜单入口）
- 新增 `platforms/macos/Sources/Help.swift` + 菜单「快捷键与使用说明…」：**读取当前配置**展示实际生效按键；`build.sh` 用 `Sources/*.swift` 通配，新文件自动纳入。

### 2026-10-10 / pi：菜单精简 + 简繁 P2 卡
- 菜单移除与快捷键冗余的「临时中英切换」「临时全/半角」（快捷键已生效；模式项已显示状态），加分隔分组：模式 / 词库与反查 / 帮助 / 关于 / 条件错误项。新增 `docs/tasks/T-P2-01.md`。

### 2026-10-10 / pi：对齐主流 Ctrl+. 与 ,/. 翻页（ADR-068）
- 新增 `hotkey.toggle_punctuation`（默认 `ctrl+.`）与 `candidate.page_with_comma`（默认 true，组合态 `,`/`.` 翻页）；中英/全半角已与搜狗/微软/微信/RIME 一致。

### 2026-10-10 / pi：中英「单独 Shift」真机修好（recognizedEvents）
- 根因：IMK 默认只转发 `keyDown`，`flagsChanged` 必须在 `recognizedEvents` 中显式声明；另修返回类型应为 `Int`（写错会编译失败装成旧包）；接管 `leftMouseDown`。用户实机确认 `mask=5122`、单独 Shift 生效。

### 2026-10-10 / pi：快捷键对齐搜狗/微信且可配置（ADR-067）
- 新增 `hotkey.toggle_english`（默认 `shift` = 单独按 Shift）与 `hotkey.toggle_width`（默认 `shift+space`）；空格用**物理键码 49** 判定，修复真实 IMK 事件不生效。

### 2026-10-10 / pi：MVP 收敛（T-MVP-07，ADR-066）
- 词库每次 learn **25.6ms → ~4ms**：写入路径只 `write+rename`（不 fsync），`Store::flush()` 在会话结束/导出时统一 fsync；配置写入仍保留 fsync。用户候选改 BTreeMap 前缀 range。

### 2026-10-10 / pi：MVP 收敛（T-MVP-06）
- 候选窗**鼠标点选** + **状态徽标**（模式 + `全`）；新增 `ime_session_is_full_width()`；菜单标题显示 `混输·中·半角`；预览冒烟新增断言。

### 2026-10-10 / pi：仓库转公开 + Pages + 分支保护（T-MVP-11）
- 公开前扫描无密钥/个人路径；仓库转 **public**；启用 **Pages**（HTTP 200）；main 分支保护（必需 `check`/`macos`/`fuzz`，禁强推/删除）；Actions 免费恢复，CI（含 fuzz）与公证全绿。

### 2026-10-10 / pi：MVP 收敛（T-MVP-08/09/10）
- 固定 `cargo-deny 0.20.2`/`cargo-fuzz 0.13.2`；CI 加有界 fuzz job；新增 `security.yml` 每周 `cargo deny advisories`；`run-perf.sh` 定为回归基线；`005` 标历史、发布清单加「发布流程（汇总）」。
