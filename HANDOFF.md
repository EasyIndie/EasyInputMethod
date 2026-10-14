# HANDOFF — 会话交接文档

> **本文件记录"当前状态"，供任意 AI 工具在任意新会话中快速接手，防止背景信息丢失。**
> **每次会话结束时必须更新本文件**（规则见 `AGENTS.md` §6.1；操作见 Skill `update-handoff`）。
>
> 稳定背景（设计、决策、数据合规）在 `docs/`；**本文件只回答三件事：此刻在哪 / 下一步做什么 / 有什么坑。**
> 历史细节找 `git log` 与各 `docs/tasks/*.md`，**不要在本文件里堆流水账**。

---

**最新公开状态**：IT-25提交f90010b已批准推送，PR #41全门禁通过合入b62b70d；CI #38548270116签名公证/离线重建成功，本机附件与Apple信任核验通过（报告013）。仅该载荷公开，报告012三项核心修复仍本地；未发布/安装，原生产品门禁仍待。

**当前本地阶段**：用户批准基础UI纳入MVP（ADR-165）。功能基线66ab513冻结，分支codex/mvp-ui-refinement。UI01/02/03候选、设置与工具界面工程完成；make verify零诊断/137产物隐私检查，21文件79离线测试及预览构建通过。真实VoiceOver/客户端焦点/最终包双设备验收仍待；没有推送或安装。

## 0. 元信息

| 项 | 值 |
|---|---|
| 最后更新 | 2026-10-14（UI01候选工程完成；UI04外观/访问性工程下一步） |
| 更新者 | Codex |
| 当前阶段 | **首版功能已实现，设备 B 审计发现新增可靠性/可访问性问题，待逐项修复与最终包验收**；历史 MVP 工程收敛已闭环，产品MVP尚未完成；正式 Release、P1-M5 第三方核验和扩展兼容仍待推进 |
| 当前分支 | 独立工作区codex/mvp-ui-refinement，基于66ab513；主目录原有代码/码表保持，不覆盖 |
| 活跃 PR | 见 GitHub；仓库**已公开**，**无正式 Release**（首版 `v0.1.0` 待打 tag） |
| 历史扩展验收 | ✅ 全绿且**输出零诊断**（ADR-081）：122 项测试（含 doctest）、fmt、Clippy、deny、191 产物零网络符号；预览冒烟（含多屏/悬停断言）、宿主构建、离线重建、`make fuzz` 三目标均通过 |

**登录发现/选择阻塞已解除（仅本次设备B对照）：用户截图及TIS复查确认7bb55aa3父源/模式启用。临时根已被重新登录清理；核验公证包/绑定记录后独占恢复空根及所有权标记。用户明确批准自动切换恢复，normal/failure/INT/TERM四路径全部通过，原当前源/完整启用集合及真实配置/词库摘要保持，未发键。旧64663035已精确禁用、注销并归档，其他输入源未变。** 公证包仍保留供实际客户端验收；正式安装包未替换，产品MVP未完成。

ADR-136：授权执行链已定位并解除。TCC日志responsible/subject=com.openai.codex，实际宿主/Applications/ChatGPT.app（显示名ChatGPT）；父链ChatGPT→内嵌CodexCLI→Python→osascript。此前辅助功能有效策略Denied (System Set)，给osascript单独授权未覆盖责任主体。用户允许精确宿主后UI elements enabled=true，前台及AX保护通过。证据build/tcc-chain-2n0505ky/chain.json、attribution.log/json。严格宿主签名核验通过；没有TCC数据库读写/重置或系统代理重启。

