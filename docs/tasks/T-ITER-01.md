# T-ITER-01：多应用验收资源所有权

- 状态：进行中（脚本保护已接入，原生隔离验收及安全聊天覆盖未完成）
- 模型建议：pro（涉及资源所有权、状态契约或跨层行为判断）
- 前置：无
- 目标：安全执行多应用验收且不影响测试前已有数据（P0，对应迭代计划 IT-01）
- 步骤：识别 run-input-apps.sh 与 IMK 验收脚本的创建/清理路径；记录唯一测试资源标识，清理仅针对这些对象；焦点不符合测试对象时停止；保存并恢复剪贴板全部类型与输入源；聊天用隔离测试草稿，不使用真实已有输入。
- 验收：预存文档、未保存文档、聊天草稿、多类型剪贴板在正常退出、断言失败、可捕获中断后保持原状；仅测试资源被清理。不可捕获中断须无破坏性清理并给恢复说明。 提交前 `make verify` 零诊断；涉及 Swift 跑 strict 宿主构建与隔离预览；脚本先在隔离用户环境覆盖成功/失败/中断，不先用真实数据试错。
- 铁律提醒：配置只走 ime-config；行为/协议变更先 ADR；核心零网络；一次一个改动，文档同步。
- 禁止：关闭所有文档；清空已有聊天输入；恢复无所有权的前台控件；运行旧脚本验证真实数据。
- 参考：[迭代计划](../迭代计划.md)、[审计009](../reviews/009-macos-product-engineering-audit.md)、根目录 AGENTS.md；配置行为另读配置架构.md与相关ADR。

## 2026-10-11 推进记录

- ADR-083：先限定清理所有权。新增共享 owned-resources.sh，创建即登记应用对象ID，两脚本退出只关闭登记对象；失败不回退前台/全部对象。
- 多应用退出不再清空当前字段/剪贴板或关闭未创建的输入法面板；INT/TERM按退出路径清理。
- 自动化用mock覆盖正常、失败、INT、TERM及失效对象/非法ID；未运行真实应用。
- **尚未完成**：原生应用对象ID协议实测、每次输入的焦点保护、完整剪贴板/输入源保存恢复、微信隔离草稿。真实环境脚本仍不能开放，IT-01保持进行中。

## 第二子步（2026-10-11）

- ADR-085：新增多项目/多类型二进制剪贴板备份，0600临时文件；多应用脚本保存原输入源精确ID，退出恢复，恢复失败保留备份。检测到剪贴板changeCount变化时拒绝覆盖新内容；此检查不能消除跨进程检查后写入的极短竞争窗口，仍要求隔离验收环境。
- 移除多应用路径输入后Delete清空操作；微信改为BLOCKED且整体返回失败，不向已有会话投递按键。
- 独立随机命名剪贴板实测：多项目、多类型、二进制/中文往返、空内容及并发变化保护通过；编译零诊断。没有操作通用剪贴板或切换用户输入源。
- 尚需：完整焦点保护、原生应用ID协议、输入源恢复实机证据、IMK脚本接入状态保护以及隔离聊天覆盖。IT-01继续进行中，不开放真实环境脚本。

## 第三子步（2026-10-11）

- ADR-086：输入/快捷键同调用校验frontmost、前台对象ID；逐字输入还核对AX文本角色；失败停止，不自动重新前置并继续。
- 两脚本输入/常用快捷键已接入；TextEdit读取和清空显式寻址登记ID；读取失败输出BLOCKED，不能被当成空内容通过。
- 多应用剪贴板复制要求changeCount变化，避免旧内容被误当新上屏结果；浏览器仍需隔离环境验证地址栏角色，不以窗口ID证明所有字段安全。
- 隔离mock共7项通过，包括检查失败后不发送后续字符、未登记/非法动作不调用原生API、清空寻址登记文档。
- 尚需：原生对象/AX角色及输入源恢复验证、IMK状态恢复/配置安全、安全聊天覆盖与完整失败/中断实机证据。IT-01仍进行中，不开放live。

## 第四子步（2026-10-11）

