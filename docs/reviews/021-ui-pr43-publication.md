# 021：基础UI合入与最终包交付

2026-10-14。用户批准4e660af基础UI公开，并持续授权本项目同类已验证改动推送/PR/全门禁后合入main/CI签名公证；不包括安装或Release。

- [PR #43](https://github.com/EasyIndie/EasyInputMethod/pull/43)最终head：`c2c3b537c5eb1c2cef4399cef05ebd9f8da782ca`。check/DCO/fuzz/macos全SUCCESS且CLEAN/无冲突；match-head合入。
- main：`50fdac31381f2adfeda02bf1954b414e54953ea2`，fetch核验源码树等于PR head。
- UI运行时代码基线4e660af；256838a仅更新授权/进度文档，c2c3b53增加ADR-169及离线失败诊断回归，不改运行时。
- 本地make verify零诊断/137产物、144 Rust通过/1既有忽略、23文件82离线测试通过；原strict universal/完整私有预览与28张原生图证据见[019](019-mvp-ui-candidate.md)。
- [签名公证流水线38592570449](https://github.com/EasyIndie/EasyInputMethod/actions/runs/38592570449)全流程SUCCESS：Apple Accepted、staple、Gatekeeper及离线源码重建通过；本机静态信任复查也通过。

## 门禁异常记录

运行38588836060的macos步骤在既有test-terminal-input-sink.py失败，其他离线回归包括新UI测试均通过。当时CI仅展示文件名，失败详情留在执行器私有目录且没有失败附件，因此根因未确认。ADR-169输出有界失败诊断，保留完整私有日志、原断言和非零退出；两项回归验证错误可见及长日志截断。新运行38591509648全部通过，不据此将上次失败归因于权限、时间或UI，也不修改接收器行为。

## 最终产品门禁

尚未安装/替换输入源或发布Release。最终同包B/A、真实客户端焦点/安全字段/布局/性能、键盘/VoiceOver/系统辅助显示和单人五工作日独立核验仍待。旧d429cec的实机证据、4e660af的审核包及离屏图均不能替代50fdac3签名包的实际产品验收。

## 最终附件核验

- 附件目录：`/private/tmp/lampyris-ui-signed-38592570449/candidate-7CfWGz`；四附件摘要、0.1.0版本、arm64/x86_64架构及应用/源码提交均通过核验。
- ZIP SHA-256：`54143060ac926934aa2f1e1595d48c33d2bcef07d94e4fa8bb6510314418c27b`；已签名可执行文件SHA-256：`31badc4b53f5004d58b5c8e7674d1b5e34a5ac99b6d3846d2b3fa9078103902a`。
- codesign deep/strict、stapler validate均exit 0，Gatekeeper accepted / Notarized Developer ID。
- CI源码重建的去签名可执行文件与默认数据逐字节一致；本机没有执行/安装包，也未发布Release。
- [信任核验记录](/private/tmp/lampyris-ui-final-trust.json)，CI原始日志`/private/tmp/lampyris-ui-ci-38592570449.log`。