ADR-137/138：TextEdit基础实际提交已通过。字符/物理键码在原先“先创建文档再选源”顺序均原码透传；改为先选独有源再创建/首次激活文档，物理W/Q+空格正确提交“你”。固化驱动后再次通过（build/installed-textedit-vn0hx0zp）；原源/完整启用集合及真实数据摘要保持，独有文档关闭。模拟failure、INT、TERM恢复分别通过（z6bq1iy3、4_2jkozt、u8v4mh1s），均在发键前注入；它们只证明创建/切换阶段恢复，不等同组合中断或其他应用通过。13项相关回归、Swift前轮零诊断及本轮make verify全绿/170产物通过。签名包仍基于c294b67，不含全部未提交产品修复；IT-01整体及产品MVP保持进行中。

ADR-139：wq前缀输入后、空格提交前的failure/INT/TERM三场景已固化并原生通过（build/installed-textedit-fak6mom7、pnb0o8l1、rn5vn9py），每条均核验前缀和原源/完整启用集合/真实数据摘要恢复，独有文档关闭。新增中断场景回归后共14项相关测试通过，make verify零诊断/170产物通过。前缀文本校验不等同marked range证明，完整预编辑协议及多应用覆盖仍待验。

ADR-140：本机TextEdit自有AXTextArea公开AXTextInputMarkedRange；已同调用校验窗口/文档/前台/AX身份后读取。wq阶段AppleScript端点1,2，提交“你”后2,1，原生正常通过（build/installed-textedit-0m2r8ohi）；预编辑范围已确认时failure/INT/TERM三路径也通过（rv2fun0q、l9th_ubb、8ab2cx2q），原源/完整启用集合/真实数据恢复、独有文档关闭。范围缺失/不可读不作为空值通过，新负向回归验证不发送提交键。相关回归15项及make verify零诊断/170产物通过。该端点表示不是CFRange的location/length；只验证固定TextEdit场景，不代表所有预编辑协议或最终候选通过。

ADR-141/142：用户授权后Safari调用恢复，离线窗口创建和页面身份检查通过。关闭保留不可见零标签对象，已修正exists误判；四次顺序创建/检查/关闭原生全通过（build/safari-ownership-0uxjlkmp/fixed-result.json），不是failure/INT/TERM中断验收。未发键/选源，Safari实际输入、焦点及中断驱动仍待验；make verify零诊断/170产物通过。初次超时和关闭误判证据原样保留。

ADR-143：Safari初始焦点是智能搜索栏；自有窗口唯一描述AXTextArea定位/首次聚焦及每次read/key页面/前台/角色身份检查已接入专用驱动。正常wq+空格提交“你”通过（installed-safari-ryzelwii），前缀阶段failure/INT/TERM通过（6fkc8ng0、ch4241os、3fc5ln2v），源/启用集合/真实数据恢复且自有窗口关闭。没有Safari marked range证明，不代表完整协议/最终候选。make verify零诊断/170产物通过。

ADR-144：Terminal非执行字节接收器已实现，30秒/64字节边界、私有目录及0600元数据，INT/TERM恢复TTY；macOS恢复canonical会设置瞬态PENDIN，比较仅忽略该位。四项PTY测试（含两个中断信号）及make verify零诊断/170产物通过；尚未创建原生Terminal窗口或发键，下一步绑定窗口/TTY/接收器PID后再验输入。

ADR-145/146：用户授权后Terminal只读调用恢复；精确进程核验发现Homebrew解释器启动器和Framework实际进程路径不同，已按同版本实际路径修正，未放宽命令/TTY匹配。原生窗口/单标签TTY/ready PID/完整ps命令绑定、stop后TTY恢复及非busy精确关闭通过（build/terminal-ownership-ccynlyig/result.json）。5项接收器/身份回归及make verify零诊断/170产物通过。未发键/切源，下一步逐键AX焦点保护及实际输入；不再请求Terminal授权。



ADR-147：Terminal逐键同调用窗口/TTY/前台/AXTextArea/PID完整命令及输入源保护完成。正常wq+空格接收“你”通过（installed-terminal-tp05x0d3），AX前缀确认后failure/驱动INT/TERM通过（p93m28kf、5h66ex17、fyuau280）；源/完整启用集合/真实数据恢复、TTY恢复及自有窗口关闭均通过。前缀尾部屏幕空白判定已修正，失败证据保留；不代表marked range或最终候选。7项Terminal结果/身份/接收器回归及make verify零诊断/170产物通过。

