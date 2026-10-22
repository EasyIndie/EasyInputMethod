# HANDOFF — 当前状态

## 0. 元信息

- 更新：2026-10-22 / pi；固定dev，main代码`0f913492b9a0e27ab32bba95462cfcf4291e1625`（#80已合并，开放PR 0）。本轮在dev新增ADR-255内存修复与报告134，随同批dev→main唯一PR收尾，不新建分支。
- build4已作为固定开发包装机：0.1.0/build4，执行`49a49a2a7f47de895e282754a66e35c8d90403c723a7ce471b95a7de25d4a3ef`，隔离公证run39770165333，ZIP`b3b38bb4ac664305164b8bedbdd454e403d0bcfd0ae13328604717aa011380d2`；旧build2备份`replacement-p57rjckg/previous.app`。
- 134原生（schema2）：100键，首轮50键total p95 **10.770ms**/max37.299ms（仅冷首键≥16ms），暖态p95 10.620ms，engine p95 1.114ms，hideUs p50/p95 0.849/1.222ms；六词+八项附加（含xi'an、mixed Enter/Esc、五笔）实际读回通过。
- 内存：宿主采样后physical37.8M/峰40.3M、malloc活跃17.4M/碎片12.0M/换出18.7M，冷启动8.9M → **30MB未关闭**。ADR-255单遍紧凑加载把四表离线峰值24.4–25.4M降到15.8M（活跃10.9M不变），原生复验待下一签名包。
- 收尾：ABC、marker删除、精确宿主退出；生产两SHA与开发config未变，开发私有词库正常学习到`8b7084e4…`（14行）。`make verify`/`make macos-offline-tests`/strict universal全绿零诊断。

## 1. 设备与数据

