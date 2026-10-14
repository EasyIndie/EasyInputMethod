# 013：IT-25公开门禁与CI公证完成

2026-10-14，用户明确批准十文件提交f90010bbd9f69f2ab097dad2236cced18760ec00推送、PR、全门禁且无冲突后合入并公证。只推该SHA；后续a17ecde/658ac30/a1e86bf/fa49be8未推送，不包含在本包。

- [PR #41](https://github.com/EasyIndie/EasyInputMethod/pull/41)：check、DCO、fuzz、macos均SUCCESS，MERGEABLE后以匹配head SHA保护合入。
- main合并提交：`b62b70d6513115388b1c2223dbcbf142ac90fe9f`。
- [macOS Acceptance Package #38548270116](https://github.com/EasyIndie/EasyInputMethod/actions/runs/38548270116)：构建、全部离线回归、Developer ID签名、Apple Accepted公证、票据装订、附件制作、离线源码重建及上传均成功；未重复调度。
- 本机附件验证器核对四附件摘要、v0.1.0版本、universal双架构、应用及源码提交身份通过；隔离解包后codesign deep/strict、stapler validate和Gatekeeper均通过，source=Notarized Developer ID。
- 可执行SHA-256：`3a3c2b9cf85a0fa96383de04543161baea59a7ddaec06751e082eb55cfe113c6`。

附件私有目录：`/private/tmp/lampyris-it25-signed-38548270116/candidate-lwReDY`；只读信任副本：`/private/tmp/lampyris-it25-trust-38548270116/Lampyris-0.1.0-universal/Lampyris.app`。临时目录可能被系统清理，持久身份见[结构化证据](evidence/013-it25-ci-notary.json)及远端运行附件（保留30日）。

此包含IT-24及IT-25，未包含报告012三项新核心修复。未运行/注册/安装应用、未修改真实配置或学习词库、未创建tag或发布Release。IT-25新包原生体验与同一最终包双设备验收仍待；继续本地功能收口，最终集中推送须遵循对应载荷授权，不能因本次批准扩大公开范围。

CI平台有既有Node.js20 Action迁移及arm64容量提示；编译零诊断门禁通过。这些提示另属CI维护，不在本次十文件代码载荷中修改。