下一步：TextEdit基础预编辑/提交/组合阶段中断已通过，继续补Chrome/VSCode及安全聊天目标应用覆盖，Safari/Terminal范围和更多交互仍待验；把当前产品修复构建为最终候选后再验可靠性/UX和用户五工作日试用。不再把TextEdit基础提交列为未验，不开放旧live。

候选准备：独立工作区`/Users/joker/.codex/worktrees/mvp-product-candidate/EasyInputMethod`已按组件保存本地提交并合入远端main的PR #38，完整源码待最终审核附件核验；主工作区未覆盖，未推送/公证/安装/发布。自动工程证据与剩余人工门禁见[自动验收状态](docs/MVP自动验收状态.md)。最终附件与重建结果在独立日志/报告保存，不通过改写源码包制造提交身份漂移。

最新进度：IT-04…09完成（ADR-093…098）；IT-02完成独立面板隔离及原生交互/清理（ADR-103）；IT-19基础模糊音按音节展开、有界查询与精确候选优先完成（ADR-104）；IT-21反馈操作结果完成（ADR-102）。IT-10/11/16/17/18仍进行中；用户词库写入失败回滚、精确删除、导入路径/行号错误与反查恢复已实现并有隔离原生证据（ADR-106…108）。五笔代表键名提示已实现及登记D13（ADR-109），不等同完整字根拆字图。

最新验证：make verify全绿零诊断、170产物隐私扫描；strict universal及实际构建身份/产品契约检查通过，FFI冒烟通过；隔离预览通过（含四键提示+九长候选窄屏）。IT-03覆盖门禁10项、IT-13附件核验9项与构建身份4项回归通过，已接CI；发布演练和正式发布只读取核验后的4附件。按键内容日志已移除（ADR-110…114）。隔离渲染2200keys：cold15.827ms、warm p95 4.413ms、footprint21.49MiB；不代表真实IMK性能。

本轮新增导入/导出成功反馈（ADR-111）源码/预览通过，原生验证CUA应用绑定约3994秒超时，记BLOCKED；独有测试进程已退出、真实配置/词库未变，临时目录归档后清理。另修复交互驱动stdin注册异常未进入清理保护的问题。当前不重复调用该超时原生路径；恢复窗口工具后补原生反馈/AX/VoiceOver。未换已安装包、未提交/发布。

上轮审计核验：当前执行设备是 **B（macOS 27.0 / 26A428 / arm64）**，源码 HEAD `c294b67`，已安装包 `4d9339c`（thin arm64 / ad-hoc）。`make verify` 全绿零诊断（118 通过、1 忽略，162 产物隐私扫描）；隔离预览冒烟、满容量合成词库压力和 strict arm64 宿主构建通过。universal 本机构建缺 Intel Rust target；原生 AX 窗口检查超时，未重跑多应用实机/VoiceOver/多屏/fuzz。新增问题与证据见 [审计009](docs/reviews/009-macos-product-engineering-audit.md)。

ADR-122：测试构建和实体注册前置身份校验已接入，缺inputmethod段、连接名和模式清单漂移有回归，5项通过并由现有CI执行。设备B新版完整实体注册/清理驱动exit0，枚举2源，原输入源/完整启用集合恢复；无参数隔离服务READY且持有PID清理通过，真实数据摘要不变。证据platforms/macos/build/source-probe-e2e-6aadf5a7/；随后四路径/错误标记拒绝回归通过并删除根目录。未选择输入源、未验证客户端输入，IT-01仍进行中。