- ADR-087：IMK脚本切换前保存原输入源，退出精确恢复；配置监听/异常注入经fixture-guard记录摘要，外部或未登记修改时不覆盖，恢复失败保留备份。
- 5项隔离文件测试通过：字节/权限恢复、外部修改保留、部分失败写入、缺失/符号链接拒绝，正常/失败/INT/TERM退出恢复。保护有检查与写入间竞争边界，仍仅用于隔离验收。
- 原生字典只读核对发现document无数字ID；ADR-088改为窗口ID，TextEdit按关联文档寻址。所有权mock7项及生成焦点AppleScript原生编译通过；未创建原生窗口或输入。
- 下一步：隔离会话中验证窗口创建关联、AX角色/焦点切换、原输入源恢复及完整异常清理；微信仍BLOCKED，整卡不关闭。当前原生编译只证明语法，不能代替执行证据。

## 原生协议探针与当前阻塞（2026-10-11）

- 新增probe-owned-textedit.applescript及run-owned-probe.py：只创建空文档，核对窗口关联并按本次对象关闭，正常/注入失败后核对原有窗口ID；不发键、不读取既有文档，不改配置/输入源。
- 本轮尝试原生协议探针没有取得结果；CUA返回Mac锁屏且无法自动解锁。已精确停止本轮探针及执行shell，不杀TextEdit或用户应用；没有原生通过证据，无法据此确认窗口状态。
- ADR-089：AppleEvent5秒/外层15秒有界执行，超时/空输出/非零退出BLOCKED；不得清理未知窗口。新4项假执行器测试通过，原7+5项仍通过；PASS文本来自测试假执行器，不是原生结果。
- 探针原生编译通过。下一步设备解锁后在隔离会话验证窗口/焦点、输入源与异常恢复；微信仍BLOCKED，IT-01不关闭。

## 原生重试（2026-10-12）

有界探针连续两次重试均以BLOCKED/3返回AppleEvent超时（-1712）；正常路径未通过，注入失败路径未执行。单独只读TextEdit窗口ID查询也超时，当前阻塞位于创建测试文档之前，原因尚未确定。未取得窗口关联/清理协议通过证据，整卡保持进行中。

### 授权后重试

60秒只读窗口ID请求成功。正式探针exit 3/-1700（document不能转换为reference），正常及失败清理协议均未获得通过证据，不能据此关闭IT-01或清理未知窗口。下一步修正原生对象寻址；此前mock/编译不能替代此验证。

## 当前原生协议进展（ADR-091）

设备B正式探针normal/failure两路径均通过。TextEdit的实际文档字段为path，window无document属性；关闭文档后隐藏window对象仍可能存在。探针改用唯一空白临时文件、文档path与唯一窗口名核验，并断言文档已关闭、目标窗口不可见、原可见窗口ID集合不变。成功删除本次文件，失败保留路径；4项离线测试补验保留/删除/权限。make verify零诊断通过。

下一步迁移owned-resources.sh及两实机脚本的TextEdit创建/读取/清空/关闭协议，保留文件身份并覆盖失败/中断；当前旧window.document语句仍不可执行。随后做AX焦点、输入源与配置恢复隔离实测；整卡仍进行中。早期失败尝试的临时文件/文档未批量清理，不把探针通过当成所有环境恢复完成。

## 独有IMK入口与注册探针（2026-10-12）

ADR-115：独有bundle/连接身份和私有配置/词库，原生normal/failure/INT/TERM及错误所有权拒绝均通过，真实配置/词库摘要未变；4项离线保护通过。ADR-117注册协议5项mock通过并接CI。设备B原生TIS注册返回0但没有独有输入源，lsregister注销返回1，记BLOCKED；未启用/选择/发键。复查独有集合为空后精确移除本次软链及根目录，未覆盖用户状态。证据：platforms/macos/build/source-probe-35916ef2/。真实IMK装载、输入与恢复仍未通过，不开放旧live入口。

设备A可通过ssh pro访问，2026-10-12只读核对Intel/macOS13.7.8、Swift5.8.1、干净c294b67工作区；已安装包88833aa。用户负责独立核验；试用人数已按ADR-125调整为用户本人一位，计划2026-10-13开始，累计5工作日要求保留。

