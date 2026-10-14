# ROADMAP — 萤火虫输入法

> 任务清单。**AI 代理从这里取任务**（见 `AGENTS.md` §6）。
> 完成一项就勾选 `[x]`，并在 PR 中引用对应编号。
> 详细说明见 `docs/技术方案.md` §12。
> macOS首版历史差距与闭环记录见 [报告006](docs/reviews/006-macos-mvp-gap-review.md)，MVP-01…13 已闭环（MVP-05 含已披露限制），MVP-14 扩展兼容待推进；P1-M5 独立第三方验收未关闭。

设备 B 最新产品/UX/工程审计与建议见 [报告009](docs/reviews/009-macos-product-engineering-audit.md)；MAC-01…24 的状态见任务卡；IT-04…09已修复对应可靠性问题，其余待推进，不能由历史 DoD 已关闭推断无新问题。

用户已允许恢复，当前推进IT-03结果分类、IT-13发布门禁与IT-18/20体验收尾。当前执行顺序以 [迭代计划](docs/迭代计划.md) 为准：I0安全验收 → I1输入可靠性 → I2产品体验 → I3日常可用 → I4正式分发。计划已完成，T-ITER-01进行中（清理所有权、状态恢复与焦点保护子步已实现，TextEdit探针原生双路径通过；共享对象协议迁移及完整数据保护待验）；T-ITER-02已完成（独立进程隔离四路径及原生面板交互/清理通过）；IT-04…09已完成，IT-10/11/16/17/18/20推进中，IT-12/13已拆卡并完成隔离/离线子步；IT-19、21已完成；其余任务待推进，历史完成项不重开。

最新进展（ADR-115…140）：独有IMK数据隔离四路径与主题窗口广播通过；正确inputmethod身份的实体注册/服务启动/注销清理通过。私有根绑定与错误声明拒绝通过；登录后父源/模式已启用，四路径选择恢复通过，TextEdit基础实际提交通过；单文档驱动13项相关回归通过，用户已批准发键；重复启用父源触发设置前台已修复、四路径恢复再次通过；前台检查通过，TCC责任宿主定位为/Applications/ChatGPT.app（com.openai.codex），用户允许后UI脚本true、AX保护通过；先选源再建立客户端后wq+空格提交“你”通过，正常及发键前failure/INT/TERM恢复通过；wq预编辑范围/提交后清除及范围已确认时failure/INT/TERM恢复通过，相关回归15项，权限门禁3项通过，源/真实数据恢复，IT-01未完成。覆盖报告升级schema 2，10项回归通过；单人五工作日验收按用户安排计划2026-10-13开始，清单及IT-23卡已准备。设备A SSH连通且工作区干净；用户负责独立核验。独立CI公证提交已验证，用户批准后已推送并创建PR #38（补DCO后f5d1bbf），check/DCO/fuzz/macos全部通过，合并状态CLEAN；用户补充批准后PR已合入a292534，隔离公证运行38258905282成功，本机信任核验通过，登录后选择恢复通过；旧64663035已归档，公证7bb55aa3已通过TextEdit基础提交，保留待完整客户端验收。产品MVP仍未完成。

2026-10-13：Safari离线正文正常输入和前缀后failure/INT/TERM原生通过（ADR-143）；Terminal非执行接收器及四项PTY测试完成（ADR-144），原生窗口/TTY/进程绑定与实际输入待验。IT-01未关闭。

ADR-145/146：Terminal授权后调用恢复，解释器实际路径精确核验修正；原生窗口/TTY/接收器进程绑定及stop/TTY恢复/精确关闭通过，5项回归通过。逐键AX保护及实际输入待验，IT-01保持进行中。

ADR-147：Terminal正常实际提交“你”及wq前缀确认后的failure/INT/TERM恢复通过，源/启用集合/真实数据/TTY保持，自有窗口关闭。TextEdit/Safari/Terminal固定场景已有证据，其他目标应用、完整协议和最终候选门禁仍待验。

图例：`[ ]` 未开始 · `[~]` 进行中 · `[x]` 完成

---

## 前置：方案审核

- [x] **REV-1** 交叉审核 `docs/技术方案.md`（方向、架构、技术可行性）→ 见 `docs/reviews/001.md`
- [x] **REV-2** 审核 `docs/配置架构.md` + `docs/隐私与安全.md`
- [x] **REV-3** 确认 `docs/决策记录.md` 全部冻结项无异议（新增 ADR-013/014）
- [x] **REV-4** 定 `TBD-4`：英文/包名定为 **`Lampyris`**（ADR-056）

> ⚠️ 以上完成前，不进入编码。
> ✅ 审核已**有条件通过**（2026-10-08）；P1-1/P1-2 行动项已确认并写入文档。

---

## P1 — macOS 上"默认可混输"的完整五笔输入法

### P1-M0 引擎骨架（纯逻辑，跨平台）✅

