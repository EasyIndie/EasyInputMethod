# HANDOFF — 当前状态

## 0. 元信息

- 更新：2026-10-22 / pi；固定dev，main代码`37b2fb7`（#89 沙盒原型）（#81…#111 均四CI绿后merge：ADR-255…273、报告135…154；生产 v0.1.0/build6、开发 build7 已装；开放PR 0）。dev已快进同步，无遗留分支。
- build5已作为固定开发包装机：0.1.0/build5，main`299d8f8`，执行`aef8b7cc4e81f6ed3aa141ce03463b39eacc0696e5791a735412cbd4b649a68a`，隔离公证run39775362738，ZIP`b6f9536ace0f7c7ba1b61b217136789d2ea813c54f4be904dc745a54376dc763`；旧build4备份`replacement-r__fdgwk/previous.app`（build2更早备份仍在`replacement-p57rjckg`）。
- 135原生（build5，schema2）：首轮50键p95 **11.569ms**/max42.663ms（唯一≥16ms为冷首键），暖态p95 10.726ms/max12.587ms，附加45键p95 10.303ms/**0次≥16ms**，engine p95 1.122ms；六词+八项附加（含xi'an、mixed Enter/Esc、五笔）通过，加载器无行为回归。
- 内存：build6 三轮新宿主按 ADR-263 口径（稳态 physical + 私有已提交同时 ≤30MiB）**3/3 满足**：physical 28.0–28.8M、私有 24.6–25.3M；高水位 peak 29.6–31.9M 单列不计。最终 RC 需同协议复测后才关闭 30MB。
- 收尾：ABC、marker删除、精确宿主退出；生产两SHA与开发config未变，开发私有词库正常学习到`0ccce15f…`（14行）。
- 签名 tag 校验按 ADR-268 延后：`git-allowed-signers` 存在才强制，否则 warning；更新包验签不受影响。
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
| 159 v0.1.2 | Release `v0.1.2`（build10，appcast version 10）含**静态链接更新程序**；v0.1.1 坏更新程序资产已删；本机生产升级到 0.1.2/build10（build8 备份），更新程序装 `~/Applications`。配置/词库变为 `809e2cae…`/`f3e2eef…`（69 行，新 Schema+学习）。⌥G/菜单实测待用户 |
| 158 快捷键+静态链接 | ADR-275：`hotkey.open_update`（默认 alt+g，菜单同源）；更新程序改静态链接 `libime_ffi.a`（修复 v0.1.1 启动崩溃）；优先 LaunchServices 查找。版本/构建号 bump 到 0.1.2/build10；v0.1.2 待发，v0.1.1 更新程序资产计划移除 |
| 157 v0.1.1 | Release `v0.1.1`：主包 build9 + 源码 + sha256 + appcast（version 9）+ **签名/公证的更新程序** `LampyrisUpdateCheck-0.1.1.zip`；更新程序已装 `~/Applications`，公钥一致。生产仍 build8；菜单点击与跨版本升级待实测 |
| 156 RC build8 | 0.1.0/build8（`3c9c199f…`，universal、公证，main 45db5a2）已安装到生产身份，含「检查更新…」入口；build6 备份在 `updates/rc-build8-backup`；配置/词库未变。带更新程序的 Release 需 v0.1.1+新 tag，完整 RC 矩阵未开始 |
| 155 更新程序分发 | ADR-274：`ci-sign.sh --app` 支持单独签名/公证；Release 将附 `LampyrisUpdateCheck-<version>.zip`+sha256；菜单优先启动已安装更新程序。脚本回归通过；待打新 tag 才有该资产 |
| 154 更新入口 | ADR-273：输入法菜单新增「检查更新…」；已装更新程序则 `--ui`，否则打开 Releases 页面；宿主零网络（仅 LaunchServices）。控制器/预览 9 项回归+冒烟通过；更新程序随包分发待后续，生产 v0.1.0 尚无此入口 |
| 153 开发版命名 | ADR-272：开发版固定「萤火虫 开发版」/「Lampyris Dev」+ 角标图标；build7 已装（执行 `4d1ee6e8…`）。**实机：重启前菜单仍显示旧名，重新登录后生效**（系统缓存显示名）；换包比较改为递归剔除显示名/图标/版本；生产包仍 v0.1.0/build6 |
| 152 UI全流程 | 真实GitHub feed：检查→下载→验签→确认→安装通过（同版本重装），生产仍v0.1.0/build6、配置/词库不变、ABC还原；修复标识trim误判与错误可读性；跨版本/镜像回退UI未验 |
| 151 更新UI | ADR-271：`--ui` 窗口（检查→下载进度→验签→确认→安装→结果）；Swift `UpdateInstaller` 与 `upgrade.py` 语义一致；`UpdateDownloader` https-only/白名单/256MB。22 项测试+UI 冒烟；未真实网络点完流程 |
| 150 独立重建 | 从 tag `v0.1.0` 干净克隆构建 universal 成功并启动；4 份数据表与 Release 逐字节一致、版本/构建号一致；可执行 SHA 因签名/工具链不同未复现（不宣称 bit-reproducible） |
| 149 镜像回退 | ADR-270：`update.feed_mirrors`（UrlList ≤8、https、去重保序）；更新程序「主源→镜像」回退、成功即停；`upgrade.py --feed-urls` 同步并放行同主机直链；文档 `docs/更新源与镜像.md`。未在真实大陆网络验证 |
| 148 生产升级演练 | v0.1.0（build6，universal，`5709716c…`）真实安装：GitHub feed→验签→`--apply` 成功；回滚旧包→再升级通过；配置 `3bc1117c…`/词库 `74f76e92…`（29 行）不变；修复 lsd 持有误判（ADR-269） |
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

1. 更新闭环已打通（feed/公钥入库/下载/验签/替换回滚/多镜像/生产升级演练）。剩余可选项：区域镜像搭建（用户后续）、下载确认与进度 UI、多公钥/密钥 ID 轮换（ADR-267）。
2. 最终 RC：从当前 main（含 v0.1.0 之后修复：公钥入库、镜像、精确停宿主）构建新候选（build7），锁同一候选后完成
   三模式/重启/显示与数字提交、客户端矩阵（Safari/Chrome/VSCode/Terminal/微信安全草稿）、VoiceOver/多屏/真实睡眠、
   A/B、安装升级异常恢复卸载、五工作日观察；30MB 与 16ms 在 RC 上按既有协议复测后再正式关闭。
3. App Store：沙盒原型已验证配置根/零网络/连接名；下一步需 Apple Distribution 证书 + 描述文件，实测 MAS 安装位置与输入源注册。
4. 冷首键为一次性成本（layout 9ms + measure 6.3ms），不再优化；不创建未经授权的 tag/Release。

## 5. 边界

- 核心默认离线、零遥测，配置只由ime-config写；不改真实学习数据、UserDefaults或HIToolbox，不清用户词库。
- 脚本可**切回 ABC**（`selsrc com.apple.keylayout.ABC`，回读确认）；**切入第三方开发源不可自动完成**（返回 0 但系统 current 不变，父源 -50），仍需用户手动一次。首次增删输入源手工。不注销/不重启、不改 HIToolbox；发键仅自有夹具逐键保护，不向真实聊天发键。
- 固定dev→main单PR、merge commit保留祖先、四CI当前head绿后处理完；make verify零诊断，不绕main-only签名。

## 9. 会话日志

- 2026-10-24 / pi：产品页视觉规范入库（ADR-283，`docs/design/产品页视觉规范.md`）；后续平台页沿用同一风格。

- 2026-10-24 / pi：Pages 产品页改版：仅 DMG 安装，6 项特点、亮暗配色与移动端布局（报告 175）。

- 2026-10-24 / pi：v0.1.12/build20 发布，DMG 含安装器、卸载器（保留数据/彻底清理）和完整说明；本机/`pro` 升级（报告 174）。

- 2026-10-24 / pi：DMG 增加卸载器（保留数据/彻底清理）与安装卸载说明（ADR-282）；0.1.12/build20 待发。

- 2026-10-23 / pi：v0.1.10/build18 发布（DMG 图形安装、版本显示统一）；本机/`pro` 升级，DMG 留在 `pro:~/Downloads`（报告 172）。

- 2026-10-23 / pi：新增 DMG 图形安装器与发布流程（ADR-281）；更新页标题改「更新」、版本统一；0.1.10/build18 待发。

- 2026-10-23 / pi：v0.1.7/build15 发布，更新程序含官方图标并重做窗口；本机与 `pro` 均升级（报告 170）。

- 2026-10-23 / pi：更新程序加官方图标、重做窗口版式（ADR-280）；0.1.7/build15 待发并复验 Dock 图标。

- 2026-10-23 / pi：v0.1.6/build14 发布，更新程序 universal；Intel `pro` 与本机均升级，`pro` 上更新程序 `--ui` 启动正常（报告 168）。

- 2026-10-23 / pi：修复更新程序仅 arm64 导致 Intel 无法打开（ADR-279）：build.py 双架构 + lipo 断言，Release 加 Rust targets；0.1.6/build14 待发并装到 `pro` 复验。

- 2026-10-23 / pi：`ssh pro` 第二台设备升级到 0.1.5/build13（旧 0.1.2/build10 备份），配置/词库不变，更新程序 0.1.5 已装（报告 166）。

- 2026-10-23 / pi：v0.1.5 发布（run 39961835435，build13）：关于页显示 `0.1.5 · 构建 13`；生产已升级（build12 备份），更新程序 0.1.5，Pages 已更新。

- 2026-10-23 / pi：v0.1.4 发布（run 39953723558，build12）含 Shift HUD 与进度条修复；生产升级、更新程序 0.1.4 已装；待用户复验 HUD/进度条。

- 2026-10-23 / pi：验收反馈修复（ADR-277）：Shift 切换中英补 HUD；更新窗口进度条仅在下载阶段显示；版本升 0.1.4/build12 待发。

- 2026-10-23 / pi：v0.1.3 发布（build11，含 LampyrisTIS helper）；修复签名顺序后验收/公证通过；本机用 ZIP 内 install.sh 覆盖生产成功且未抢源，配置/词库不变；Pages 更新。

- 2026-10-23 / pi：ADR-276 简化安装/卸载：随包签名 helper（register/enable/disable/switch-abc），安装自动注册、卸载自动禁用；版本升 0.1.3/build11 待发。

- 2026-10-23 / pi：GitHub Pages 更新并部署（PR #118，Pages run 39944750053）：一键安装/卸载命令 + 平台架构表 + ⌥G 说明；https://easyindie.github.io/EasyInputMethod/

- 2026-10-23 / pi：v0.1.2 发布（run 39938190051），更新程序改静态链接并在本机验证启动；生产升级 build10、更新程序装 ~/Applications；配置/词库新基线已记录。

- 2026-10-23 / pi：定位 v0.1.1 更新程序启动崩溃（动态链接 CI 绝对路径 dylib），改静态链接；新增检查更新快捷键 alt+g；版本升 0.1.2/build10，待发布。

- 2026-10-23 / pi：v0.1.1 发布成功（run 39933564550），含已签名/公证的更新程序资产；修了两处流水线问题（bash 变量花括号、ASC issuer secret 名）；更新程序已装到 ~/Applications。

- 2026-10-22 / pi：build8 RC（run 39924589316）核验并安装到生产身份（build6 备份保留），含检查更新入口；配置/词库未变；待 v0.1.1 Release 与完整矩阵。

- 2026-10-22 / pi：ADR-274 更新程序打包/签名链路落地（ci-sign --app + release 资产），待新 tag 生效。

- 2026-10-22 / pi：#111（ADR-273 检查更新入口）四CI绿 merge `adcc3ff`；dev快进同步、PR 0。

- 2026-10-22 / pi：ADR-273 输入法菜单「检查更新…」落地（更新程序/浏览器二分，宿主零网络），菜单回归与预览冒烟通过。

- 2026-10-22 / pi：用户实机确认开发版改名/角标在**重新登录后**才在输入源菜单生效（系统缓存显示名），已记入报告153；生产包未变。

- 2026-10-22 / pi：#110（开发包元数据递归比较修复 + 报告153补 build7 证据）四CI绿 merge `adcc3ff`；dev快进同步、PR 0。

- 2026-10-22 / pi：开发版命名/图标落地并安装 build7（run 39914200961）：显示名「萤火虫 开发版」/「Lampyris Dev」+ 角标；修复换包对嵌套图标键的误判（递归剔除可演进字段）。

- 2026-10-22 / pi：ADR-272 固定开发版名称/图标（去 UUID 前缀 + 角标图标），换包元数据允许显示名/图标演进；回归通过，待 build7 实机观察。

- 2026-10-22 / pi：#107（报告152 UI全流程）四CI绿 merge `840a9f1`；dev快进同步、PR 0。

- 2026-10-22 / pi：更新UI真实全流程演练通过（报告152），修复标识trim与错误信息；生产包/配置/词库未变，ABC还原。

- 2026-10-22 / pi：#106（ADR-271 更新UI+Swift安装器）四CI绿 merge `a11dcad`；dev快进同步、PR 0。

- 2026-10-22 / pi：ADR-271 更新 UI 落地（`--ui` 窗口 + Swift 安装器/下载器），22 项更新程序测试通过、窗口冒烟正常；未发 Release、未动生产包。

- 2026-10-22 / pi：#105（报告150 独立重建）四CI绿 merge `1e45d7b`；dev快进同步、PR 0。

- 2026-10-22 / pi：独立重建验证（报告150）：tag v0.1.0 干净克隆构建成功、数据/版本一致、可启动；二进制因签名与工具链差异未逐字节复现，如实记录。

- 2026-10-22 / pi：#104（ADR-270 镜像回退）四CI绿 merge `1f5d99c`；dev快进同步、PR 0。

- 2026-10-22 / pi：ADR-270 多镜像回退落地（配置/更新程序/安装器/文档），18+14+24 项回归通过；未在真实大陆网络验证。

- 2026-10-22 / pi：#103（ADR-269 精确停宿主+报告148）四CI绿 merge `c3532d3`；dev快进同步、PR 0。

- 2026-10-22 / pi：生产升级演练完成（v0.1.0/build6/universal），含回滚→再升级；修复 `lsd` 持有导致的误拒（ADR-269），配置/词库未变，新宿主启动正常。

- 2026-10-22 / pi：#102（ADR-268 签名 tag 延后启用）四CI绿 merge `0e04f0a`；dev快进同步、PR 0。

- 2026-10-22 / pi：#100（ADR-266 公钥入库）四CI绿 merge `6b3ffd5`；dev快进同步、PR 0。

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
