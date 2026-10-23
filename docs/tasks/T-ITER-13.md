# T-ITER-13：发布附件与构建元信息

- 状态：进行中（ADR-112附件门禁完成本地回归；构建身份/target预检及日志移除已验证；真实签名候选待验）
- 目标：dry_run和正式发布使用同一核验，包与源码对应。
- 实现：validate-release.py离线读取ZIP/tar，不解压执行。检查二进制/源码各自外部摘要、ZIP全文件摘要、版本/tag/提交、BUILD-INFO已签名声明、实际Mach-O arm64+x86_64及执行权限、默认输入数据、离线源码材料。发布只读取核验输出的四个附件。
- 回归：`PYTHONDONTWRITEBYTECODE=1 python3 packaging/macos/tests/test-validate-release.py`，9项合成测试通过；本机真实universal可执行文件架构检查通过。测试不是Apple签名/公证验证；没有下载最终包、触发Release或提交变更。
- ADR-113：SDK/系统/Xcode从实际构建环境派生，CLT不虚构Xcode；target在编译/暂存清理前预检。4项回归通过，strict universal通过，产物SDK27.0/26A425、Xcode27.0/27A266a、最低13.0与本机实际一致，产品契约核验通过。
- ADR-114：移除生产宿主按键字符NSLog；FFI冒烟/渲染辅助工具补warnings-as-errors。FFI运行时通过，相关宿主编译零诊断。
- 下一步：锁提交后核验真实签名公证附件，执行dry_run；当前工作树含未提交变更，开发包的HEAD字段不能冒称最终源码身份。
- 验收：make verify零诊断、strict universal及隔离预览；最终候选身份与摘要可复核，演练/发布共用门禁，失败不能发布。
- 关联：IT-14/15，ADR-064/065/112；GPL对应源码同页发布。

2026-10-21优先级调整（ADR-240/报告111）：用户明确先MVP输入体验，再继续升级；#64原型保留评审。版本治理待实现：Cargo权威版本派生产品X.Y.Z、独立正递增构建号、移除打包校验两版本强制相等、SBOM/包名/说明同步；双渠道同版本和源码候选、分别记录构建/签名/SHA。正式发布仍独立授权。

2026-10-22 用户要求优先清理PR：#64更新原型不合入输入候选，关闭PR但保留分支feat/website-updater-integration@eab23b1e47ad62fe32e2b83850f709b253e3b9d6及评审历史，输入出口后重新对齐main评审；不算升级功能完成。见122。

2026-10-22 用户明确要求升级原型也经评审/必要补验进入main：在固定dev恢复#64独立模块，固定上游源码/许可/测试SHA复核通过；实际严格并发错误以两个不可变值Sendable本地补丁解决并登记/逆向校验，补离线边界与默认关闭验证。显示版本由Cargo派生；仍无下载/包验签/安装回滚/GUI/后台/商店分发，升级功能不算完成。见ADR-248、126。

2026-10-22 ADR-249：版本派生链实现中；宿主/独立更新程序、包名/源码说明/SBOM/构建记录/重建及发布核验共用Cargo版本和受审阅构建序号，定向18项回归通过。性能因本机高负载保留待验，未锁RC、不启用更新或发布。

127补验：ca15f49真实审核归档5.18MB，配对归档版本/源码/build核验和同机离线双架构字节重建通过；不是第三方独立核验。PR #77持续跟进，原生/升级/最终RC门禁不变。

2026-10-22 #77四CI通过合入b317590，版本治理工程完成；实际固定开发包39719374289静态发现隔离构建遗漏版本字段，拒绝安装。ADR-251/报告128修复同一派生链及安装器新增SemVer字段兼容，候选0.1.0/build2；19项定向与完整verify零诊断通过。由唯一PR #78承接，合入后签名重建再核验。原型升级闭环、正式RC/独立第三方验收不算完成。

128收尾：#78最终head fc65b65四CI绿合入18fcbbf，0.1.0/build2固定开发包39728402241签名/公证/版本与ABC原位换包通过，四份数据SHA保持；实际新宿主输入待用户切源，不冒充正式升级/最终RC通过。

2026-10-22 报告136/137：①冷首键定位——离屏插桩显示本项目渲染代码稳态约1.10ms/首次5.73ms，原生content 4.15/15.5ms的差额在可见窗口AppKit布局；试做微优化无可重复收益已回退，下一步需schema3子阶段或非冻结采样。②内存复测（build5，系统swap4.14GB）：29.9→34.8M区间，30MB仍不关闭。③ADR-256新增Ed25519负载验签（CryptoKit，7项XCTest+严格release构建通过，仍不下载/不安装）；ADR-257确定网站/App Store双渠道互斥，商店版需沙盒+去更新，待沙盒构建实测。