- [x] 创建 Cargo workspace、`rust-toolchain.toml`、`deny.toml`
- [x] `ime-core`：`Engine` trait、`InputMode`、`Candidate`/`ConvertResult`、会话状态机（`forbid(unsafe_code)`）
- [x] `ime-table`：码表加载 + 精确/前缀查询（**排序数组 + 文本 TSV**；cedarwood/mmap 为带触发条件的可选优化，ADR-060）
- [x] `ime-core`：模式切换（`mixed`/`wubi`/`pinyin`）与多引擎合并骨架
- [x] `ime-cli`：REPL，能输入码→候选→选字上屏→切模式
- [x] 单测（11 个）+ `cargo clippy -D warnings` + `cargo deny` 通过
- [x] **验收**：`ime-cli` 里 `wq`→「你」、「kwwl」→「中华人民共和国」，切换模式生效

### P1-M1 自建码表流水线

- [x] `crates/wubi-encoder`：五笔86 编码器（键名字/成字字根/合体字/末笔字型识别码）—— 细卡见 `docs/tasks/T-M1-01..03`（T-M1-01 字根表、T-M1-02 键名字+成字字根、T-M1-03 合体字+识别码 已完成；oracle 对照 99.98%）
- [x] `data/sources.toml` + 拆字数据交叉校验（`wubi-lex` MIT / WindInput MIT）—— 另接入 **oracle #2** `rime/rime-wubi`（LGPL-3，T-M1-04b，仅验证不发布）
- [x] 单字码表生成（T-M1-05：`wubi86-single.tsv` 已生成 + 双 oracle 回归 GB1 100%；**不引入 .imedict**，文本 TSV 为交付格式，ADR-060）
- [x] 词组码自动生成（T-M1-06：`wubi86-phrases.tsv` 已生成；词表来自 `phrase-pinyin-data` MIT）
- [x] **词频/默认权重接入（P1-1 必交付，ADR-013）**：T-M1-06b 用 `fxsjy/jieba`（D10，MIT）真实词频给单字/词组赋权；词组码表改为多候选（ADR-021）
- [x] `docs/数据来源与许可.md` 登记全部数据（D1–D10，均含 SHA-256 与 fetch 脚本，T-M1-08）
- [x] **验收**：编译产物体积达标（≤0.6MB）；与公开码表对照回归通过

### P1-M2 配置 + 拼音 + 混输

- [x] `ime-config`：Schema + `ArcSwap` 快照 + 原子写 + 广播（见 `docs/配置架构.md`）
- [x] `PinyinBackend` trait + **内置轻量拼音兜底**（音节→高频字词表 + 简拼）
- [x] `inputx-pinyin` **spike**：验证 API/质量/体积，决定是否接入（ADR-008）—— 结论 **不接入**（体积否决；见 `docs/reviews/002-inputx-pinyin-spike.md`）
- [x] 混输合并（五笔优先 + 拼音兜底 + 去重排序）
- [x] 拼音反查（字→拼音，返回首选读音）
- [x] **验收**：改 `config.toml` 即时生效；空码自动出拼音候选

### P1-M3 macOS 宿主

- [x] `ime-ffi`：C ABI（会话 + 配置接口）
- [x] 独立 AppKit 调试窗口（T-M3-05，ADR-024）：复用真实引擎、FFI 与候选窗，脱离系统装载流程
- [x] Swift + InputMethodKit 宿主（`IMKInputController`）—— T-M3-02 完成；ADR-023 注册修正 + Developer ID/公证/重启后，TextEdit/Safari 实体键盘验收通过
- [x] 安装/卸载与签名公证脚本 + 可信安装文档（ADR-032；新候选实机流程待完整 DoD）
- [x] CI 加 macOS runner（T-M3-04：Rust 验证、宿主构建、独立预览冒烟；本地及远端检查已通过）
- [x] **验收**：TextEdit/Safari 里能五笔打字（2026-10-08，用户实体键盘确认；混输拼音兜底也通过）

### P1-M4 交互完善

- [x] 候选窗（自绘 `NSPanel`，亮/暗主题；屏幕边界限制已接入）
- [x] 翻页/选择/退格/Esc（核心及两宿主冒烟；2026-10-09用户确认正式候选翻页正常）
- [x] 中英切换、标点（含成对引号）、全半角（ADR-028）
- [x] 用户词库 + 词频学习（ADR-029：有界 TSV、原子持久化、新增/导出/导入，隔离重建会话验证）
- [x] **验收**：达到 `docs/技术方案.md` §12 DoD —— 2026-10-11 本机 A 实机验收 **12/13 通过 + ⑩ 已记录限制**（[MVP-05](docs/tasks/MVP-05.md)）

### P1-M5 发布工程

