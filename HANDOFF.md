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
| 最后更新 | 2026-10-09（MVP-01/12 数据结构决策闭环，ADR-060） |
| 更新者 | pi |
| 当前阶段 | **macOS 首版收尾：MVP-01/02/03/04/12 已闭环；余 MVP-05…11；本机（macOS 13 Intel）可独立迭代与真机验收，不再依赖签名机** |
| 当前分支 | `main`，与 origin 同步（见 `git log --oneline -5`） |
| 活跃 PR | 见 GitHub；仓库保持 private，无公开 Release |
| 最近一次 `make verify` | ✅ 全绿：104 单测 + 1 doctest、fmt、Clippy、deny、156 产物零网络符号；`dev-preview --smoke-test`（含来源/配置刷新/错误断言）、universal 构建、离线重建均通过 |


## 1. 三十秒摘要

- **萤火虫**：跨平台、开源可审计、默认离线、只做核心输入的中文输入法（五笔优先，**默认混输**）。Rust 引擎 + 窄 C ABI + 平台薄宿主；**GPL-3.0-or-later**。
- **现在**：P1-M0（引擎骨架）、P1-M1（自建码表）、P1-M2（配置 + 拼音 + 混输）**全部完成**；P1-M3 已完成 `ime-ffi`（C ABI）与 **Swift/InputMethodKit 宿主**（编译/打包/FFI 冒烟通过）。
- **下一步**：MVP-01/02/03/04/12 已闭环（ADR-057…060）；接着做 T-M1-10（`convert` 去全表扫描）与 MVP-06…10（鲁棒性/验证链路）。详见 `docs/reviews/006-macos-mvp-gap-review.md`。
- ⛔ 铁律：核心不联网、`forbid(unsafe_code)`（**仅 `ime-ffi` 例外**）、数据登记许可、配置只走 `ime-config`。

## 2. 已完成（按里程碑；细节见 `docs/tasks/` 与 ADR）

| 阶段 | 成果 | 关键文档 |
|---|---|---|
| 调研 / 方案 | 选型、权威方案、交叉审核（有条件通过） | `docs/技术方案.md`、`docs/reviews/001.md` |
| **P1-M0** | workspace + `ime-core`（Engine/InputMode/会话状态机）+ `ime-table` + `ime-cli` | — |
| **P1-M1** 自建码表 | `crates/wubi-encoder`（五笔86 全规则）+ `data/` 流水线；单字表 **27,823 字**（vs D3 99.98% / vs rime 98.77%，**GB2312 一级均 100%**）；词组多候选表；内置核心 `wubi86-core.tsv` **491,854 B ≤ 0.6MB** | ADR-016…021 |
| **P1-M2** 配置+拼音+混输 | `crates/ime-config`（Schema/`ArcSwap` 快照/原子写/广播）+ `crates/ime-pinyin`（`PinyinBackend` + 内置兜底）；混输（`ime-core` 已实现合并）。实测 `nihao→你好`、`wq→你` | `docs/配置架构.md`、ADR-008/009 |
| **P1-M3**（进行中） | `crates/ime-ffi`（会话 + 配置 C ABI）+ **`platforms/macos/` Swift 宿主**（纯代码 AppKit，可编译/打包，`build.sh` 产 `Lampyris.app`） | `platforms/macos/README.md`、ADR-022、`docs/技术方案.md` §5.3、`docs/配置架构.md` §9 |

> 实验数据：`docs/experiments/`（派发策略：独立任务用「每卡新 worker」，整批实测省 token）。

## 3. 进行中

