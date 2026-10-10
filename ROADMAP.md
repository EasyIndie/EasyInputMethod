# ROADMAP — 萤火虫输入法

> 任务清单。**AI 代理从这里取任务**（见 `AGENTS.md` §6）。
> 完成一项就勾选 `[x]`，并在 PR 中引用对应编号。
> 详细说明见 `docs/技术方案.md` §12。
> macOS首版差距与执行队列见 [报告006](docs/reviews/006-macos-mvp-gap-review.md)，MVP-01…14未完成；实现复选框不代表完整DoD通过。

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
- [ ] **验收**：达到 `docs/技术方案.md` §12 DoD

### P1-M5 发布工程

- [x] macOS 本地候选打包脚本（源码/vendor/许可/SBOM，签名与上传显式分步）
- [x] `scripts/verify-no-network.sh` 接入 CI
- [x] `docs/隐私与安全.md` 配套说明 + CycloneDX SBOM
- [x] 同环境离线载荷可复现说明及 run-repro.sh（源码包实际重建，去签名二进制/词表逐字节一致）
- [ ] **验收**：第三方可复现、可抓包验证零外联

---

## P2 — 拼音体验 + 自研引擎

- [ ] 整句/长词（n-gram）
- [ ] 模糊音、简拼优化
- [ ] 自研 FSA 拼音引擎替换 `inputx-pinyin`（保持 trait）
- [x] `TBD-3` 用户词库采用 TSV v1（ADR-029）
- [x] 简繁转换（OpenCC 数据 + `Ctrl+Shift+F`，ADR-069，T-P2-01）
- [ ] 设置界面（Schema 已就绪，见报告 008 P2）
- [ ] 字根提示（§6.2 既定能力，见报告 007/008）

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
- [ ] `TBD-4` 英文/包名最终形