当前隔离公证包：`~/Library/Input Methods/LampyrisIMKTest-7bb55aa3-bc3d-431a-98bc-16161a4b5acc.app`，显示名“萤火虫隔离验收 7bb55aa3”，独有根`/private/var/folders/z0/1h35x82j7d767_fm_x3tvdsh0000gn/T/lampyris-imk-7bb55aa3-bc3d-431a-98bc-16161a4b5acc`。公证运行38258905282、合并提交a292534；包基于c294b67，仅作信任/隔离对照，不含主工作区全部MVP改动。附件/选择证据：`platforms/macos/build/ci-isolated-38258905282/Lampyris-isolated-imk-a292534062608bbf2ede323dd54bf041055cbc9a/`，post-login-result.json四路径通过；root-recovery.json记录空根恢复。旧包归档：`platforms/macos/build/retired-isolated-64663035/`，state.json确认其他输入源不变。不要改签名资源或以此包当最终候选。

ADR-131/132：已装源探针保留原启用集合；原先用于注册/清理的驱动不适合直接重跑此已启用包。临时根会在登录时被清理，恢复仅允许已核验独有UUID/私有根绑定的空目录和标记，不回退正式配置。TextEdit基础客户端输入已通过，其他客户端/组合中断待验，旧live入口继续禁用。命名/路径/登录发现与根生命周期经验见平台README。

独立CI工作区`/Users/joker/.codex/worktrees/isolated-ci-notary/EasyInputMethod`保留，PR #38已合入。主工作区未拉取覆盖未提交改动，远端main为a292534；后续同步需保留本地产品改动。

设备A已由ssh pro只读确认Intel/macOS13.7.8、Swift5.8.1、干净c294b67；已安装88833aa。用户担任手动验收和独立核验者；ADR-125改为用户本人一位，计划2026-10-13开始，累计5工作日要求保留。单人清单和IT-23任务卡已准备；覆盖报告schema 2、10项回归通过。尚无最终候选或用户验收结果。

## 1. 三十秒摘要

- **萤火虫 / Lampyris**：跨平台、开源可审计、默认离线、只做核心输入的中文输入法（五笔优先，**默认混输**）。Rust 引擎 + 窄 C ABI + 平台薄宿主；**GPL-3.0-or-later**。
- **现在**：P1-M0…M3 全部完成；**首版功能集已补齐**（五笔/拼音/混输、反查、用户词库与学习、中英/全半角/中英标点/简繁/三模式切换、候选点选与来源标注、配置即时刷新与错误可见；设置与词库面板、版本信息与反馈入口（ADR-080 已移除独立帮助））；**MVP 工程收敛 11/11** 完成；仓库公开、Pages 上线、Release/Pages 工作流就绪。
- **下一步**：按 [迭代计划](docs/迭代计划.md) 执行 I0安全 → I1可靠性 → I2产品体验 → I3日常可用 → I4分发就绪；继续 T-ITER-01与IT-03，保护实机验收数据。IT-02、04…09、19、21已完成；IT-01仍进行中；IT-11/16推进中，后续输入质量与分发门禁仍待完成。
- ⛔ 铁律：核心不联网、`forbid(unsafe_code)`（**仅 `ime-ffi` 例外**）、数据登记许可、配置只走 `ime-config`。

## 2. 已完成（按里程碑；细节见 `docs/tasks/` 与 ADR）

- **UI01**：候选主体精简、非激活有界翻页、长内容滚动、亮暗及错误/AX保留；离线工程证据见[报告017](docs/reviews/017-mvp-ui01-candidate.md)。

