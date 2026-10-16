# 045：PR #45合入、正式签名候选与包级验收

2026-10-17。用户明确恢复PR #45推送、四CI全绿后合入及Apple签名公证，安装另行确认。本轮从额度恢复断点继续，未重新安装或操作桌面。

## 已完成的正式候选流程

- PR #45最新head `daa7971e6fbebfe30c627aadb4a84fe40a0bf7fa`的check/dco/fuzz/macos全部SUCCESS；CI38912736120及DCO38912735997，正常合入，无绕过。
- main合入提交 `abdb83ff2a6ff3cd1a63a48e0c446822e18e2f86`，与head源码树相同：`5380f16dc41e1f4f2cf583b399af895394d3a8f6`。main CI38934285127通过。
- 签名公证运行38934284869成功：完整验证/离线回归、Developer ID签名、Apple公证、同工具链配套源码重建、四附件上传和签名材料清理均通过。未创建Release。
- 下载同commit附件后，发布附件验证器核验版本/摘要/双架构/包内清单/配套源码身份通过；本机codesign deep strict、stapler及Gatekeeper通过，source=Notarized Developer ID。应用只解包检查，未启动/注册/安装。

## 正式附件

持久证据目录：`platforms/macos/build/final-menu-abdb83f/`。下载四附件位于`ci-assets/candidate-5BewsM/`。

| 附件 | 字节 | SHA-256 |
|---|---:|---|
| Lampyris-0.1.0-universal.zip | 4,950,721 | 2377dcde8c3502e8279c00f786ca9794d759d2f89f009846e7f3bcd8af572c72 |
| Lampyris-0.1.0-source.tar.gz | 13,021,507 | b650a431b2a6a085939509bf6a7cbe56d010bdb12627029f5a28d5cecb24713a |

签名执行文件SHA：`c4a0703481b56806fd454d0d301874916f82b5685a8a65c0af978ac61b093151`；arm64+x86_64。正式包BUILD-INFO记录Swift6.3.3、SDK26.5、macOS26.6.2和Rust1.98.1。

审核head的本地ad-hoc审核包另有配套源码离线逐字节通过，剥签名SHA `d28febca0e5b5452c0ec4788ab220f900e8dd5edb19e4112c5f37082687f6e10`；它不能代替上述正式签名包。

## B本地重建的真实失败与既有范围

对正式附件运行run-repro.sh，本地编译成功，但最终cmp返回exit1。原始失败日志`signed-local-repro.log`和`local-repro-result.json`保留，没有重复盲跑或改记PASS。原脚本退出会删除临时重建目录；诊断使用此前已保存且源码树一致的本机审核产物，与正式包作剥签名分片和LC_BUILD_VERSION比较，并明确来源。

CI为Swift6.3.3/SDK26.5，B为Swift6.4/SDK27.0；两个SDK值也在Mach-O中得到确认。CI同工具链重建的剥签名SHA与正式包本机剥签名一致：`759eef1c78c58ccdef51b9e833ba2c1f8cb29974af26621bebdc6a5f434daf13`。分片大小和SHA均记录于toolchain-comparison.json及load-command日志，未声称已逐字节解释全部差异。

`docs/隐私与安全.md`已有约定只承诺相同Swift/SDK/架构的未签名载荷比较，不承诺不同SDK一致；本轮没有新增例外或放宽标准。因此签名/完整性包级结果可通过，B跨工具链比较仍是FAIL；用户独立复现保持BLOCKED，不能以CI同环境重建代填。

## 正式报告状态

已建立既有schema 2的formal-report.json，绑定正式ZIP摘要、main commit、双架构、签名公证及本机只读应用版本库存。只读版本库存均标明未测试，不能当应用验收。

正式检查输出：`pass=1 fail=0 skip=0 blocked=22`，exit3（BLOCKED），唯一PASS为package-validation，证据为同commit附件、签名/票据/信任以及CI同工具链源重建。B跨工具链失败独立保留，independent-reproduction原因明确引用。正式MVP未完成。

剩余包括独立账号/数据保护、四路径恢复、同包实际输入/长组合/撤销/焦点/模式/睡眠、键盘VoiceOver、系统外观/多屏、真实IMK性能、A/macOS13与B实际运行、六客户端安全适配、用户独立复现和五工作日。新候选/学习按钮执行器仍只有本地保护测试，系统菜单跨进程归属未验，不扩大通过范围。

## 实机环境与交接

当前仅查到日常账号joker501；用户尚未确认建立或登录标准测试账号，已解释它是不需Apple ID的本机系统用户。当前joker会话不能直接操控另一个账号GUI，需要在测试账号中运行工具/Codex，并重新核对该账号权限与工具环境。未创建账号、切换用户、复制账号密钥或投放共享目录。

`TEST-ACCOUNT-HANDOFF.md`列出正式包/源码转交、同commit核验、明确安装安排、登录后宿主核验、私有资源、逐动作保护和记录要求。复制物只需已校验包/源码与公开摘要，不包含日常用户配置词库。安装仍单独确认，不根据旧“空闲”发键。

B当前已装SOURCE-COMMIT仍1621a6d，执行文件SHA仍`296a698c0a51ff43eac29ace4800aef5826be8eb1295204ca08fe047ca9097ec`；未重复安装，主目录原有产品代码/Makefile未覆盖。报告及证据仅作为本地验收记录保存，不推进已经冻结的正式候选SHA。下一步等待明确测试环境及安装安排，随后按同候选开始实机，不能宣称验收已完成。

## 用户后续选择（ADR-196）

用户明确不使用单独账号，改为当前账号的自有资源、焦点及数据审计方案；此前独立账号不是产品必须条件。安装abdb83f及本轮空闲待答复；正式报告状态未提升，没有操作桌面。

## 安装状态后续更新

用户随后明确授权AB同装且分别确认空闲；两台均已升级同一abdb83f并通过已装副本/信任及数据源保持核验（报告046）。均等待用户重新登录后观察新宿主，未发键；本报告前文“未安装”为当时包级阶段记录。
