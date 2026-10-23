# HANDOFF — 当前状态

## 0. 元信息

- 更新：2026-10-22 / pi；固定dev，main代码`a38f816`（#89 沙盒原型）（#81…#95 均四CI绿后merge：ADR-255…265、构建号与报告135…146；开放PR 0）。dev已快进同步，无遗留分支。
- build5已作为固定开发包装机：0.1.0/build5，main`299d8f8`，执行`aef8b7cc4e81f6ed3aa141ce03463b39eacc0696e5791a735412cbd4b649a68a`，隔离公证run39775362738，ZIP`b6f9536ace0f7c7ba1b61b217136789d2ea813c54f4be904dc745a54376dc763`；旧build4备份`replacement-r__fdgwk/previous.app`（build2更早备份仍在`replacement-p57rjckg`）。
- 135原生（build5，schema2）：首轮50键p95 **11.569ms**/max42.663ms（唯一≥16ms为冷首键），暖态p95 10.726ms/max12.587ms，附加45键p95 10.303ms/**0次≥16ms**，engine p95 1.122ms；六词+八项附加（含xi'an、mixed Enter/Esc、五笔）通过，加载器无行为回归。
- 内存：build6 三轮新宿主按 ADR-263 口径（稳态 physical + 私有已提交同时 ≤30MiB）**3/3 满足**：physical 28.0–28.8M、私有 24.6–25.3M；高水位 peak 29.6–31.9M 单列不计。最终 RC 需同协议复测后才关闭 30MB。
- 收尾：ABC、marker删除、精确宿主退出；生产两SHA与开发config未变，开发私有词库正常学习到`0ccce15f…`（14行）。
- 136/137/258/138：**build6（main 2b34d0f，执行`21f5b05b…`，run 39787338801）已实机归因**——冷首键total 42.657ms，content 18.347ms = layout 9.043（首次窗口尺寸同步）+ measure 6.302（首次文本测量）+ 0.17；稳态 content 2.87ms、首轮p95 10.56ms、暖态9.97ms。结论：冷首键是每进程一次性成本，不做预热。内存固定时点 30.0→32.6→33.7→33.6M（峰34.5，swap 4.07GB），**30MB仍未关闭**。ADR-256新增Ed25519负载验签（7项XCTest+严格release构建通过，仍不下载/不安装）；ADR-257确定网站/App Store双渠道互斥，商店版需沙盒+去自更新，待不发布沙盒构建实测。

## 1. 设备与数据

| 设备 | 已装包/执行SHA | 数据及输入源 | 恢复点 |
|---|---|---|---|
| A（历史，本轮回读） | Intel/macOS13.7.8，生产07bbb2f/681fb1c8… | config809e2cae…，词库2ee1a469…/217行 | 报告103，不操作A |
| B生产 | arm64/macOS27.0.1，17053e1/535d546f… | config3bc1117c…，词库74f76e92…/29行；全程只读 | 生产包未替换 |
| B固定开发 | 299d8f8/0.1.0/**build5**，执行`aef8b7cc…`，公证39775362738；ZIP`b6f9536a…` | 当前ABC，开发宿主0个，marker不存在；dev config`3bc1117c…`，私有词库14行/`0ccce15f…` | `replacement-r__fdgwk/previous.app`=build4（build2=replacement-p57rjckg）；135证据在`platforms/macos/build/acceptance-135/` |

- 固定开发根：`~/Library/Application Support/LampyrisIMKDev/lampyris-imk-d4fcecfb-af99-4b9a-a590-55fa99e16f05`；身份不变，不反复移除/添加/注销。
- 手工文稿“萤火虫性能验收-115.txt”历史窗口2372保留；本轮未操作，禁止清空。
- 计时 marker 契约：固定根`perf-trace.enabled`（0600，内容=trace绝对路径），必须在启动宿主前写入；本轮trace=`platforms/macos/build/acceptance-134/perf-134/trace.jsonl`（目录0700、文件0600）。

## 2. 最近完成

| 范围 | 当前结果/证据 |
|---|---|
| 147 公钥入库 | ADR-266：公钥提交在 `packaging/macos/update-public-key.txt`，构建/工作流默认读取（不再需要变量/Secret）；私钥仅 Secret 且有「追踪文件无 PEM」回归；已用该公钥复验 v0.1.0 真实签名通过/篡改拒绝 |
| 146 发版自动化 | ADR-265 `release-appcast.py`（离线签名+自检+appcast，5 项回归）与 `release.yml`（tag v*：验证→构建→签名公证→appcast→gh release create，always 清理）；真实 tag/密钥未配置，未实际发版 |
| 145 更新来源 | ADR-264：`update.feed_url`（空/https，拒绝凭据/fragment）默认空=GitHub Releases feed；设置新增「更新」分区；公钥固定签名包；更新程序经 ime-config 读取；GitHub 资产主机重定向允许列表；密钥生成/Actions 步骤见 `docs/更新发布流程.md`。尚未配真实密钥与 feed |
| 142 appcast | ADR-262 `feed.py` 与 Swift 同规则（https-only、1MiB/1000 项/深度 16、拒绝 DTD、64 字节签名、build 点分比较）；`upgrade.py` 接 `--feed-file/--feed-url`，无更新 `up-to-date` 退出 0；11+16 项离线回归；真实 feed/公钥/HTTPS 未做 |
| 141 下载器 | ADR-261 `--payload-url` 仅 https、私有临时文件、256MB 上限、重定向复查、结束清理；顺序下载→验签→替换；7 项离线回归，升级相关共 15 项；真实 feed/公钥/HTTPS 演练未做 |
| 140 沙盒原型 | ADR-260 `build.sh --sandbox` 产出不安装的 LampyrisSandbox.app；探针证明配置/学习数据只落容器、真实 Application Support 未写；连接名/entitlements 纳入 2 项离线回归；条件性 go，MAS 签名/安装注册/审核未验 |
| 139 升级路径 | ADR-259 `upgrade.py`：验签→解包→候选校验→停精确宿主→备份→原子替换→落地复验→回滚，dry-run 默认；8 项离线回归进自动发现，仍无下载器/真实 feed |
| 136/137 定位与验签 | 冷首键差额定位到AppKit可见布局（未改代码）；更新程序新增Ed25519负载验签与`--verify-payload`，仍默认关闭；商店口径ADR-257 |
| 135 build5原生 | ADR-255后复验：功能无回归、p95 11.569ms、附加0次≥16ms；宿主physical29.5M/峰29.9M、碎片5.7M、换出14.6M，见报告135 |
| 134 build4原生 | 静态核验后安装，换包保留旧包、输入源集合不变；schema2 100键首轮p95 10.770ms、hideUs p95 1.222ms，见报告134 |
| ADR-255加载内存 | `from_tsv`单遍偏移构建+拼音/简繁去逐行临时分配；离线四表峰值24.4–25.4M→15.8M，frag/换出如实记录；verify/193离线/strict双架构通过 |
| 133/132 | #80最终e17abfc四CI绿merge0f91349；小bounds与同尺寸原生设置修复已入main，build4实机stderr未见约束提示复现路径 |
| #79历史 | 9f7f68f四CI绿merge b618972，隐藏计时schema2入main |

## 3. 未决

- 30MB门禁：口径已定（ADR-263：稳态 physical + 私有已提交，peak 不计）；build6 三轮 3/3 满足，最终 RC 同协议复测后正式关闭。
- 16ms门禁：build5单轮p95 11.569ms、附加0次≥16ms，仍按单候选记录；冷首键42.7ms仍在，且已定位到AppKit可见布局（本项目代码约1.1ms/5.7ms），下一步需schema3子阶段或非冻结采样再动。
- 同最终RC三模式/重启/显示与数字提交、完整客户端矩阵（浏览器/VSCode/终端/微信安全草稿）未跑；更新闭环（feed/key、真实下载验签、回滚、App Store可行性）与D16扩词覆盖有限。
- A/B、安装升级/异常恢复/卸载、VoiceOver/多屏/真实睡眠、独立第三方重建、五工作日未完成；权限/设备缺口不冒充PASS。
- 交接辅助脚本`--prompt`骨架仍有旧main直推/最近ZIP误标示例，只用其采集表。

## 4. 下一步

1. 本批（报告136/137+ADR-256/257+更新程序验签）一次性`dev → main`PR，四CI绿后merge并快进dev。
2. 30MB：等满足前置条件（loadavg1<8、swap used<2G、无 Xcode 构建）后按固定时点协议复测 build6；仅能自动切回 ABC，进入开发源仍需用户手动一次。143 轮因 loadavg 54/swap 6.1G 判为无效，不作证据。
3. 更新闭环下一步：配置真实 Ed25519 密钥（Variable 公钥、Secret 私钥），打首个 tag 走 `release.yml` 真实验证一次；然后用真实包做 HTTPS 下载→验签→`upgrade.py --apply` 演练（含回滚）；再做下载确认/进度 UI 与镜像回退。
4. App Store：沙盒原型已验证配置根/零网络/连接名；下一步需要真实 Distribution 签名 + MAS 安装位置与输入源注册实测，再决定是否投入商店工程。
4. 之后锁同RC做三模式/重启/客户端矩阵与五日。不创建tag/Release。

## 5. 边界

- 核心默认离线、零遥测，配置只由ime-config写；不改真实学习数据、UserDefaults或HIToolbox，不清用户词库。
- 脚本可**切回 ABC**（`selsrc com.apple.keylayout.ABC`，回读确认）；**切入第三方开发源不可自动完成**（返回 0 但系统 current 不变，父源 -50），仍需用户手动一次。首次增删输入源手工。不注销/不重启、不改 HIToolbox；发键仅自有夹具逐键保护，不向真实聊天发键。
- 固定dev→main单PR、merge commit保留祖先、四CI当前head绿后处理完；make verify零诊断，不绕main-only签名。

## 9. 会话日志

- 2026-10-22 / pi：首个 `v0.1.0` Release 已发布（appcast 518B、ZIP 5.2MB，`sparkle:version=6`），修了 YAML heredoc、bash3.2 mapfile、发布 ZIP 包装目录三个真实问题；ADR-266 公钥入库并用它复验真实签名；真实 `--apply` 待用户确认。

- 2026-10-23 / pi：#96（公钥支持 Variable/Secret + 签名自检工作流）四CI绿 merge `a38f816`；待配置私钥 secret 后手动触发 Update Signing Check。

- 2026-10-22 / pi：#95（ADR-265 签名 appcast+release 工作流）四CI绿 merge `5133e83`；dev快进同步、PR 0。

- 2026-10-22 / pi：ADR-265 发版自动化落地：`release-appcast.py`（Ed25519 签名+自检+appcast，5 项离线回归）与 `release.yml`（tag 校验/构建/公证/公钥构建/发布/清理）；未配置真实密钥、未打 tag、未联网。

- 2026-10-22 / pi：#94（ADR-264 更新源可配置+GitHub 默认）四CI绿 merge `1c8c32e`；dev快进同步、PR 0。

- 2026-10-22 / pi：ADR-264 更新来源可配置落地：`update.feed_url`（空/https）默认 GitHub Releases、设置新增「更新」分区、公钥固定、更新程序经 ime-config 读取、GitHub 重定向允许列表；密钥生成与 Actions 发版步骤写入 `docs/更新发布流程.md`；config/settings/updater/upgrade 回归通过，未接真实密钥。

- 2026-10-22 / pi：#93（ADR-263 内存口径+build6 三轮判定）四CI绿 merge `a7079b0`，dev快进同步、PR 0。

- 2026-10-22 / pi：B 项完成：按 ADR-263 口径（稳态 physical + 私有已提交同时≤30MiB）三轮新宿主回测，build6 3/3 满足（physical 28.0–28.8M、私有 24.6–25.3M），p95 10.81–12.00ms；高水位 29.6–31.9M 单列；收尾 ABC 自动还原、marker 删除、宿主精确退出，生产数据未变。

- 2026-10-22 / pi：#92（报告143：无效内存轮+输入源自动化）四CI绿 merge `9be2f3e`，dev快进同步、PR 0。

- 2026-10-22 / pi：B 项复测因 loadavg 54、swap 6.1G 判无效（不复用其数据）；实测 `TISSelectInputSource` 可脚本切换已启用源，已用 `selsrc` 自动切回 ABC 并完成收尾；写入前置条件与自动化边界（143）。

- 2026-10-22 / pi：#91（ADR-262 appcast 解析/版本选择+11 项回归）四CI绿 merge，dev快进同步、PR 0。

- 2026-10-22 / pi：ADR-262 appcast 解析/版本选择落地并与 Swift 规则对齐；`upgrade.py` 支持 feed 入口（无更新不下载）；11+16 项离线回归通过；未联网、未动已装 build6。

- 2026-10-22 / pi：#90（ADR-261 下载器+7 项回归）四CI绿（dco 卡住后重跑）merge `f4a9906`，dev快进同步、PR 0。

- 2026-10-22 / pi：ADR-261 下载器落地（https-only、私有临时文件、256MB 上限、重定向复查、结束清理），顺序仍下载→验签→替换；7 项离线回归通过（升级相关共 15 项）；未请求真实 feed/未联网。

- 2026-10-22 / pi：#89（ADR-260 沙盒原型+2 项离线回归）四CI全绿 merge `fed5936`，dev快进同步、PR 0。

- 2026-10-22 / pi：ADR-260 沙盒原型落地：`build.sh --sandbox`、entitlements、沙盒配置探针与 2 项离线回归；实测沙盒宿主正常启动、容器创建、真实 Application Support 未写、无 deny 日志；未安装/未注册输入源，已装 build6 与生产数据未动。

- 2026-10-22 / pi：#88（ADR-259 upgrade.py+8 项离线回归）四CI全绿 merge `8fe146c`，dev快进同步、PR 0。

- 2026-10-22 / pi：ADR-259 落地 `packaging/macos/upgrade.py` 与 8 项离线回归（替换/回滚/验签失败/停宿主失败/dry-run/符号链接/缺 bundle），默认 dry-run；未执行真实安装、未请求 feed；build6 与生产数据未动。

- 2026-10-22 / pi：#87（报告138+ADR-258证据）四CI全绿 merge `050f434`，dev快进同步、PR 0；build6 仍为已装开发包。

- 2026-10-22 / pi：ADR-258/schema3 经 #85 合并、build号6经 #86 合并（main `2b34d0f`）；构建核验 build6 后一次换源完成 47 条 schema3 采样：冷首键 content 18.347=layout9.043+measure6.302，稳态2.87ms，p95 10.56ms；内存30.0→33.6M未关闭；收尾ABC、marker删除、精确退出，生产数据/开发config未变。

- 2026-10-22 / pi：#84（ADR-256/257+报告136/137）head b050fb5 四CI全绿，merge `95ef68b`，dev快进同步、PR 0。

- 2026-10-22 / pi：136定位冷首键（离屏插桩1.10/5.73ms，原生差额在AppKit可见布局；微优化无收益已回退）并复测build5宿主内存29.9→34.8M（30MB未关闭）；137新增ADR-256 Ed25519负载验签（7项XCTest+严格release构建通过，仍不下载/不安装）与ADR-257双渠道互斥口径；已装build5与生产数据未动。

- 2026-10-22 / pi：#83（报告135+ADR-255宿主证据）head 8f5522d 四CI全绿，merge `eebe326`，dev快进同步、PR 0；build5仍为已装开发包，30MB待低压力复测。

- 2026-10-22 / pi：build号递增PR #82（4→5）四CI绿merge `299d8f8`；从该main构建并核验build5（run39775362738），用户只切一次源完成schema2 95键与八项附加（含xi'an），宿主physical29.5M/峰29.9M、碎片5.7M、换出14.6M；收尾ABC、marker删除、宿主退出，生产数据/开发config未变，私有词库正常学习。

- 2026-10-22 / pi：#81（ADR-255+报告134）head 83cc263 check/dco/fuzz/macos 四CI全绿，merge `01c85f3`，dev普通快进同步、PR 0；build4仍为已装开发包，下一步从新main构建build5复测宿主内存。

- 2026-10-22 / pi：从main 0f91349构建并核验build4固定开发签名包（run39770165333），ABC换包保留旧包/数据；marker先行、用户只切一次源，schema2 100键完成（首轮p95 10.770ms，hideUs p95 1.222ms），六词+八项附加含xi'an通过；宿主physical37.8M/峰40.3M、碎片12.0M→ADR-255单遍紧凑加载离线峰值24.4–25.4M→15.8M；verify/离线/strict通过，收尾ABC、marker删除、宿主退出，生产数据与开发config不变。

- 2026-10-22 / Codex：用户要求额度耗尽前跨代理交接；只读重采dev@0ca1019/main0f91349、PR0、ABC/PID50615/无marker，补完整已装双SHA及下一步签名构建/计时顺序，写专用提示词并校正模板旧main直推示例。不触发新构建/换包/采样；交接make verify完整通过、零诊断。

- 2026-10-22 / Codex：132调用栈+实际频次后加同尺寸原生设置保护；133另修cell小bounds无效矩形，旧回归失败后通过、三个可见进程stderr空。两步193离线/双架构/verify通过，#80最终e17abfc四CI绿merge0f91349、dev同步/PR0；已装build2保持，ABC/PID50615/无marker、数据配置SHA保持。

- 2026-10-22 / Codex：132尺寸保护验证后保存5363ff8。LLDB定位可见约束提示到PaddedCandidateCell零/小bounds内缩；ADR-254先写，新回归旧版失败/修复后通过，三次可见复查stderr全空（133），完整门禁待完成；两个小提交同批PR，未装包/发键。

- 2026-10-22 / Codex：132可见窗口测量+精确子进程采样确认窗口系统同步；ADR-253只加同尺寸setContentSize保护，三对内容P95降15–24%但hide最大值均回退。动画反序失败未采纳，冷29ms未复现；定向回归通过，完整门禁/PR待收尾，未碰已装包/源/真实文稿。
