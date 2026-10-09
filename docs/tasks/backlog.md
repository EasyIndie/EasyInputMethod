# 任务卡 backlog（粗粒度，到点时再拆）

> 以下为历史阶段拆分草案，不能作为当前未完任务清单。
> 当前执行队列见 [首版对照报告006](../reviews/006-macos-mvp-gap-review.md) 的MVP-01…14；P1-M2/M3多数已交付，P1-M4/M5仍需补齐缺口及验收。
> 这些是 P1-M2 之后的阶段。**执行前先按"flash/pro"原则拆成细卡**（见本目录 README）。
> 依赖关系见 `ROADMAP.md`。

## P1-M2 — 配置 + 拼音兜底 + 混输

- **配置子系统**（`ime-config`）：Schema + `ArcSwap` 快照 + 原子写 + 广播 + 唯一写者。见 `docs/配置架构.md`。（建议 pro：并发/跨进程是难点；Schema 骨架可 flash）
- **`PinyinBackend` trait + 内置轻量拼音兜底**（音节→高频字词表 + 简拼 + 反查）。数据几百 KB。
- **混输合并**（五笔优先 + 拼音兜底 + 去重排序，source 标记）。
- **`inputx-pinyin` spike**：验证 API/质量/体积，决定是否接入（ADR-008）。

## P1-M3 — macOS 宿主

- `ime-ffi` C ABI（会话 + 配置接口，唯一 unsafe 集中地）。
- Swift + InputMethodKit 宿主（`IMKInputController`）。
- 安装脚本 + 手动安装/Gatekeeper 说明。
- CI 加 macOS runner。

## P1-M4 — 交互完善

- 候选窗（自绘 NSPanel、亮暗主题）。
- 翻页/选择/退格/Esc；中英切换、标点、全半角。
- 用户词库 + 词频学习（本地持久化、可导出/导入）。
- 拼音反查完善。

## P1-M5 — 发布工程

- 打包脚本、`verify-no-network.sh` 接入 CI、SBOM、可复现构建说明。

## P2 — 拼音体验 + 自研引擎

- 整句/长词（n-gram）、模糊音、简拼优化。
- 自研 FSA 拼音引擎替换（保持 trait）。

## P3 / P4 / P5 / P6

- P3 Windows：Rust TSF spike（timebox 1–2 周，不成就退 C++ 薄壳）。
- P4 Linux：Fcitx5 addon。
- P5 Android / iOS（Android=Kotlin+JNI；iOS=Swift+staticlib，不申请 Full Access）。
- P6 本地语音（`sherpa-onnx`，模型下载器放 workspace 外，避开 deny 网络禁令）。

## 待调研（不阻塞）

- TBD-2 五笔98/新世纪/郑码数据源
- TBD-3 已由ADR-029关闭：有界TSV v1
- TBD-4 英文/包名（yinghuo / lampyris）
