# HANDOFF — 当前状态

## 0. 元信息

- 更新：2026-10-22 / pi；固定dev，main代码`050f434`（#81 ADR-255、#82/#86 构建号、#83 报告135、#84 ADR-256/257、#85 schema3、#87 报告138 均四CI绿后merge；开放PR 0）。dev已快进同步，无遗留分支。
- build5已作为固定开发包装机：0.1.0/build5，main`299d8f8`，执行`aef8b7cc4e81f6ed3aa141ce03463b39eacc0696e5791a735412cbd4b649a68a`，隔离公证run39775362738，ZIP`b6f9536ace0f7c7ba1b61b217136789d2ea813c54f4be904dc745a54376dc763`；旧build4备份`replacement-r__fdgwk/previous.app`（build2更早备份仍在`replacement-p57rjckg`）。
- 135原生（build5，schema2）：首轮50键p95 **11.569ms**/max42.663ms（唯一≥16ms为冷首键），暖态p95 10.726ms/max12.587ms，附加45键p95 10.303ms/**0次≥16ms**，engine p95 1.122ms；六词+八项附加（含xi'an、mixed Enter/Esc、五笔）通过，加载器无行为回归。
- 内存：宿主physical **29.5M**/峰**29.9M**、malloc活跃17.2M/碎片**5.7M(25%)**/换出14.6M（build4：37.8/40.3、17.4/12.0/18.7），首次落到30MB线下，但系统swap已用3.9GB，只记候选证据，**不宣布门禁干净关闭**。
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
| 139 升级路径 | ADR-259 `upgrade.py`：验签→解包→候选校验→停精确宿主→备份→原子替换→落地复验→回滚，dry-run 默认；8 项离线回归进自动发现，仍无下载器/真实 feed |
| 136/137 定位与验签 | 冷首键差额定位到AppKit可见布局（未改代码）；更新程序新增Ed25519负载验签与`--verify-payload`，仍默认关闭；商店口径ADR-257 |
| 135 build5原生 | ADR-255后复验：功能无回归、p95 11.569ms、附加0次≥16ms；宿主physical29.5M/峰29.9M、碎片5.7M、换出14.6M，见报告135 |
| 134 build4原生 | 静态核验后安装，换包保留旧包、输入源集合不变；schema2 100键首轮p95 10.770ms、hideUs p95 1.222ms，见报告134 |
| ADR-255加载内存 | `from_tsv`单遍偏移构建+拼音/简繁去逐行临时分配；离线四表峰值24.4–25.4M→15.8M，frag/换出如实记录；verify/193离线/strict双架构通过 |
| 133/132 | #80最终e17abfc四CI绿merge0f91349；小bounds与同尺寸原生设置修复已入main，build4实机stderr未见约束提示复现路径 |
| #79历史 | 9f7f68f四CI绿merge b618972，隐藏计时schema2入main |

## 3. 未决

- 30MB门禁：build5两次测量区间29.5–34.8M（视换出/压力），swap高压力下不关闭；需低压力且固定采样时点复测后才谈口径，不忽略swap、不用RSS替代。
- 16ms门禁：build5单轮p95 11.569ms、附加0次≥16ms，仍按单候选记录；冷首键42.7ms仍在，且已定位到AppKit可见布局（本项目代码约1.1ms/5.7ms），下一步需schema3子阶段或非冻结采样再动。
- 同最终RC三模式/重启/显示与数字提交、完整客户端矩阵（浏览器/VSCode/终端/微信安全草稿）未跑；更新闭环（feed/key、真实下载验签、回滚、App Store可行性）与D16扩词覆盖有限。
- A/B、安装升级/异常恢复/卸载、VoiceOver/多屏/真实睡眠、独立第三方重建、五工作日未完成；权限/设备缺口不冒充PASS。
- 交接辅助脚本`--prompt`骨架仍有旧main直推/最近ZIP误标示例，只用其采集表。

## 4. 下一步

1. 本批（报告136/137+ADR-256/257+更新程序验签）一次性`dev → main`PR，四CI绿后merge并快进dev。
2. 30MB：换低压力时机（无 Xcode 构建、swap 回落）按同一固定时点协议复测 build6，再判断能否关闭；冷首键已归因为一次性成本，不再优化。
3. 更新闭环下一步：实现下载器（先验签再写盘）与正式 feed/公钥，再用真实签名包演练 `upgrade.py --apply`（含失败回滚）；App Store 先做不发布沙盒构建验证配置根/输入源/学习数据。
4. 之后锁同RC做三模式/重启/客户端矩阵与五日。不创建tag/Release。

## 5. 边界

- 核心默认离线、零遥测，配置只由ime-config写；不改真实学习数据、UserDefaults或HIToolbox，不清用户词库。
- 不自动切源、注销或重启；发键仅自有夹具逐键保护，不向真实聊天发键，保留手工文稿与旧包恢复路径。
- 固定dev→main单PR、merge commit保留祖先、四CI当前head绿后处理完；make verify零诊断，不绕main-only签名。

## 9. 会话日志

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