### ADR-118注册阻塞诊断

LaunchServices -f与-u原生均exit0；TIS仍exit3（状态0、独有集合为空），仅按精确ID复查也为空，排除bundle属性过滤遗漏。未出现授权弹窗或明确权限拒绝；根因未确定，下一步区分实体路径与签名条件。自有软链/根目录已清理，证据在platforms/macos/build/source-probe-5020a4a4/。驱动追加有界识别与0600诊断文件；6项离线回归通过（非原生IMK证据）。

### 实体路径与签名对照（2026-10-12）

ADR-119：独有实体包ad-hoc及Developer ID hardened runtime两组注册均BLOCKED（TIS返回0、独有集合为空）；LaunchServices识别与注销成功，Developer ID严格签名校验通过。未启用/选择/启动/发键，实体包和临时根目录已清理，原输入源/启用集合未变。证据platforms/macos/build/source-probe-physical-c6b4be89/。不能据此排除公证、bundle/IMK声明或系统会话条件；下一步核对系统识别契约。新增文件树保护3项回归接CI，IT-01仍进行中。

### 测试身份与注销后复核（2026-10-12）

ADR-120/121最新进展：隔离包身份保留.inputmethod.后，设备B实体ad-hoc包成功枚举两个独有TIS身份。首次禁用后默认模式仍显示enabled，清理门禁正确BLOCKED；精确核对非测试启用集合/当前源及自有文件树后注销移除实体包，新进程复查两个身份均禁用、完整启用集合恢复。新版数据隔离normal/failure/INT/TERM和错误标记拒绝原生通过，真实文件未变，临时根目录已清理；证据platforms/macos/build/source-probe-identity-7cb49b02/。新的注销后复核已接入实体驱动，整驱动尚待端到端复跑；服务启动/选择恢复/客户端输入未验，不关闭IT-01。

### 防回归与端到端复跑（2026-10-12）

ADR-122：测试构建和实体注册前置身份校验已接入，缺inputmethod段、连接名和模式清单漂移有回归，5项通过并由现有CI执行。设备B新版完整实体注册/清理驱动exit0，枚举2源，原输入源/完整启用集合恢复；无参数隔离服务READY且持有PID清理通过，真实数据摘要不变。证据platforms/macos/build/source-probe-e2e-6aadf5a7/；随后四路径/错误标记拒绝回归通过并删除根目录。未选择输入源、未验证客户端输入，IT-01仍进行中。

稳定排错经验已沉淀至platforms/macos/README.md的“IMK包标识与注册排错”；后续修改测试身份不得删去.inputmethod.段，也不得把.app后缀改成.inputmethod。

### 选择恢复与人工启用条件（2026-10-12）

ADR-123/124/126：增加身份绑定的选择恢复日志、实体包私有根声明和包自身上下文操作。数据隔离normal/failure/INT/TERM、错误根声明/权限/所有权拒绝原生通过；覆盖报告schema 2的10项回归通过，make verify零诊断、170产物隐私扫描通过。

外部helper与测试包自身进程均未成功选择独有模式：父源enabled=false，模式enabled=true、可选=true，TISSelectInputSource返回-50；Developer ID对照亦未解决。不计为选择恢复四路径通过。证据`platforms/macos/build/selection-c76b222a/`。

人工登记包64663035暂保留于用户Input Methods目录，独有私有根仍保留。中文CFBundleDisplayName未成为TIS名称，用户反馈找不到中文测试名；已改为请求查找实际父源名称LampyrisIMKTest，等待反馈。复查曾观察到当前源由用户改为正式Lampyris.default，禁止按旧ABC日志覆盖该选择。未发键、未替换正式包，IT-01继续进行中。

### 人工发现失败与名称资源补齐

用户确认中文名与实际ASCII名均无法在系统设置中找到。短时启动旧包pid21172成功提交IMK端点且已精确终止；历史连接名拒绝日志不能直接归因本包（build/connection-probe-64663035/）。ADR-127补齐隔离工厂的本地化父源/模式名称；5项回归及plutil检查通过。新包选择仍返回-50/父源disabled，已注销移除新实体包，完整输入源状态恢复，私有根保留诊断（build/localized-source-probe-751cec67/）。make verify零诊断/170产物通过。旧人工包64663035保留，不重复请求查找，不开放旧live。