| 阶段 | 成果 | 关键文档 |
|---|---|---|
| 调研 / 方案 | 选型、权威方案、交叉审核（有条件通过） | `docs/技术方案.md`、`docs/reviews/001.md` |
| **P1-M0** | workspace + `ime-core`（Engine/InputMode/会话状态机）+ `ime-table` + `ime-cli` | — |
| **P1-M1** 自建码表 | `crates/wubi-encoder`（五笔86 全规则）+ `data/` 流水线；单字表 **27,823 字**（vs D3 99.98% / vs rime 98.77%，**GB2312 一级均 100%**）；内置核心 `wubi86-core.tsv` **491,854 B** | ADR-016…021 |
| **P1-M2** 配置+拼音+混输 | `crates/ime-config`（Schema/`ArcSwap`/原子写/广播）+ `crates/ime-pinyin`（内置兜底）；混输合并 | `docs/配置架构.md`、ADR-008/009 |
| **P1-M3** macOS 宿主 | `crates/ime-ffi`（会话 + 配置 C ABI）+ `platforms/macos/` Swift/IMK 宿主（`build.sh` 产 `Lampyris.app`） | `platforms/macos/README.md`、ADR-022/023/055 |
| **MVP 收敛** | T-MVP-01…11 全部完成（安全/一致性/性能/CI/文档） | `docs/tasks/mvp-hardening.md`、ADR-061…066 |
| **首版功能集** | 中英（单独 Shift）/全半角（Shift+空格）/标点（Ctrl+.）/简繁（Ctrl+Shift+F）/三模式；候选点选 + 来源标注 + 状态徽标；设置 / 词库面板与版本信息 / 反馈入口 | ADR-057/067/068/069/079/080 |
| **发布工程** | 二进制不含源码 + 同页源码包（GPL §6(d)）、Release + Pages 工作流、仓库公开、分支保护 | ADR-064/065、`.github/workflows/` |

## 3. 进行中与待推进

- UI02四pane原生工具栏/Schema/最小窗/主题/无会话禁用已验证；UI03开始。

- **当前主线T-MVP-UI**：UI01工程完成，UI04外观/访问性工程下一步；UI03/04及最终包门禁未完成。

- **设备 B 审计已完成，MAC-01的清理所有权子步已实施，完整数据保护待推进；MAC-02…05、07、19已由IT-04…09修复，其余MAC项待推进**：见 [报告009](docs/reviews/009-macos-product-engineering-audit.md)。近期优先：实机脚本可能影响真实数据、快捷键非法/冲突、全半角配置与临时状态冲突、组合中配置不重算、保存失败被吞、可访问动作、简繁资源错误与对比度验证。
- **已交付**：候选窗多屏几何与悬停/文本居中；简繁（ADR-069）；设置 / 词库两分区、版本信息与显式反馈跳转（以 ADR-079/080 为准）；MEM-1 内存优化（ADR-082）。
- **历史实机**：本机 A 的 MVP-05 已关闭（12/13 + 浏览器地址栏已披露限制）；机器 B 在88833aa完成复现，内存优化后补验14/14（MVP-05 §2.3–2.4）。这些不是 c294b67 最终签名包的完整验收。
- **发布收尾待办**：最终包来源/SHA/版本说明、Release dry_run实际附件校验、P1-M5独立第三方复现与零外联、正式 v0.1.0 Release。
- **MVP-14**：更多 macOS 版本、真实多屏/缩放覆盖与分层图标仍待评估；当前已在设备 B，可本地处理 Xcode27 相关工作，但不把图标升级作为首版门槛。

- **IT-01进行中**：共享TextEdit所有权协议及normal/failure/INT/TERM四条原生路径通过；Safari/Terminal协议、输入源恢复和真实IMK数据隔离仍需补验，禁止直接运行旧真实环境脚本。
- **IT-02已完成**：独立临时配置/词库、唯一进程身份、四路径清理及原生面板交互通过；旧入口参数仍在资源操作前BLOCKED/3退出。详见任务卡。
- **恢复执行入口**：IT-03门禁实现仍待安全驱动/实际包报告接入；IT-18成功反馈已实现但新增原生验证BLOCKED。IT-20提示验收/IT-12基线/IT-13分发卡已建立；下一步安全IMK隔离及原生工具恢复，然后I2/I3/I4最终门禁。