| 设备 | 已装包/执行SHA | 数据及输入源 | 恢复点 |
|---|---|---|---|
| A（历史，本轮回读） | Intel/macOS13.7.8，生产07bbb2f/681fb1c8… | config809e2cae…，词库2ee1a469…/217行 | 报告103，不操作A |
| B生产 | arm64/macOS27.0.1，17053e1/535d546f… | config3bc1117c…，词库74f76e92…/29行；全程只读 | 生产包未替换 |
| B固定开发 | 0f91349/0.1.0/**build4**，执行`49a49a2a…`，公证39770165333；ZIP`b3b38bb4…` | 当前ABC，开发宿主0个，marker不存在；dev config`3bc1117c…`，私有词库14行/`8b7084e4…` | `replacement-p57rjckg/previous.app`=build2；134证据在`platforms/macos/build/acceptance-134/` |

- 固定开发根：`~/Library/Application Support/LampyrisIMKDev/lampyris-imk-d4fcecfb-af99-4b9a-a590-55fa99e16f05`；身份不变，不反复移除/添加/注销。
- 手工文稿“萤火虫性能验收-115.txt”历史窗口2372保留；本轮未操作，禁止清空。
- 计时 marker 契约：固定根`perf-trace.enabled`（0600，内容=trace绝对路径），必须在启动宿主前写入；本轮trace=`platforms/macos/build/acceptance-134/perf-134/trace.jsonl`（目录0700、文件0600）。

## 2. 最近完成

| 范围 | 当前结果/证据 |
|---|---|
| 134 build4原生 | 静态核验（版本/commit/身份/root/arm64/Team2N62934Y28/spctl/stapler/数据SHA）后安装，换包保留旧包、输入源集合不变；schema2分段与冷首键见报告134 |
| ADR-255加载内存 | `from_tsv`单遍偏移构建+拼音/简繁去逐行临时分配；离线四表峰值24.4–25.4M→15.8M，frag/换出如实记录；verify/193离线/strict双架构通过 |
| 133/132 | #80最终e17abfc四CI绿merge0f91349；小bounds与同尺寸原生设置修复已入main，build4实机stderr未见约束提示复现路径 |
| #79历史 | 9f7f68f四CI绿merge b618972，隐藏计时schema2入main |

## 3. 未决

- 30MB门禁：宿主37.8M/峰40.3M为ADR-255**修复前**数据；需下一签名包复测主机稳态（含碎片与换出分类），不忽略swap、不用RSS替代。
- 16ms门禁：本候选单样本p95达标但仍按单候选记录；冷首键37.3ms（content15.7ms、status7.4ms）仍在，暖态无≥16ms样本；不提前预热掩盖。
- 同最终RC三模式/重启/显示与数字提交、完整客户端矩阵（浏览器/VSCode/终端/微信安全草稿）未跑；更新闭环（feed/key、真实下载验签、回滚、App Store可行性）与D16扩词覆盖有限。
- A/B、安装升级/异常恢复/卸载、VoiceOver/多屏/真实睡眠、独立第三方重建、五工作日未完成；权限/设备缺口不冒充PASS。
- 交接辅助脚本`--prompt`骨架仍有旧main直推/最近ZIP误标示例，只用其采集表。

## 4. 下一步

1. 本批一次性`dev → main`PR（ADR-255代码+ADR+报告134+HANDOFF），跟进当前head四CI直至merge，merge后dev普通快进同步；不squash/rebase/强推。
2. 从新main（含ADR-255）构建**build5**固定开发签名包：静态核验ZIP/版本/架构/签名/公证/数据SHA；保留配置/词库/旧包。
3. 换包后先写marker再启动宿主，只请用户切开发源一次；集中复测宿主稳态内存（碎片/换出/physical）、冷首键与mixed剩余项；逐键焦点守卫，失焦立即停止。
4. 采样后删marker、恢复mode，用户ABC后按精确路径/SHA退出宿主；随后推进更新闭环与商店可行性，再锁同RC完整矩阵与五日。不创建tag/Release。

## 5. 边界

- 核心默认离线、零遥测，配置只由ime-config写；不改真实学习数据、UserDefaults或HIToolbox，不清用户词库。
- 不自动切源、注销或重启；发键仅自有夹具逐键保护，不向真实聊天发键，保留手工文稿与旧包恢复路径。
- 固定dev→main单PR、merge commit保留祖先、四CI当前head绿后处理完；make verify零诊断，不绕main-only签名。

## 9. 会话日志

- 2026-10-22 / pi：从main 0f91349构建并核验build4固定开发签名包（run39770165333），ABC换包保留旧包/数据；marker先行、用户只切一次源，schema2 100键完成（首轮p95 10.770ms，hideUs p95 1.222ms），六词+八项附加含xi'an通过；宿主physical37.8M/峰40.3M、碎片12.0M→ADR-255单遍紧凑加载离线峰值24.4–25.4M→15.8M；verify/离线/strict通过，收尾ABC、marker删除、宿主退出，生产数据与开发config不变。

- 2026-10-22 / Codex：用户要求额度耗尽前跨代理交接；只读重采dev@0ca1019/main0f91349、PR0、ABC/PID50615/无marker，补完整已装双SHA及下一步签名构建/计时顺序，写专用提示词并校正模板旧main直推示例。不触发新构建/换包/采样；交接make verify完整通过、零诊断。

- 2026-10-22 / Codex：132调用栈+实际频次后加同尺寸原生设置保护；133另修cell小bounds无效矩形，旧回归失败后通过、三个可见进程stderr空。两步193离线/双架构/verify通过，#80最终e17abfc四CI绿merge0f91349、dev同步/PR0；已装build2保持，ABC/PID50615/无marker、数据配置SHA保持。

- 2026-10-22 / Codex：132尺寸保护验证后保存5363ff8。LLDB定位可见约束提示到PaddedCandidateCell零/小bounds内缩；ADR-254先写，新回归旧版失败/修复后通过，三次可见复查stderr全空（133），完整门禁待完成；两个小提交同批PR，未装包/发键。

- 2026-10-22 / Codex：132可见窗口测量+精确子进程采样确认窗口系统同步；ADR-253只加同尺寸setContentSize保护，三对内容P95降15–24%但hide最大值均回退。动画反序失败未采纳，冷29ms未复现；定向回归通过，完整门禁/PR待收尾，未碰已装包/源/真实文稿。