### CI公证准备（ADR-128/129）

旧人工包严格签名有效，Gatekeeper拒绝原因Unnotarized Developer ID，尚非发现失败已证实根因。用户指定CI公证。独立工作区提交1d599c3仅新增隔离CI入口/工厂/回归与文档，基于c294b67；原生构建/normal、5+2回归、签名清理模拟、actionlint及完整验证通过。凭据仍仅main使用，签名前绑定设备B目标根，不下载后修改签名资源。自动审批拒绝公开远程分支推送，已请求明确目的地/代码载荷授权；未推送/建PR/合并/提交Apple。

用户已明确授权推送及创建PR，2026-10-12已创建https://github.com/EasyIndie/EasyInputMethod/pull/38并关联任务。DCO补齐后提交f5d1bbf，代码与已验证1d599c3一致；CI检查中，未合并/提交Apple。

PR #38最新f5d1bbf的check/DCO/fuzz/macos全部通过，GitHub状态CLEAN。合入main及上传Apple公证的补充授权已请求，未回复前不执行；现有推送/创建PR授权不变。

### 已公证包与登录发现对照（ADR-130）

PR #38合入a292534；隔离公证运行38258905282成功，附件SHA/commit/目标根、签名、staple及Gatekeeper本机通过。已公证包选择仍-50/父源disabled，原当前源和完整启用集合恢复，本次实体/进程已清理。证据ci-isolated-38258905282附件目录。随后只在本次源全禁用、目标不存在及公证校验通过后重新放置同一独有实体包7bb55aa3并做LS登记；未调用TIS启用/选择/发键，当前/启用集合不变。用户选择现在安排手动注销重新登录；尚无完成或系统设置可添加结果，停止桌面验证等待，IT-01未关闭。正式安装包未替换。

### 登录后发现与选择恢复通过（ADR-131/132）

用户截图确认两个测试源出现在菜单；TIS复查7bb55aa3父源/模式均enabled=true。原临时根被重新登录清理，在公证/身份/目标根/当前临时路径核验后独占恢复0700空根及0600owner，不恢复配置内容。用户明确批准切换恢复后，normal/failure/INT/TERM四路径全部通过，原当前源/启用集合、真实配置/词库摘要保持；未发键，实际客户端输入未验。post-login-result.json及post-login-selection证据在CI附件目录。旧64663035已按精确身份/签名/声明核验后禁用、注销及可恢复归档，其他源不变；归档build/retired-isolated-64663035/。新公证包保留，整卡不关闭。

### 实际客户端焦点阻塞（2026-10-12，ADR-133）

用户已批准独有TextEdit文档wq+空格测试；切换后前台检查阻止发键，未完成“你”的提交断言，原源/完整启用集合及真实数据摘要保持。修复关闭已消失窗口后读取可见性导致的清理误报，7项回归及make verify零诊断通过。

用户确认Codex辅助功能/自动化已全部允许并关闭系统设置后仍复现。只读NSWorkspace诊断记录切换前com.apple.TextEdit、切换后com.apple.systempreferences，后者PID由1194变4476；此观察不能独自解释触发原因。独立诊断进程AX信任为false不代表Codex授权状态；System Events前台查询还有AppleEvent超时。等待用户说明系统设置页面/提示，不自动重新抢回焦点、不以重复发键绕过保护。最新证据build/installed-textedit-hp3arkbn/result.json、textedit-native-focus-k4vq2qnz；测试文档关闭，源恢复复核与前次集合相符。整卡仍进行中。

### 重复启用修复与实际权限主体（2026-10-12，ADR-134）

用户关闭设置再试仍被焦点保护阻止。分阶段只读探针显示before-enable-parent为TextEdit，after-enable-parent立即为System Settings；已启用父源仍被重复启用。source-state助手改为仅未启用时调用启用API，修复后前台检查通过，normal/failure/INT/TERM选择恢复四路径全通过（build/source-idempotent-pyfmihms），启用集合保持。实际输入尚未通过AX检查，不记输入PASS。