## 4. 下一步（可执行，按优先级）

当前执行路线（取代此前“UI整体后移”）：UI01候选主体/分页工程已完成 → UI02设置与菜单 → UI03已有工具/反馈/关于 → UI04外观与访问性 → UI05重新锁定完整签名包，B后A原生验收及用户独立核验/五工作日试用。详见[任务卡](docs/tasks/T-MVP-UI.md)、[实施规格](docs/design/mvp-ui.md)。完整拆字教学/学习偏好仍后移。

66ab513只作为功能基线及旧审核附件身份，不能当含UI改版的最终MVP。公开授权仍绑定既有明确SHA；本轮仅本地实现/提交，不推送、不安装。A当前不可用，B未获本轮桌面操作安排；离线组件测试不激活用户窗口。

以下为历史任务索引，不构成安装或公开新包的执行授权。

1. **I0 / 恢复后推进**：用户已允许恢复；IT-02已完成，继续IT-03结果分类及IT-01真实IMK数据隔离/协议补验，未经修复不运行旧真实环境脚本。
2. **I1 / IT-04…09已完成**：最终安装包仍需真实客户端回归；本轮未替换历史安装包。
3. **I2产品体验**：IT-10/11、16…22，设置/候选视觉、词库纠错、基础拼音质量、字根提示、反馈与产品走查纳入MVP。
4. **I3日常可用**：IT-12/23性能和持续试用、目标应用/系统/多屏兼容。
5. **I4 / P1-M5**：最终候选、包校验、独立第三方核验和分发材料。
6. **发布 v0.1.0**：统一版本说明与验收环境，补附件摘要/来源核验后 dry_run，再决定打 tag / Release。
7. **MVP后**：稳定维护→输入质量深化→Windows/Linux→移动端；详见 `docs/MVP后里程碑.md`。

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
| **UX-1** | **⑩ 浏览器地址栏预编辑残留**（Chrome 切窗口/点击、Safari 点击；其余应用正常）。根因：客户端失焦时 **IMK 会把预编辑原样取消标记**成普通文本，且该时机在输入法收到任何回调之前（`commitComposition:` 内无论 `setMarkedText("")` / `insertText("")` / `markedRange()` 何种写法都不生效；只有我们主动清（如 Esc）才有效）。**决定（2026-10-11）：接受为已知限制**（与主流输入法同类行为），已写入发布说明 §3；若后续反馈多，再评估「预编辑不入客户端」（需放弃行内预编辑） | 否 |
| **IMK-SEL** | 登录后7bb55aa3父源/模式启用，四路径选择恢复通过；旧64663035已归档 | 选择阻塞已解除，TextEdit基础提交通过，完整客户端覆盖待验 |
| **AUD-009** | 设备 B 审计发现新增可靠性 / 测试数据保护 / 可访问性问题（报告009） | 待逐项修复与验收；未改变历史已接受限制 |
| **MEM-1** | ✅ **已解决（ADR-082 / T-P2-04）**：简繁懒加载 + `ime-table` 紧凑数组 + 面板关闭释放；宿主全新 **43.8→23.3 M**，验收 ⑪ 达标（14/14）。见 [`docs/tasks/T-P2-04-memory.md`](docs/tasks/T-P2-04-memory.md) | 已关闭 |

### 本次候选与执行状态

- 当前设备 B 安装：`~/Library/Input Methods/Lampyris.app`，**4d9339c / thin arm64 / ad-hoc**（审计009读取包内提交和签名确认），早于 #37 文字居中修复；本轮未替换。
- 当前源码：`main c294b67`；审计009生成 strict arm64 开发构建于 `platforms/macos/build/Lampyris.app`，**未安装**。本机已安装 arm64 与 Intel Rust target，strict universal开发构建已通过；未证明Intel实机运行或正式签名。
- 仓库已公开；上一轮远端查询无开放 PR/正式 Release，c294b67 的 CI 与 macOS Acceptance Package 成功。本轮未再查询远端或下载签名候选，不能使用旧候选编号表示最新附件。

