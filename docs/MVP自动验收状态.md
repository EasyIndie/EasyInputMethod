# MVP 自动工程验收状态

更新：2026-10-13。这里区分工程证据、发布操作和人工产品验收；不将旧隔离包报告提升为最终候选报告。

| 自动工程项 | 当前结果 | 证据 |
|---|---|---|
| 源码归并 | 独立codex/mvp-product-candidate分支，按文档、CI、配置、引擎、词库、FFI、宿主、隔离工具、发布门禁保存；已同步main的PR #38 | 分支git历史，主工作区未覆盖 |
| Rust/许可/隐私 | make verify零诊断；无核心网络依赖或网络符号 | /private/tmp/lampyris-verify-merged-candidate-20261013.log |
| 离线平台/发布回归 | 17文件、75测试通过；普通macOS CI和候选CI共用make macos-offline-tests | /private/tmp/lampyris-offline-merged-candidate-20261013.log |
| 双架构宿主 | strict universal成功，真实SDK/Xcode与产品契约检查通过 | /private/tmp/lampyris-build-candidate-20261013.log；后续审核包重建日志 |
| 独立预览 | 亮暗/最小窗口/长错误/候选/词库/辅助动作冒烟通过，截图已检查 | /private/tmp/lampyris-preview-auto-20261013.log |
| FFI | wq→你、nihao→你好通过 | /private/tmp/lampyris-ffi-auto-20261013.log |
| 满词库渲染压力 | 2200keys；cold7.334ms、warm p95 6.089ms、max10.207ms、无一次≥16ms；footprint26.52MiB | /private/tmp/lampyris-perf-auto-20261013.log |
| 解析器fuzz | 三目标各30秒，无发现崩溃；临时固定cargo-fuzz0.13.2，不改系统工具 | /private/tmp/lampyris-fuzz-auto-20261013.log |
| 数据生成/文档 | 五笔提示逐字生成一致，主要文档本地链接有效 | ADR-109/148/149及本轮核验 |
| 审核包/源码包 | 原始包已完成离线逐字节重建；实体ZIP元数据及源码链接问题修复后需按最终提交生成并验证，结果独立保存 | packaging/out/candidate-*；/private/tmp/lampyris-repro-auto-20261013.log |

## 仍需外部操作或人工验收

- 当前本地审核包为ad-hoc，不能对外发布或替换正式安装包。公开推送/PR及最终CI签名公证尚未执行；先核验本地附件，公开代码载荷须另行确认，不能沿用仅针对PR #38的授权。
- 需要同一最终签名包的目标应用、真实IMK性能/功耗、VoiceOver、系统辅助外观、多屏/缩放/Spaces/睡眠唤醒验收；预览与固定旧隔离包场景不能代替这些结果。
- 设备A Intel/macOS13、设备B新版macOS的最终包验收，用户独立核验及一人累计五工作日试用保持待验。
- IT-01/03/10…18/20/22/23与产品MVP不因自动工程门禁通过而整体关闭；正式Release须全部发布门禁通过。

实体打包经验见ADR-149：ZIP不包含._资源叉/扩展属性副本，摘要覆盖不放宽；源码内链接仅允许安全相对目标。--review只能验未签名包，不能与--assets-only一起用于正式发布输出。
