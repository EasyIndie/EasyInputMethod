# 016：完整核心修复候选审核说明

候选已冻结；本说明在主目录记录，不包含于下列提交载荷，不改变审核包源码身份。

- 完整候选：`66ab5132d963ce75c9ed4309f152f79406874c0f`。
- 公开main基线：`b62b70d6513115388b1c2223dbcbf142ac90fe9f`；新增7个本地提交、39文件。本地合并预检无冲突，合并树与候选相同；远端PR仍须实际门禁及合并检查。
- 拟用公开目的地：`EasyIndie/EasyInputMethod`，分支`codex/mvp-core-refinement`（当前只核验不存在，未创建/推送）。
- 此前明确公开/合入/公证批准仅覆盖f90010b；本批是新增代码/派生数据载荷，未据旧批准公开。

## 本批内容

| 提交 | 内容 |
|---|---|
| a17ecde | 核心完整性调研与范围归并 |
| 658ac30 | 混输wang跨引擎歧义保护 |
| a1e86bf | 首屏两个精确拼音兜底 |
| fa49be8 | xi'an显式隔音符与标准码学习 |
| 4c31fd4 | 上次精确授权的合入/公证记录 |
| 6f487a4 | 多音字构建期保守次读音权重、37例固定质量集、来源摘要与字表可复现门禁 |
| 66ab513 | Home/End/前向Delete组合保护、真实Swift/FFI离线回归及原生矩阵 |

## 本地门禁与附件

144 Rust通过/1个既有计时忽略；18文件76 macOS/打包离线测试通过；Swift/C ABI及strict universal通过，编译零诊断，137产物隐私扫描。离线源码重建的去签名可执行文件及三核心词表逐字节一致；四默认数据均与源码归档一致。不是最终包原生/安全字段验收。

- [应用审核ZIP](/Users/joker/.codex/worktrees/mvp-product-candidate/EasyInputMethod/packaging/out/candidate-uUy6qh/Lampyris-0.1.0-universal.zip)，4,456,111字节。
- [对应源码及离线依赖](/Users/joker/.codex/worktrees/mvp-product-candidate/EasyInputMethod/packaging/out/candidate-uUy6qh/Lampyris-0.1.0-source.tar.gz)。
- [完整SHA/文件/摘要与验证清单](/private/tmp/lampyris-mvp-core-candidate-review.json)。

本包为开发ad-hoc审核构建，signed_release=false，未Developer ID签名/公证，不用于安装或发布。完成新载荷批准后，按精确SHA推送建PR、全部check/DCO/fuzz/macos通过且无冲突再合入，由main CI签名公证；不发布Release、不替换安装包。

后续必须使用包含所有修复的同一最终签名包，先B后A进行真实客户端/焦点/布局/安全输入/恢复，以及用户独立核验和累计五工作日观察。UI整体重构保持下一里程碑。见[质量报告014](014-pinyin-reading-quality.md)及[原生矩阵015](015-editing-boundary-audit.md)。


2026-10-14范围更新：此冻结附件仍准确对应66ab513功能基线，摘要/源码身份不变；用户随后批准基础UI纳入MVP，UI01已本地提交217a861。此旧功能包不能代表新最终MVP，完成UI后另锁完整包；本报告的公开授权范围不自动覆盖新UI提交。


当前完整UI候选HEAD4e660af，旧66ab附件保持其功能基线身份；新UI载荷另行审核，不以本报告授权推送新增UI。