精确自有TextEdit文本控件角色/focused查询返回“osascript不允许辅助访问”（-1719），明确了实际执行者权限不足；不能把用户已允许Codex视为此执行者已获授权。已请求用户允许osascript；不绕过AX角色保护。证据build/textedit-ax-role-w3uefw2z、installed-textedit-eog590zf、textedit-source-trace-eg308zb6。Swift warnings-as-errors、7项回归和make verify零诊断/170产物通过；真实数据/原源保持，独有测试文档关闭。

### 已授权但当前调用链不可用（2026-10-12，ADR-135）

用户确认osascript已允许，原生仍返回辅助访问-1719；路径确认为/usr/bin/osascript，只读UI elements enabled=false。尚未确认授权刷新/责任进程机制，不重复要求用户检查同一开关，不重置TCC、不绕过焦点/AX保护。单文档驱动在创建资源及切换源之前增加有界UI脚本检查，仅精确true继续；false/异常/超时直接BLOCKED。新增3项回归验证失败前无资源创建，原生实测在只读前置检查停止；既有7项通过。最新实际探针build/installed-textedit-3h4qvjhs，AX诊断textedit-ax-role-c_olgq0k；原源/启用集合及真实数据摘要恢复。提交仍未验收，整卡未完成。

### 授权责任归属已定位及解除（2026-10-12，ADR-136）

父链实际为/Applications/ChatGPT.app/Contents/MacOS/ChatGPT→内嵌CodexCLI→Homebrew Python→/usr/bin/osascript。同次请求tccd的responsible/subject为com.openai.codex、责任路径为ChatGPT.app，kTCCServiceAccessibility有效策略Denied (System Set)；因此之前仅按错误名称要求授权osascript不准确。宿主plist显示名ChatGPT、bundle ID com.openai.codex；/Applications/Codex.app不存在；严格签名通过。此证据定位拒绝主体，不证明签名失效或macOS普遍bug。

用户允许精确/Applications/ChatGPT.app后只读UI elements enabled=true，原生前台及AX保护通过。wq+空格实际执行，但提交“你”断言exit97，stderr为空；原源/完整启用集合及真实数据摘要恢复。授权问题已解除，下一步诊断实际输入结果，不能继续重复权限请求或把该包当最终产品候选。证据build/tcc-chain-2n0505ky（chain.json及attribution.log/json）、installed-textedit-z9io4ah1/result.json。

### TextEdit基础提交与创建阶段恢复通过（2026-10-12，ADR-137/138）

字符和对应物理键码在旧顺序均得到原码wq加空格，测试宿主在运行。只改变顺序为先选择独有源再创建/首次激活文档，物理W/Q+空格正确提交“你”（build/installed-textedit-o667kaek）。驱动已固化这个顺序及仅允许W/Q的新键码；路径/窗口/前台/AX保护、源核对、原源/启用集合恢复及真实数据摘要保护保持。13项回归通过，包括选源先于创建、选择失败不创建文档、焦点失败停止后续键及恢复先于关闭。

固化驱动正常输入再次通过（build/installed-textedit-vn0hx0zp）；failure、INT、TERM分别在发键前注入，退出7/130/143且恢复通过（z6bq1iy3、4_2jkozt、u8v4mh1s，各scenario-result.json）。三条证明客户端创建阶段恢复，不能冒充组合中断验证。make verify零诊断/170产物通过。其他应用/聊天保护、组合中断及最终产品候选仍待推进，整卡不关闭。

### 输入前缀后的中断恢复（2026-10-12，ADR-139）

驱动增加--scenario normal/failure/INT/TERM。后三条在W/Q输入后、Space前核验独有文档文本wq，再注入退出7/130/143；不发送其他键，恢复源/启用集合和真实数据摘要，关闭独有文档。原生三条通过，证据build/installed-textedit-fak6mom7、pnb0o8l1、rn5vn9py/result.json。前缀校验仅证明受控输入存在，不等同marked range证明；完整预编辑协议仍待验。离线新增中断回归验证Q之后注入、无Space提交及恢复先于关闭，共14项相关回归通过；make verify零诊断/170产物通过。其他客户端/聊天和最终包验收未完成，整卡保持进行中。

