# 核心修复公开与公证记录（PR #42）

历史核心交付记录（当时授权范围）：2026-10-14。用户明确批准66ab5132d963ce75c9ed4309f152f79406874c0f核心载荷推送/PR/全门禁后合入并由CI签名公证；未批准UI4e660af公开或任何安装/Release。

- [PR #42](https://github.com/EasyIndie/EasyInputMethod/pull/42)：check、DCO、fuzz、macos全部SUCCESS，MERGEABLE/CLEAN；以match-head绑定66ab513合入。
- main合并提交：7778070e8f127ec6288ecf7d02d7cb12230e7d56；本地fetch与tree校验确认源码树等于66ab513，未夹带UI。
- [自动macOS Acceptance Package工作流38580600884](https://github.com/EasyIndie/EasyInputMethod/actions/runs/38580600884)成功；Apple Accepted、staple及CI离线逐字节重建通过。
- UI本地4e660af的代码改造已完成；相对新main为4提交28文件，合并预检无冲突且树仍等于该UI候选。完整代码/包/图集见报告019，随后已获批准并由PR #43合入50fdac3；最新状态见报告021。

本记录在主目录保存，不修改冻结UI源码/审核包身份。未安装、替换输入源或发布Release；最终完整UI签名包的同包B/A、VoiceOver/辅助显示及用户独立五工作日验收仍待。


## 下载附件与本机信任复查

- 原始附件目录：`/private/tmp/lampyris-core-signed-38580600884/candidate-rEWXOn`，版本/提交/架构/摘要/对应源码全部校验通过。
- ZIP SHA-256：`28152dffec36e3c862a55590195dbd4595ea128d53edfe70bd8392aa7a4970f7`；签名可执行文件：`5a791612b390350fd8184e636ffc8edbcbee327380fc7306734b8c3317db53fc`。
- codesign deep/strict有效、stapler validate通过、Gatekeeper accepted / Notarized Developer ID。证据[信任记录](/private/tmp/lampyris-core-final-trust.json)。
- 包基于main7778070、源码树与66ab513一致，不含UI4e660af。没有安装、替换输入源或发布Release。


2026-10-14授权更新：UI已获批准并通过PR #43合入50fdac3；持续授权及完整UI交付状态见[报告021](021-ui-pr43-publication.md)。