## 6. 必须知道的坑与硬约束

- 铁律见 `AGENTS.md` §2：核心零网络、unsafe仅FFI、配置唯一、数据合规、ADR先于行为变更、提交前零诊断验证。
- **真实环境验收脚本尚有数据保护缺陷**，IT-01未完成；两个旧live入口已程序化BLOCKED，无绕过；使用说明见 `platforms/macos/tests/README.md`。
- 安装ZIP用Finder/ditto保留权限；注意同bundle影子副本。首次注册可能需注销/登录；热杀宿主后仅重选输入源不能保证恢复。操作细节见 `platforms/macos/README.md` 与 `docs/人工验收与多机复现.md`。
- B现有双架构Rust target，strict universal开发构建已通过；构建失败不会替换旧包，必须核对退出码与SOURCE-COMMIT。
- 构建/FFI/API约定见平台README与配置架构；派发工具及供应商配置见任务索引/开发工作流，勿把历史机器操作当成本次执行结果。

## 7. 环境快照

| 项 | 值 |
|---|---|
| 本机 A（本地迭代/真机验收） | macOS **13.7.8**、**Intel x86_64**；仅 CLT（Swift 5.8.1、无 Xcode）；`security find-identity` 为 0；已加 `aarch64-apple-darwin` + `x86_64-apple-darwin` target |
| 机器 B（签名/新版系统） | macOS **27.0**（26A428）、**Apple Silicon arm64**；Xcode **27.0**（27A266a）；Developer ID 身份与 CI 公证凭据；当前执行设备；审计009核验已安装 **4d9339c / thin arm64 / ad-hoc**，源码 **c294b67**（旧 `Yinghuo.app` 与 `9e7ef41` 已 `lsregister -u` 并移到 `~/lampyris-pkg/backup/`）；验收步骤与一键脚本放在其 `~/lampyris-pkg/`。原生 CUA 清单可读，但应用 AX 抓取超时；隔离预览冒烟在审计009通过，真实 GUI 验收范围见报告009 |
| Rust | ✅ 1.98.1（`rust-toolchain.toml` 固定）；设备 B 已有 `aarch64-apple-darwin` 与 `x86_64-apple-darwin`；A 的双 target 为历史记录 |
| 宿主工具链 | A：CLT `swiftc`/`codesign`；B：Xcode 27 `swiftc`/`codesign`/`notarytool`/`stapler`；`make` 均可用 |
| 输入法现状 | 设备 B 当前 4d9339c / thin arm64 / ad-hoc；机器 A 安装状态本轮未访问，不能推断与 B 同步。正式分发候选由 CI 签名/公证 |
| 数据 | `data/generated/`：`wubi86-core.tsv` / `pinyin-chars.tsv` / `pinyin-core.tsv` / **`variant-s2t.tsv`**（简繁，841KB，随包）；`pinyin-words.tsv` 8.4MB 不入库，可由 fetch 脚本复现 |
| 代码 | ✅ crates：`ime-core` `ime-table` `ime-pinyin` `ime-config` `ime-ffi` `ime-cli` `wubi-encoder`；审计009 **118 项通过（含 doctest）+ 1 项忽略**；`platforms/macos/` Swift 宿主；`fuzz/` cargo-fuzz |

## 8. 接手清单（新会话开始时）

- [ ] 读 `AGENTS.md`（铁律 / 工作流 / 约定）
- [ ] 读本文件
- [ ] 看 `ROADMAP.md` 当前进度
- [ ] 读与本次任务相关的 `docs/`（宿主看 `platforms/macos/README.md`、`docs/配置架构.md` §9、`docs/技术方案.md` §5.3）
- [ ] 先跑 `make verify` 确认基线
- [ ] 有歧义 → **先问，不要猜**