2026-10-22 ADR-259/报告139：新增`packaging/macos/upgrade.py`——验签→解包→候选校验→停精确宿主→备份→原子替换→落地复验→回滚→0600 receipt；默认dry-run，`--apply`必须带已签名验签器。8项离线回归（替换/回滚/验签失败/停宿主失败/dry-run/符号链接/缺bundle）通过并进macos-offline-tests自动发现。仍无下载器、真实feed/公钥与实机升级演练，升级闭环不宣称完成。

2026-10-22 ADR-260/报告140：`build.sh --sandbox`产出不安装的LampyrisSandbox.app（app-sandbox+mach-register例外，无网络权限）；沙盒探针验证`ime_config_init/set/get`只落容器、真实Application Support未被写入；Info.plist连接名=CFBundleIdentifier+_Connection、entitlements无网络权限纳入2项离线回归。条件性go；MAS Distribution签名/安装位置与输入源注册/审核仍需真实商店构建验证。

2026-10-22 ADR-261/报告141：`upgrade.py`增加`--payload-url`（仅https，file://需显式测试开关），流式0700/0600临时文件、256MB上限、重定向协议复查、结束即清理；顺序下载→验签→解包→校验→停宿主→替换。新增7项离线回归，升级相关共15项全PASS。仍无正式feed/公钥、无真实HTTPS演练、无UI提示。

2026-10-22 ADR-262/报告142：`feed.py`实现与Swift更新程序一致的appcast解析/版本选择（https-only、1MiB、1000项、深度16、拒绝DTD/ENTITY、64字节签名、build点分比较）；`upgrade.py`接入`--feed-file/--feed-url/--current-build`，无更新直接up-to-date退出0不下载。11项feed回归+16项升级回归全PASS。仍无真实feed/公钥、HTTPS演练与架构/渠道筛选。

2026-10-22 ADR-264/报告145：新增`update.feed_url`（Url类型：空或https、拒绝凭据/fragment），设置自动新增「更新」分区（5分区/20项）；默认feed=GitHub Releases，公钥固定签名包不可被用户替换；更新程序链接ime-config读取来源；GitHub资产主机重定向允许列表（Swift/Python同步）。config 17项、settings、updater FeedSource、upgrade 18项回归通过。仍无真实密钥/feed/HTTPS演练与Actions流水线。

2026-10-22 ADR-265/报告146：新增`release-appcast.py`（ZIP长度/SHA→OpenSSL Ed25519签名→自检→Sparkle兼容appcast，拒绝非https/空包/非法build/缺钥）与`.github/workflows/release.yml`（tag v*：verify/离线回归/通用构建/签名公证/公钥构建更新程序/appcast自检/gh release create/always清理，tag须等于Cargo版本）。5项离线回归通过；真实tag、公钥变量与私钥secret未配置，未实际发版。

2026-10-22 ADR-266/报告147：Ed25519公钥入库`packaging/macos/update-public-key.txt`（32字节Base64），Updater/build.py默认读取并校验，release/self-check工作流不再用变量/Secret读取公钥；私钥仅Secret并有「追踪文件无PEM」回归。用该公钥构建的更新程序复验v0.1.0真实ZIP+appcast签名通过、篡改被拒。真实安装`--apply`待用户确认。

2026-10-22 ADR-268：签名tag校验延后（设备不稳定）：release.yml保留git tag -v，仅在packaging/git-allowed-signers存在时强制；缺失时warning并继续。README/发布文档标记待启用；更新包Ed25519验签始终强制。

2026-10-22 报告148/ADR-269：生产升级演练完成。旧17053e1→v0.1.0 build6（universal，5709716c…），GitHub feed下载+验签+--apply成功；回滚到旧包再升级通过；配置3bc1117c…/词库74f76e92…(29行)不变，新宿主启动正常。首次重试因lsd持有被拒并自动回滚，改为只终止精确二进制持有者（系统服务持有只记录）。

2026-10-22 ADR-270/报告149：大陆GitHub访问容错。新增update.feed_mirrors（UrlList≤8、https、去重保序），更新程序主源→镜像顺序回退、成功即停；upgrade.py新增--feed-urls并按同主机直链放行。文档`docs/更新源与镜像.md`含镜像搭建/要求/验证。18+14+24项回归通过；未在真实大陆网络验证，未发新Release。

2026-10-22 ADR-271/报告151：更新UI与Swift安装器。`--ui`窗口：检查(主源→镜像)→下载进度→验签→确认→安装→结果；UpdateInstaller与upgrade.py语义一致（精确停宿主/备份/原子替换/回滚/0600 receipt）；UpdateDownloader https-only+GitHub资产白名单+256MB上限。22项更新程序测试通过，UI启动冒烟通过；未在真实网络点完整流程。