- [x] macOS 本地候选打包脚本（源码/vendor/许可/SBOM，签名与上传显式分步）
- [x] `scripts/verify-no-network.sh` 接入 CI
- [x] `docs/隐私与安全.md` 配套说明 + CycloneDX SBOM
- [x] 同环境离线载荷可复现说明及 run-repro.sh（源码包实际重建，去签名二进制/词表逐字节一致）
- [ ] **验收**：第三方可复现、可抓包验证零外联

---

## MVP产品完成标准（ADR-084；历史工程完成不等于产品MVP完成）

- [ ] I0/IT-01…03 安全验收（IT-01进行中、IT-02完成、IT-03进行中）
- [x] I1/IT-04…09 可靠性（ADR-093…098；源码与隔离回归通过，最终包客户端验收在I3/I4）
- [ ] I2/IT-10/11、16…22 交互、视觉、基础输入质量与核心功能完善
- [ ] I3/IT-12/23 真实宿主性能与日常试用、目标兼容覆盖
- [ ] I4/IT-13…15 最终签名候选、第三方核验、分发材料

验收以 [MVP产品标准](docs/MVP产品验收标准.md) 为准；MVP后见 [里程碑路线](docs/MVP后里程碑.md)。

## P2 — MVP后输入质量深化

- [ ] 整句/长词（n-gram）
- 基础模糊音/简拼质量纳入MVP IT-19；后续进一步深化按质量证据立项
- [ ] 现有内置拼音后端质量评估后，再决定是否自研 FSA（保持 trait；inputx spike 已否决，未接入）
- [x] `TBD-3` 用户词库采用 TSV v1（ADR-029）
- [x] 简繁转换（OpenCC 数据 + `Ctrl+Shift+F`，ADR-069，T-P2-01）
- [x] 设置界面（Schema 驱动非模态面板，ADR-070，T-P2-02）
- [x] 用户反馈入口（GitHub Issues，用户主动打开浏览器；ADR-071，T-P2-03）
- 字根提示纳入MVP IT-20（§6.2既定能力）
- [x] 引擎常驻内存优化（macOS 27/arm64 宿主 43.8→23.3M；**MEM-1**，`T-P2-04`，ADR-082）

## P3 — Windows

- [ ] Rust TSF **spike（timebox 1–2 周）**：不成就退 C++ 薄壳（P2-3）
- [ ] `windows` crate 实现 TSF COM（`ITfTextInputProcessorEx` 等）
- [ ] 候选窗；安装/卸载；签名
- [ ] **验收**：Win10/11 主流应用可用

## P4 — Linux

- [ ] Fcitx5 addon（C++ 薄壳 + Rust C ABI）
- [ ] 可选 IBus 引擎
- [ ] 打包 deb/rpm/AUR/Flatpak

## P5 — 移动端

- [ ] Android：Kotlin `InputMethodService` + JNI
- [ ] iOS：Swift 键盘扩展 + static lib（**不申请 Full Access**）

## P6 — 本地语音（可选）

- [ ] `sherpa-onnx` 独立模块；模型按需下载 + 哈希校验
- [ ] 录音仅内存，不落盘
- [ ] 模型下载器放 workspace 外（独立工具），避开 `deny.toml` 网络禁令（P2-6）

---

## 待调研（不阻塞 P1）

- [x] `TBD-1` 已定 jieba MIT（ADR-021）
- [ ] `TBD-2` 五笔98 / 新世纪 / 郑码数据源
- [x] `TBD-3` ADR-029：用户词库TSV v1
- [x] `TBD-4` 英文/包名最终形（ADR-056：Lampyris）

- [ ] IT-25：ADR-159五笔主动后项学习工程已通过隔离回归、make verify/strict universal/Swift FFI；待新签名原生验收与用户例子确认。见docs/tasks/T-ITER-25.md。

2026-10-14报告011：21个隔离默认配置FFI样例与Apple/Rime/Fcitx官方对照，新增待决IT-29混输提交歧义、IT-26兜底首屏、IT-27隔音符/读音质量与IT-28编辑/隐私补验；无产品代码修改。IT-25本地提交先保存，整体UI/公开推送继续暂缓。

2026-10-14 IT-29：ADR-160混输跨引擎歧义保护工程完成，wang不再提前提交；核心回归/默认码表FFI通过，最终包原生待验。本地保存，未推送/安装。

2026-10-14 IT-26：ADR-161首屏两个精确拼音兜底工程完成；默认ni/wo/yu目标20/16/74→均第8，五笔首项保留；完整门禁通过，最终包原生待验。

2026-10-14 IT-27第一步：ADR-162隔音符工程完成；默认两模式xi'an→西安及标准码学习通过。IT-29/26本地提交658ac30/a1e86bf；本批最终141 Rust通过、17文件75离线测试、Swift/C ABI与strict universal通过。读音权重、IT-28及最终包原生尚未完成，UI/推送暂缓；见报告012。