- **✅ MVP-04 完成（ADR-059，2026-10-09，pi）**：`ConfigStore` 记录首启/重载失败原因（含行号），`reload` 错误状态变化广播哨兵键 `*error`；FFI 增 `ime_config_last_error`；宿主菜单常驻「配置错误」条目 + 同一错误只弹一次 NSAlert，修复后复位。坏文件沿用上一份有效快照，绝不改写用户文件。
- **✅ MVP-03 完成（ADR-058，2026-10-09，pi）**：新增全进程单例 `ConfigWatcher`（仅 `ime_config_subscribe` 一次；回调可能在文件监视线程，统一 `DispatchQueue.main.async` 派发）；`candidate.count`/`mode` 外部变更无需按键即刷新会话与候选窗；`deactivateServer` 按身份解绑，避免重复订阅/泄漏。另修正 ADR-056 遗漏：应用支持目录改为 ASCII `…/Lampyris/`。
- **✅ MVP-02 完成（ADR-057，2026-10-09，pi）**：候选来源由 `ime-ffi`（已带 `source`）贯穿到 Swift `ImeCandidate` 与候选窗；当前页出现多种来源时，在候选后标注小号次要色「五笔／拼／词」，单一来源页不标注。去重/排序/学习归属仍由 `ime-core` 依 `source` 处理，未改；预览冒烟新增来源断言，另修 `run-render-perf.sh` 的 WMO 静态链接坑。
- **✅ SIG-1 澄清 + 本机验收通过（2026-10-09，pi）**：macOS 13.7.8（Intel、无签名身份）上，ad-hoc + 正确 bundle ID 的构建被系统枚举（`enabled/selectCapable=true`，共 284 源），**用户已实体输入验收通过**（ADR-055）。之前“必须公证”的结论混入了 ADR-023 的 bundle ID bug；**macOS 13 本地迭代无需签名机**，分发/macOS 26+ 仍按 ADR-032。
- **✅ CI 现在出 universal 候选**（arm64 + x86_64）：`build.sh --universal`、`prepare.sh`、`run-repro.sh` 与两个 workflow 已接入；本机离线重建逐字节一致。顺手修了 Swift 5.8 的 WMO 静态链接坑（ADR-055）。
- **✅ MVP-01/12 完成（ADR-060，2026-10-09，pi）**：数据结构决策成文——文本 TSV 真值 + 排序数组为当前实现，cedarwood/二进制/mmap 降级为带触发条件的可选优化；同步 `技术方案.md`/`ROADMAP.md`/`T-M1-09` 等。实现债（`convert` 去全表扫描）另立 T-M1-10。
- 首版尚未整体验收：剩余 MVP-05…11 见报告 006（实机 DoD、解析器 fuzz、组合长度/资源边界、词库锁恢复、正式数据加载诊断、CI 审计、发布材料）。
- 用户已安排词库/重启/长时间多应用等实机验收稍后进行；本机用户域 ad-hoc 安装验收后可移除，日常开发仍用独立窗口（ADR-024）。

## 4. 下一步（可执行，按优先级）

**本地迭代（不依赖签名机）**：日常 `make macos-preview`；阶段真机 `./platforms/macos/build.sh --strict --universal` → 拷到 `~/Library/Input Methods/` 并删 `build/` 副本（避影子）→ 选中「萤火虫」实打。macOS 13 上 ad-hoc 即可（ADR-055）。

1. **T-M1-10**：`CodeTableEngine::convert` 去全表线性扫描（改二分 + 前缀区间，`z` 通配独立分支）；先加回归测试再改。见 `docs/tasks/T-M1-10.md`。
2. **MVP-06…10**：解析器 fuzz、组合长度/资源边界、词库锁恢复、正式数据加载诊断、CI 审计完整性；先复现，避免操作真实词库。
3. **MVP-11/05**：发布材料与长期保管；实机DoD由用户安排稍后。C级兼容/空闲优化不扩首版范围。

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

- 当前 CI 公证候选：`Lampyris-macos-acceptance-<sha>`（universal，约 11.5 MB）；签名/staple/Gatekeeper 与离线复现通过。
- 本机（macOS 13 Intel）为**用户域 ad-hoc 临时安装**（`cn.jokerhub.inputmethod.Lampyris`），用户已实体输入验收；验收结束可移除。
- 仓库保持 private，无公开 Release；CI 签名/公证凭据配置见 `packaging/macos/CI-ACCEPTANCE.md`（不在本文件记录凭据细节）。

## 6. 必须知道的坑与硬约束

**铁律（见 `AGENTS.md` §2）**：核心不联网；`forbid(unsafe_code)`（仅 `ime-ffi`）；配置只走 `ime-config`（禁 `UserDefaults`/注册表/第二文件）；任何数据先登记许可。

**实操坑（本轮踩过，务必记住）**：

- ⚠️ 发行ZIP必须用Finder/ditto保留执行权限；Python zipfile.extractall把程序变0644，签名仍通过但无法启动。安装器现拒绝损坏权限。