## 9. 会话日志（倒序，保留最近 10 条；更早见 git 历史）

### 2026-10-14 / Codex：UI03工具界面
- ADR-167：词条显式标签/错误保留、删除默认取消，关于/反查信息窗及系统文件操作统一。
- make verify零诊断/137产物、21文件79离线测试、预览构建通过，亮暗/最小窗/长文本离屏图检查。
- 私有剪贴板与反馈成功/失败测试通过，未打开外链/用户窗口；下一步UI04。

### 2026-10-14 / Codex：UI02设置与菜单
- ADR-166：四pane原生工具栏、当前页标题与暂态恢复；词库无会话禁用，菜单状态类别明确。
- make verify零诊断/137产物、21文件79离线测试及预览构建通过；亮暗/最小窗真实离屏图检查。
- 下一步UI03，最终包原生仍待，未推送/安装。

### 2026-10-14 / Codex：MVP基础UI首项
- ADR-165确定首版基础UI范围，完整拆字教学仍后移；功能基线66ab513。
- UI01候选主体/分页完成；make verify、21文件79离线测试及预览构建通过，原生离屏图已检查。
- 仅本地；下一步UI02设置/菜单，最终包真实验收尚未完成。

### 2026-10-14 / Codex：IT-28离线编辑边界
- 额度恢复后探针确认Home/End/前向Delete保护缺口，ADR-164最小修复；真实分类器先红后绿。
- 144 Rust、18文件76离线测试、strict universal全绿零诊断；私有英文不学习/写配置，报告015原生矩阵。
- 读音修复6f487a4仅本地；新载荷未推送/安装，安全字段/布局及最终包原生待验。

### 2026-10-14 / Codex：常用读音权重收口
- ADR-163构建期次读音保守分数，复用D4/D5/D10；37例首项22→27、首屏36→37，读音不删除。
- 144 Rust、Swift私有学习/混输回归、重复生成与strict universal通过；报告014，未推送/安装。
- 下一步IT-28编辑/安全边界及最终包原生；UI暂缓。

### 2026-10-14 / Codex：IT-25精确授权公开与公证
- 只推f90010b，PR #41四门禁通过且无冲突后合入b62b70d；CI38548270116公证/离线重建成功。
- 本机四附件摘要/双架构/提交及签名/票据/Gatekeeper通过；报告013记录身份。
- 未安装/发布/推送后续本地修复，原生产品验收待推进。

### 2026-10-14 / Codex：核心收口第一批
- ADR-160/161/162：wang歧义保护、首屏两个拼音兜底、xi'an隔音符完成，仅本地提交。
- 141 Rust、17文件75离线测试、Swift私有学习/默认词表及strict universal通过；无诊断/联网/安装。
- 报告012保留证据；读音质量、IT-28及最终包原生仍待，UI/推送暂缓。

### 2026-10-14 / Codex：IT-29混输歧义保护
- 先红回归确认wang抢提交，ADR-160修复并保留纯五笔唯一契约。
- make verify零诊断通过；默认码表FFI无提前提交，Swift显式选王通过；待最终包原生。

### 2026-10-14 / Codex：核心范围与竞品调研
- 官方Apple/Rime/Fcitx对照＋21个隔离默认配置FFI；wang抢提交、短码拼音靠后、xi'an隔音符缺口确认。
- 报告011及IT-29/26/27与28取证卡，仅研究不改产品行为；IT-25本地保存、公开推送/整体UI暂缓。


### 2026-10-14 / Codex：IT-25离线主动学习修复
- 旧隔离例历史1000后四选不前移，ADR-159修复；新增7项Rust回归与Swift私有词库重载通过。
- make verify零诊断、strict universal及Swift/C ABI通过；无联网/新配置/格式变化，主目录代码与已装d429cec不改。
- 待本次载荷公开门禁/签名与原生产品验收；IT-24保持P0，UI重构下一里程碑暂缓。