### 固定TextEdit预编辑范围验证（2026-10-12，ADR-140）

自有TextEdit AXTextArea枚举发现AXTextInputMarkedRange。marked-range共享动作仅TextEdit可用，沿用同调用文件路径/窗口/前台/AX角色保护；wq后要求AppleScript端点1,2，提交“你”后要求2,1，缺失/不可读/不匹配失败。范围格式不当作CFRange location/length，也不读取未知用户文本。正常原生证据build/installed-textedit-0m2r8ohi；已核验预编辑范围时failure/INT/TERM分别rv2fun0q、l9th_ubb、8ab2cx2q，源/完整启用集合和真实数据摘要恢复、独有文档关闭。15项相关回归通过，新增不可读范围不提交的负向用例；make verify零诊断/170产物通过。固定TextEdit的预编辑/提交/中断恢复通过，不代表其他应用、所有预编辑协议或最终产品候选；整卡保持进行中。

2026-10-13（ADR-143/144）：Safari专用离线正文焦点、正常提交及前缀后failure/INT/TERM原生通过，源/启用集合/真实数据保持、自有窗口关闭；不等同Safari marked range或最终候选。Terminal非执行接收器已实现，四项PTY测试通过；原生窗口/TTY/进程绑定和实际输入仍待验。IT-01保持进行中。

2026-10-13（ADR-145/146）：Terminal授权后原生窗口/TTY/接收器PID完整命令绑定、stop/TTY恢复及精确关闭通过（terminal-ownership-ccynlyig）。Homebrew解释器启动器与Framework实际路径差异已修正并登记，5项回归通过；实际逐键焦点保护和输入仍待验，IT-01不关闭。

2026-10-13（ADR-147）：Terminal逐键同调用窗口/TTY/前台/AX/PID命令及输入源保护完成，正常提交和已确认wq前缀后的failure/INT/TERM恢复全通过（tp05x0d3、p93m28kf、5h66ex17、fyuau280）。真实数据/完整源集合/TTY恢复、自有窗口关闭；其他目标应用、安全聊天及最终候选覆盖待验，IT-01未关闭。

2026-10-16（ADR-194/报告043）：新增正式包独立账号数据边界检查，不修改宿主入口；当前日常账号被正确拒绝，未发键。仅账号路径前置，不等于正式IMK隔离、菜单动作保护或整卡通过。

- ADR-195/报告044：TextEdit+正式宿主候选/学习区按钮逐动作AX保护已实现，本地注入回归与原生拒绝路径验证；实际AX及完整四路径恢复仍待。系统菜单代理不在范围。用户已恢复推送、全绿后合入/公证，安装另行确认。

## 2026-10-19 A 机原生所有权复验（报告 097）

- `run-owned-probe.py normal|failure` 在 A（macOS 13.7.8）**首次真实 PASS**；`run-owned-library.py` 四路径 PASS；探针后 TextEdit 窗口 0。
- 修 `probe-owned-textedit.applescript`：macOS 13 关闭文档会销毁窗口对象，`visible of window id` 抛 `-1700`，
  先 `exists window id testID` 再判 `visible`（等待循环与最终断言都加），避免把成功关闭误判为清理失败。
- `make macos-offline-tests` 在 A 13/31 失败：Swift 5.8.1 不支持部分测试的异质字面量 + 高负载编译超时；Swift 侧门禁以 CI 为准。
- 仍未关闭：IMK 学习数据隔离、独有身份包注册/TIS 枚举、Safari/Terminal 协议、完整剪贴板与输入源实机证据、微信草稿（BLOCKED）。

## 2026-10-19 独有身份包注册与真实 IMK 验收（报告 099/100）

- **数据隔离（ADR-215）**：`LAMPYRIS_SUPPORT_DIR` 把已装宿主的数据根（config+词库）重定向到私有目录，真机验证通过（报告 098）；
  真实 IMK 验收因此可安全执行（报告 099：`wq→你`、`nihao→你好`、Esc、来源标注、状态芯片、配置热更新全 PASS，用户数据 SHA 未变）。