- ⚠️ **模型名要带 provider**：`deepseek-v4-pro` 在 8 个 provider 下**歧义** → 必须 `--provider cc-switch-deep-seek`；`deepseek-v4-flash` 不歧义。
- ⚠️ **> ~5 MB 的生成文件会让 `git push` 报 HTTP 400**：大表（`wubi86-phrases.tsv` 5.6MB、`pinyin-words.tsv` 8.4MB）**一律 gitignore**，由 `data/sources/fetch-*.sh` + `cargo run --example …` 复现。
- ⚠️ **macOS 输入法必须是 `.app`**（不是 `.inputmethod`），本机首次注册/注册元数据修正后需**注销/重启**完成登录扫描；普通代码热替换尚未验收；`killall TextInputMenuAgent` / 删 `IntlDataCache` / `lsregister -f` / `TISRegisterInputSource`（返回 `noErr`）都**不能**免重启触发重扫。日常功能迭代使用独立窗口（ADR-024），无需该流程。诊断：`platforms/macos/tools/`。
- ✅ **注册标识**：bundle ID 必须采用带 `.inputmethod.` 的形式；当前为 `cn.jokerhub.inputmethod.Lampyris`，连接名为 `${bundleID}_Connection`（ADR-023/056）。组合修正及重启后实机通过；不要再据早期失败推断必须 appex。
- ⚙️ **Swift/Swift 链接坑**：`-whole-module-optimization` 下不能把 `.a` 作位置参数（Swift 5.8 当源码）也不能用 `-L … -lime_ffi`（会链到 cdylib 并把绝对构建路径写进 `LC_LOAD_DYLIB`）；必须 `-Xlinker <lib.a>`。见 ADR-055。
- ⚙️ **universal 构建**：需 `rustup target add aarch64-apple-darwin x86_64-apple-darwin`，再 `./platforms/macos/build.sh --strict --universal`（注意 Rust 用 `aarch64`、Apple 用 `arm64`）。
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
| 本机 A（本地迭代/真机验收） | macOS **13.7.8**、**Intel x86_64**；仅 CLT（Swift 5.8.1、无 Xcode）；`security find-identity` 为 0；已加 `aarch64-apple-darwin` + `x86_64-apple-darwin` target |
| 机器 B（签名/新版系统） | macOS **27.0**（26A428）、**Apple Silicon arm64**；Xcode **27.0**（27A266a）；Developer ID 身份与 CI 公证凭据 |
| Rust | ✅ 1.98.1（`rust-toolchain.toml` 固定）；target `x86_64-apple-darwin` + `aarch64-apple-darwin` |
| 宿主工具链 | A：CLT `swiftc`/`codesign`；B：Xcode 27 `swiftc`/`codesign`/`notarytool`/`stapler`；`make` 均可用 |
| 输入法现状 | 本机 A 用户域 ad-hoc 安装（`cn.jokerhub.inputmethod.Lampyris`），用户已实体输入验收；分发/公证候选由 CI 出 universal |
| 数据 | `data/generated/` 已生成 `wubi86-core.tsv` / `pinyin-chars.tsv` / `pinyin-core.tsv`（词表 8.4MB 不入库，可由 fetch 脚本复现） |
| 代码 | ✅ crates：`ime-core` `ime-table` `ime-pinyin` `ime-config` `ime-ffi` `ime-cli` `wubi-encoder`；**100 单测 + 1 doctest**；`platforms/macos/` Swift 宿主 |

## 8. 接手清单（新会话开始时）

- [ ] 读 `AGENTS.md`（铁律 / 工作流 / 约定）
- [ ] 读本文件
- [ ] 看 `ROADMAP.md` 当前进度
- [ ] 读与本次任务相关的 `docs/`（P1-M3 看 `docs/技术方案.md` §5/§5.3、`docs/配置架构.md` §9）
- [ ] 先跑 `make verify` 确认基线
- [ ] 有歧义 → **先问，不要猜**

## 9. 会话日志（倒序，保留最近 10 条；更早见 git 历史）

