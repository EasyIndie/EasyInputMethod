# 019：MVP基础UI完整候选审核

代码改造已全部完成；此说明与界面图集在主目录保存，不改变冻结载荷/包身份。

- 候选：`4e660afda7bb669f3464bcce39925f0106c299d3`，本地`codex/mvp-ui-refinement`干净。
- 相对已知公开基线b62b70d：11提交59文件；其中本次基础UI4提交（217a861/d0904e6/20e759c/4e660af）。核心功能66ab513基线后crates/data/依赖清单均无改动。
- UI范围：候选、四pane设置/菜单、词库/读音反查、关于/反馈、亮暗及高对比配色策略与可访问性工程；完整拆字学习/学习偏好仍后移。
- make verify零诊断/137产物，144 Rust通过/1既有忽略，22文件80离线测试、strict universal和完整私有预览通过。
- 审核附件身份核验与对应源码离线重建通过；去签名可执行文件SHA-256为`0b39babd5c66fac8463dd2dba60c63c835ea881a9ead757290c75ac17436acc9`，四默认词表与源码归档逐字节相同。

## 审阅产物

- [28张实际AppKit原生离屏界面图](/Users/joker/Documents/EasyInputMethod/docs/design/mvp-ui-review/index.html)。系统高对比请求在B被解析为普通亮暗；高对比配色策略和真实系统状态明确分开，不冒充VoiceOver/活跃客户端通过。
- [工程验收018](/Users/joker/Documents/EasyInputMethod/docs/reviews/018-mvp-ui-engineering.md)。
- [完整SHA、文件与附件摘要清单](/private/tmp/lampyris-mvp-ui-candidate-review.json)。

- [Lampyris-0.1.0-universal.zip](/Users/joker/.codex/worktrees/mvp-product-candidate/EasyInputMethod/packaging/out/candidate-LJmWVy/Lampyris-0.1.0-universal.zip)，4486274字节；SHA-256 `a52ec1511890d89b03ccc25574170b0715dca97086973f18737d7d991d9d6e15`。

- [Lampyris-0.1.0-source.tar.gz](/Users/joker/.codex/worktrees/mvp-product-candidate/EasyInputMethod/packaging/out/candidate-LJmWVy/Lampyris-0.1.0-source.tar.gz)，9159719字节；SHA-256 `3fb88f7f5f96e3f8371b278c75a3554a5a83202904cd44abe59fc6bf4feef986`。

本包仅ad-hoc审核，未Developer ID签名公证，不安装/发布。它记录4e660af时点的原生图及重建证据；最终签名包另按合并提交核验。

## 公开进度

用户已批准UI，并明确持续授权本项目同类推送/PR/全门禁后合入/CI公证，不含安装/Release。PR #43的最终head为c2c3b537c5eb1c2cef4399cef05ebd9f8da782ca，追加的文档与ADR-169离线失败诊断不改变UI运行时代码。check/DCO/fuzz/macos全SUCCESS、CLEAN/无冲突后已合入main50fdac31381f2adfeda02bf1954b414e54953ea2，树与PR head相同。自动公证运行38592570449成功，附件/源码/本机信任核验通过（报告021）。最终包产品门禁保持开放。