- **发键铁律**：每批 `typekeys`/`keymod` 前必须 `guard-focus.sh <目标>`；本轮曾因 QQ 抢前台出过事故（未发送），已整改并写进技能。
- **独有身份包注册**：软链方式 `lsregister` 失败 `-10811`（BLOCKED，副作用已清理）；**实体包方式 PASS**（2 个自有身份，清理后用户源集合不变）→ 后续走实体包。
- 工具修复：`isolated-imk/source-state.swift` 显式字典类型（Swift 5.8 可编）、`isolated-imk.py` 支持 `LAMPYRIS_IMK_TEST_OPT`。
- 仍未关闭：实体独有包安装/启用后的 `run-installed-textedit-probe.py`、Safari/Terminal 协议、完整剪贴板恢复、微信草稿（BLOCKED）。

## 2026-10-19 阶段结论（报告 099/100）

- 已完成：原生 TextEdit 所有权（normal/failure）、ADR-215 数据根隔离、已装正式包的真实 IMK 输入
  （`wq→你`/`nihao→你好`/Esc/来源标注/状态芯片/配置热更新）、独有身份实体包注册与枚举（2 个身份）。
- **BLOCKED（缺签名能力，转 IT-14）**：已装独有包 → `run-installed-textedit-probe.py`、
  Safari / Terminal 原生协议 —— 三者前置都是「已安装且 Developer ID 签名的独有隔离包」，
  A 机 `security find-identity` = 0 个身份、ad-hoc 包 `spctl` rejected 且不出现在系统设置「＋」列表。
- 未关闭原因：微信聊天隔离草稿仍 BLOCKED；完整剪贴板多类型恢复只有命名剪贴板与 mock 证据。
- 决策（用户 2026-10-19 同意）：这些原生协议项**不绕过、不作 PASS**，留到 IT-14 用最终签名包与签名能力补验。

## 2026-10-19 IT-14 前置：CI 签名隔离包（报告 102，进行中）

- `c60bd88` / ADR-216：隔离公证 CI 支持 `arch=arm64|x86_64|universal`、目标根放宽到设备系统临时目录；run `39269308347` 出
  **x86_64 + Notarized Developer ID** 的独有身份包（zip `d14a395b…`，Team `2N62934Y28`，`spctl` accepted），已装 A 并核对绑定/架构。
- **新发现的阻塞**：macOS 13 上新装第三方输入法需**一次重新登录**才被系统发现——系统设置「＋」与菜单都看不到，
  `TISSelectInputSource` 返回 `-50`、父源 `enabled` 仍 0（与 ADR-130/131 在 B 的现象一致）；停在登录前，不绕过。
- 重新登录后按 HANDOFF §4.1 添加源并跑 textedit/safari/terminal 四路径，再把本节 BLOCKED 改判；生产包与用户数据未受影响。

## 2026-10-21 固定开发身份（ADR-230 / 报告106）

新增macos-imk-dev初始化/校验换包与公证工作流development选项；长期私有根复用UUID与输入源声明，旧包可回退、数据保留，不自动切源/增删源。原生直接进程四退出路径及owner/权限拒绝通过，9项工具回归、41文件离线及make verify通过（3项沙箱失败正常权限补跑）。固定开发源尚未安装/启用；免注销真实输入及A/B验证待，整卡不关闭。105临时RC候选与生产包不变。

106当前补验：PR #56四门禁通过合入b652cd6，固定开发公证39527358251成功；B已装“萤火虫开发 d4fcecfb”，签名启动及同载荷包级替换/回退通过，生产三SHA/ABC/实际集合未变。实际尚未启用；等待首次添加后验证不同包免注销真实输入，不计同载荷交易为热更新通过。

106登录后补验：固定开发d4fcecfb父源/default实际启用；正常TextEdit wq→你/marked及恢复通过，failure在自有窗口创建守卫前停止无发键，INT/TERM/拼音/Esc未执行。用户要求清理的旧dce4ae25已撤销登记并可恢复归档，真实三SHA和启用集合保持；不同包免注销更新仍待。PR合并/签名构建被自动审批要求明确授权，未执行。
