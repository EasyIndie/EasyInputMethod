# ROADMAP — 萤火虫输入法

> 任务清单。**AI 代理从这里取任务**（见 `AGENTS.md` §6）。
> 完成一项就勾选 `[x]`，并在 PR 中引用对应编号。
> 详细说明见 `docs/技术方案.md` §12。

图例：`[ ]` 未开始 · `[~]` 进行中 · `[x]` 完成

---

## 前置：方案审核

- [x] **REV-1** 交叉审核 `docs/技术方案.md`（方向、架构、技术可行性）→ 见 `docs/reviews/001.md`
- [x] **REV-2** 审核 `docs/配置架构.md` + `docs/隐私与安全.md`
- [x] **REV-3** 确认 `docs/决策记录.md` 全部冻结项无异议（新增 ADR-013/014）
- [ ] **REV-4** 定 `TBD-4`：英文/包名（`yinghuo` vs `lampyris`）

> ⚠️ 以上完成前，不进入编码。
> ✅ 审核已**有条件通过**（2026-10-08）；P1-1/P1-2 行动项已确认并写入文档。

---

## P1 — macOS 上"默认可混输"的完整五笔输入法

### P1-M0 引擎骨架（纯逻辑，跨平台）✅

- [x] 创建 Cargo workspace、`rust-toolchain.toml`、`deny.toml`
- [x] `ime-core`：`Engine` trait、`InputMode`、`Candidate`/`ConvertResult`、会话状态机（`forbid(unsafe_code)`）
- [x] `ime-table`：码表加载 + 精确/前缀查询（M0 排序数组验证；M1 换 `cedarwood`，ADR-015）
- [x] `ime-core`：模式切换（`mixed`/`wubi`/`pinyin`）与多引擎合并骨架
- [x] `ime-cli`：REPL，能输入码→候选→选字上屏→切模式
- [x] 单测（11 个）+ `cargo clippy -D warnings` + `cargo deny` 通过
- [x] **验收**：`ime-cli` 里 `wq`→「你」、「kwwl」→「中华人民共和国」，切换模式生效

### P1-M1 自建码表流水线

- [x] `crates/wubi-encoder`：五笔86 编码器（键名字/成字字根/合体字/末笔字型识别码）—— 细卡见 `docs/tasks/T-M1-01..03`（T-M1-01 字根表、T-M1-02 键名字+成字字根、T-M1-03 合体字+识别码 已完成；oracle 对照 99.98%）
- [x] `data/sources.toml` + 拆字数据交叉校验（`wubi-lex` MIT / WindInput MIT）—— 另接入 **oracle #2** `rime/rime-wubi`（LGPL-3，T-M1-04b，仅验证不发布）
- [x] 单字码表生成（T-M1-05：`wubi86-single.tsv` 已生成 + 双 oracle 回归 GB1 100%；`.imedict` 编译留待 T-M1-09 接入）
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
- [x] Swift + InputMethodKit 宿主（`IMKInputController`）—— T-M3-02（编译/打包/FFI 冒烟通过；**装载与打字待人工验证**）
- [ ] 安装脚本 + 手动安装/Gatekeeper 放行文档
- [ ] CI 加 macOS runner（覆盖 Swift 前端，P2-5）
- [ ] **验收**：TextEdit/Safari 里能五笔打字

### P1-M4 交互完善

- [ ] 候选窗（自绘 `NSPanel`，亮/暗主题）
- [ ] 翻页/选择/退格/Esc
- [ ] 中英切换、标点（含成对匹配）、全半角
- [ ] 用户词库 + 词频学习（本地持久化，可导出/导入）
- [ ] **验收**：达到 `docs/技术方案.md` §12 DoD

### P1-M5 发布工程

- [ ] 打包脚本（`.pkg` 或安装脚本）
- [ ] `scripts/verify-no-network.sh` 接入 CI
- [ ] `docs/隐私与安全.md` 配套说明 + SBOM
- [ ] 可复现构建说明
- [ ] **验收**：第三方可复现、可抓包验证零外联

---

## P2 — 拼音体验 + 自研引擎

- [ ] 整句/长词（n-gram）
- [ ] 模糊音、简拼优化
- [ ] 自研 FSA 拼音引擎替换 `inputx-pinyin`（保持 trait）
- [ ] `TBD-3` 定用户词库存储格式

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

- [ ] `TBD-1` 词频数据源（许可明确）
- [ ] `TBD-2` 五笔98 / 新世纪 / 郑码数据源
- [ ] `TBD-3` 用户词库存储格式
- [ ] `TBD-4` 英文/包名最终形