### 2026-10-09 / pi：MVP-01/12 词典数据结构决策（ADR-060）
- 事实核对：仓库无 cedarwood 依赖，`ime-table` 一直排序 `Vec`，`ime-dict` 仅有界 TSV；文档却写 cedarwood/`.imedict`/mmap。
- ADR-060：文本 TSV 为可审计真值 + 排序数组内存索引为当前实现；cedarwood/二进制/mmap 降级为**带触发条件的可选优化**；给出迁移触发条件与“可复现编译 + SHA + 校验器”前提。
- 同步 `技术方案.md` §4/§6.2/§7/§11、`ROADMAP.md`、`T-M1-09`（追认完成）、`参考与致谢`/`数据来源与许可`/`backlog`；实现债另立 T-M1-10。

### 2026-10-09 / pi：MVP-04 配置错误反馈（ADR-059）
- `ime-config` 新增 `ConfigStore::last_error`/`load_or_defaults`（首启坏文件降级且记录含行号错误）；`reload` 在错误状态变化时广播哨兵键 `*error`。
- `ime-ffi` 暴露 `ime_config_last_error()`；宿主菜单常驻「配置错误」条目 + 同一错误只弹一次 NSAlert，修复后自动复位；坏文件全程沿用上一份有效快照，不改写用户文件。
- 测试：ime-config/FFI 单测覆盖首启与运行中坏文件、快照保留、错误键广播；预览冒烟覆盖「坏配置→可见错误→修复清除」。

### 2026-10-09 / pi：MVP-03 配置无按键即时刷新（ADR-058）
- 新增全进程单例 `ConfigWatcher`：`ime_config_subscribe` 只订阅一次，回调可能在 `ime-config` 文件监视线程，统一转主线程；`activateServer` 注册、`deactivateServer` 按身份解绑。
- `candidate.count`/`mode` 外部变更即时应用到会话与候选窗（无需按键）；按键路径读取保留为幂等兜底。预览冒烟新增「外部改配置→无按键即时刷新」断言。
- 修正 ADR-056 遗漏：`Config.swift` 应用支持目录仍写死中文 `萤火虫`，已改为 ASCII `…/Lampyris/`；本机已迁移（旧目录备份为 `萤火虫.bak.*`）并重装。

### 2026-10-09 / pi：MVP-02 候选来源显示（ADR-057）
- FFI 本已暴露 `ImeCandidate.source`，Swift 端此前丢弃；现贯穿到候选窗：`ImeCandidate` 增 `source`，混合来源页在候选文本后追加 11pt 次要色「五笔／拼／词」，单一来源页不标注。
- 未改引擎：去重/排序/学习归属仍由 `ime-core` 依 `source` 处理；新增 ime-ffi 来源映射回归测试与预览冒烟来源断言。
- 顺手修复 `run-render-perf.sh` 的 WMO 静态链接坑（`-Xlinker <lib.a>`）；该探针在本机（Intel/OLP）噪声较大，控制性基准仍用 `run-perf.sh`。

### 2026-10-09 / pi：英文/包名定为 Lampyris（关闭 TBD-4）
- ADR-056：英文/包名 `Lampyris`（读 /læmˈpɪərɪs/，希腊语“发光的虫”，萤科一属），bundle `cn.jokerhub.inputmethod.Lampyris`（自有域名 jokerhub.cn 反向 DNS）。
- 全量改名：可执行/App、控制器类、连接/模式 ID、bundle 资源、安装/卸载校验、发布物/CI/SBOM 名、应用支持目录 `…/Lampyris/`；历史记录（experiments/archive/reviews）与 `assets/icons/yinghuo-*` 设计稿名保留。
- 本机已换装并重新枚举通过（`cn.jokerhub.inputmethod.Lampyris.default`）；旧配置目录已迁移至 `…/Lampyris/`。

### 2026-10-09 / pi：macOS 13 本机 ad-hoc 验收通过 + universal 候选
- 关键发现：之前“非 Apple 签名不被枚举”的结论混入了 ADR-023 的 bundle ID bug；修正后 macOS 13（Intel、无签名身份）上 ad-hoc 构建被系统枚举且用户实体输入通过（ADR-055）。
- 依此把本地开发/真机验收从签名机解绑；日常用 ADR-024 独立窗口，阶段用用户域 ad-hoc 安装。
- 新增 `build.sh --universal`（arm64+x86_64）、`prepare.sh`/`run-repro.sh`/两个 workflow 的 universal 支持；本机离线重建逐字节一致。
- 修坑：WMO 下必须 `-Xlinker <lib.a>` 静态链接（`-L/-l` 会链 cdylib 并把绝对路径写进二进制）。

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
