# 106：固定身份 IMK 开发迭代

日期：2026-10-21。关联 IT-01、ADR-230；产品RC仍为3728dfc，本报告不是新RC验收。

## 当前状态（2026-10-21 PR #58 合入及新包换装后，以本节为准）

- **最新覆盖**：用户随后报告候选框显示时方向键仍会输入乱码；此前↓/空格局部通过不代表方向键整体已验。ADR-232复现并修复预览遗漏左/右等组合导航拦截，实际适配器回归修复前失败/修复后通过，完整冒烟与make verify通过；用户物理键复验及新签名包IMK验收尚待，发布阻断保持。见文末补记及T-ITER-24。

- PR #58 的 `247c444` 四项门禁通过后合入，`main` 为 `288c750`；同一固定根的 arm64 公证任务39532557520成功。ZIP SHA `daa077a4…f395a0f`，执行 SHA `be7deecf…78a68318`，包内源码标记 `288c750`。签名、Gatekeeper、stapler校验通过。
- 已在源启用期间换入不同执行SHA的新包，无移除/添加/注销。安装记录 `~/Library/Application Support/LampyrisIMKDev/lampyris-imk-d4fcecfb-af99-4b9a-a590-55fa99e16f05/replacement-7eurs9cz/installation.json` 显示当前源和实际启用集合前后相同；旧包留在同根 `replacement-7eurs9cz/previous.app`。这证明包已原位替换，不证明系统已装载新二进制。
- 随后系统加载了新宿主PID26819，`lsof`确认其文本可执行路径是当前安装包，执行SHA `be7deecf…78a68318`。重跑现有自有窗口探针通过：`wq` marked range `1, 2`，空格提交“你”，marked range清除；输入源及实际启用集合恢复，生产config/词库SHA仍 `3bc1117c…` / `74f76e92…`。证据 `platforms/macos/build/installed-textedit-uy16l3pt/result.json`。Computer Use确认原先“未命名”窗口保持原样。
- 新包的模式循环探针在创建可唯一识别的自有TextEdit窗口时停止（`BLOCKED 未取得自有空白窗口`），未发按键；当前ABC、实际启用集合和生产数据恢复。证据 `platforms/macos/build/installed-mode-fpvhla9z/`。因此模式切换、拼音/Esc仍未验证。此前AppleEvent超时和错用助手的尝试均保留为过程证据，不覆盖本次PASS。
- 之前固定包b652cd6的 `wq`→“你”结果仍作为单独历史证据（`installed-textedit-ol5y0d69`），新包有自己的独立PASS，二者不跨SHA继承。旧隔离包dce4ae25可恢复归档在 `packaging/out/retired-imk-dce4ae25-20261021/`。
- [机器证据](106-stable-imk-evidence.json)已同步。不同执行SHA的包替换和基本真实输入已通过；模式循环、拼音/Esc及完整候选一致性范围未证实。无需用户再次添加或注销，旧包回退副本继续保留。

## 2026-10-21 共享 TextEdit 夹具修正

- 复核发现共享 `owned-textedit.applescript` 在打开唯一临时文件前先执行 `make new document`。TextEdit 可能复用已有空白窗口，导致“新自有空白窗口”条件无法成立；同类历史问题在报告024中通过直接打开唯一文件解决。
- 按 ADR-091/092，将创建步骤改为直接打开 0600 唯一临时文件，继续验证唯一文档名、完整文件路径、可见窗口唯一性和窗口ID不属于原有集合；没有放宽所有权守卫。`osacompile`通过，`make verify`全绿。
- 用新脚本重跑模式探针时，系统自动化预检在创建文档前以 `System Events -10827` 拒绝，故未发键、未切换输入源；TIS只读状态仍为ABC，开发输入模式实际启用，生产配置/词库未变。证据目录 `platforms/macos/build/installed-mode-current-134728/`。随后尝试既有`source-state select-owned`时，TIS返回-50；当前ABC、开发模式项enabled/selectable但父源disabled。未切换源；临时唯一文件未输入并已关闭清理。夹具修复尚无本机运行证据，模式/拼音/Esc/候选一致性仍待验。
- 旧失败证据保留；下一步是先由用户在输入源菜单手动选中已启用的固定开发源；确认来源后再用 Computer Use 在唯一临时文档做人工输入验证，保持ABC可手动恢复。若要运行脚本探针，还需解决System Events `-10827`；不改TCC数据库、不绕过预检。

## 2026-10-21 用户切换后的人工原生补验

- 用户确认已切换开发源。在独有临时 TextEdit 文档通过 Computer Use 手工输入：`wq` 空格提交“你”；`nihao` 空格提交“你好”；重复 `nihao` 后 Esc 保持既有文本不变；退格删除末尾后重输并空格提交“你好”；`nihao` 按数字键 `1` 提交结果与空格提交相同。目标窗口截图未显示候选面板，故不能据此确认候选显示次序，也不能确认数字键提交与画面上指定候选逐项一致。
- `alt+m` 连续三次后，隔离开发根配置回读依次为 mixed→wubi→pinyin→mixed，输入文本未变化；这是模式切换的实际 UI 行为证据。独有临时文档关闭时选择“复原更改”，原“未命名”窗口保持存在；只删除本轮创建的临时文件和目录。
- TIS `source-state` 仍回读 `com.apple.keylayout.ABC`，与用户选择及实际热键行为不一致；不据此断言当前输入源，亦未再调用选源 API。开发包注册别名可执行 SHA 为 `be7deecf…78a68318`，匹配新包；本轮 HUD 宿主探针仍报告宿主未运行，故不把这些手工 UI 观察单独归因到已确认 PID。此前 PID 26819 加载该 SHA 的独立探针及 `wq→你` 证据仍有效。
- 生产执行/config/词库 SHA 仍为 `535d546f…` / `3bc1117c…` / `74f76e92…`。机器记录见同目录 JSON 的 `manual_computer_use_followup`。夹具本身的脚本模式探针仍被 `System Events -10827` 阻断；本次手工操作不解除该自动化权限阻塞。
- 当前补验将“基本五笔与拼音提交、取消/退格重输、模式热键循环”从未测提升为人工原生观察；候选面板可见性/排序、数字键与屏显候选一致性、重启后输入、应用兼容、A机、升级恢复以及完整RC验收仍未关闭。

## 2026-10-21 候选可见性补查与工作流复核

- 新一轮只读检查再次发现证据链不一致：TIS回读ABC、父输入源disabled而开发模式enabled/selectable；`lsof`显示PID 26819持有当前开发包精确可执行路径，但现有HUD探针通过`NSRunningApplication`按bundle查找时报告宿主未运行，`ps`读取被系统权限拦截。未调用选源API，不能据此判定当前客户端输入源或候选UI故障。
- `run-installed-hud-probe.py`把System Events预检、候选面板、HUD、外观与第二屏耦合；`-10827`会在创建/输入前阻断整组实验。故障定位：这是验收工具拆分和宿主识别缺口，不是已证实的产品缺陷。下一步应新增独立只读候选窗口枚举，按已登记包的精确可执行路径/PID核对宿主；保留既有焦点和资源所有权守卫。
- Computer Use在自建的未命名测试文稿中曾观察到`wq`+空格提交“你”，随后文稿已清空并选择删除；当前仅原有“未命名”窗口仍开着。该观察只证明该次提交可用，未捕获组合态候选列表。数字键与空格结果相同的先前手工观察，也因没有候选屏显项而不能证明候选序号一致。没有新的排序PASS。
- 流程审查已更新[开发工作流](../开发工作流.md)：按UI快照→隔离预览→固定身份IMK→最终RC分层；只有IMK层验证才换开发包，开发和RC证据各自绑定SHA/环境；单人日常内环先跑`make fast`和定向检查，再按提交门禁跑`make verify`。修复候选探针后再继续实机输入验证，避免权限/第二屏/HUD条件挡住候选核心证据。

## 2026-10-21 方向键候选浏览实现（新源码，未装机）

- 复核ADR-151后确认其只消费四方向来保护预编辑；上/下候选浏览没有实现。按ADR-231补齐当前页候选焦点：上下移动、页边界停留、翻页回首项、空格确认焦点，数字/鼠标维持立即提交；候选窗显示选中高亮和操作提示。左右/Home/End/前向Delete的既有预编辑保护不变。
- 定向离屏候选测试通过（含边界、可访问性焦点标签及焦点序号提交映射）；独立预览 `-warnings-as-errors` 构建通过；IMK controller 集成离线回归正常权限复跑通过；`make verify`全绿。
- 全量 `make macos-offline-tests`仍有一项 `test-tools-presentation.py` 命名私有剪贴板复制断言失败，换用全新`/private/tmp`输出目录仍复现；controller 与 Swift ModuleCache 两项初次失败在正常权限复跑通过。剪贴板断言作为独立离线回归问题跟进，不记全绿。
- Computer Use打开独立预览请求超时，随后回读应用清单显示LampyrisPreview运行中但AX访问返回`-10005`；未向预览或其他应用发键，故没有新增可视候选/箭头交互证据。
- 此变更尚未重建、签名或安装候选包。报告106早前的实机证据绑定旧执行SHA，不能证明新导航行为；固定开发包候选实际行为需同一新SHA原生复验后再更新结论。

## 签名包安装历史

- PR [#56](https://github.com/EasyIndie/EasyInputMethod/pull/56)最新59ee533四门禁全通过（CI39526751254），合入main **b652cd6**。固定开发公证任务 [39527358251](https://github.com/EasyIndie/EasyInputMethod/actions/runs/39527358251)成功；[机器证据](106-stable-imk-evidence.json)绑定源码、zip/执行SHA、设备与未验项。
- B固定身份包已由 `288c750` 替换；旧 `b652cd6` 包留在上述previous.app。新包严格签名、项目Developer ID、Gatekeeper、公证票据和源码绑定核验通过；对新执行SHA的客户端输入仍未证实。
- 使用同一签名载荷实际完成安装→替换→previous.app回退，三次实际源集合均与开始相同，数据保留。这只证明未启用时的包级交易，不证明不同版本热更新或客户端输入。证据 `platforms/macos/build/stable-imk-dev/signed-install.log`、`signed-replace.log`、`signed-rollback.log`、`signed-native.json`。
- 固定开发父源及模式实际启用，当前ABC。实际启用集合由 `dev-state.swift` 的 `includeAllInstalled=false` 读取；安装前后集合一致。
- 私有测试词已经FFI删除，私有mode恢复mixed；生产执行/config/词库三SHA仍与105一致，生产宿主未运行。未改旧105候选。
- **下一步**：保持ABC和新包；解决TextEdit窗口复用/所有权识别导致的现有探针BLOCKED后，再跑模式、拼音/Esc及候选数字提交矩阵；只使用自有窗口，不关闭身份不明窗口。A机另初始化其独有长期根。调试附加与正式RC门禁仍待。

## 首次添加界面实查（后续补验）

用户报告找不到后，以Computer Use打开系统设置→键盘→文字输入→编辑→添加。简体中文右侧及搜索“萤火虫”均只显示正式“萤火虫”，没有“萤火虫开发 d4fcecfb”。未点击添加/移除，取消搜索对话框并返回键盘面板，设置未变。

同轮严格签名、Gatekeeper Notarized Developer ID及stapler再次通过；执行SHA仍cda17638…，TIS全目录仍枚举正确开发名称/身份，实际启用列表无开发源、当前ABC；真实config3bc1117c…和词库74f76e92…未变。只证明添加界面尚未发现，不把目录default.enabled=true当启用；也不能唯一归因具体缓存组件。下一步保存工作后手动注销重登，复查同一已装身份，不重新生成UUID、不清系统缓存。首次发现仍BLOCKED，后续同身份免注销更新未开始。

## 官方依据与边界

[Apple DTS于2026年6月的回复](https://developer.apple.com/forums/thread/775526)确认系统设置发现新输入源暂无已知免注销方法，反馈FB23026482。不能由此推断每次同身份二进制更新都必须注销，也不能保证同身份更新一定免注销。

[Xcode官方支持附加运行进程](https://developer.apple.com/documentation/xcode/diagnosing-and-resolving-bugs-in-your-running-app)，但调试签名权限与正式Developer ID包不同；本次不为公证包开启get-task-allow。性能采样应单独记录有无调试器，不把断点下的耗时计入16ms门槛。

## 使用流程

日常引擎、候选UI和菜单先用 `make macos-dev`，无需登记输入源。只有IMK调度/预编辑/跨应用验证才进入长期开发源。

```sh
# 每台设备一次；再次调用返回原UUID，不创建新身份。
make macos-imk-dev ACTION=init
# 复制此命令输出的绝对根，提交给main上的公证工作流：
python3 scripts/macos-imk-dev.py root

gh workflow run isolated-imk-notary.yml --ref main \
  -f development=true -f arch=arm64 \
  -f target_root="$(python3 scripts/macos-imk-dev.py root)"
# A机将arch改为x86_64；下载解压工作流产物，不修改签名资源。

make macos-imk-dev ACTION=install APP="/绝对路径/Lampyris.app" ARGS=--stop-host
```

开发根固定为 `~/Library/Application Support/LampyrisIMKDev/lampyris-imk-<UUID>`。其owner是所有权声明，不是第二配置；config.toml仍经ime-config，个人词库仍用既有API。根/owner为0700/0600，生产Lampyris根不动。

首次安装后，用户手动添加“萤火虫开发 <UUID前8位>”；若系统未发现，保存工作后手动注销一次。每次换包前结束组合并切到ABC，工具不自动切源、增删源、改系统缓存或注销。`--stop-host`只停止精确开发包可执行路径对应的进程；有其他持有者或启动竞态则拒绝换包。签名、项目Team、Gatekeeper、公证票据、完整输入源声明和数据根均校验。

旧包保留在开发根的 `replacement-*/previous.app`，换包失败自动回放；成功后保留供回退。主动回退可把该previous.app作为同一install命令的APP，仍须通过全部校验。备份不放在Input Methods中，避免额外登记副本。每次记录installation.json中的执行SHA、源码提交、换包前后当前源及实际启用集合；数据不清空。此工具不把包级成功标为真实输入成功。

## 必须补的原生实验

1. 首次启用后记录实际源集合、当前源、宿主PID/执行SHA，使用已有自有窗口/逐批焦点协议验证wq→你、nihao→你好及Esc。
2. 切ABC，构建同一根的新包并换包；不移除/添加、不注销，确认新PID/新执行SHA，重复输入。比较启用集合及真实生产数据摘要。
3. 以previous.app回退并验证，再做失败/中断恢复。A/B独立记录，不能跨机继承。
4. 若旧菜单或旧宿主仍缓存，不杀系统服务、不清系统偏好，记录失败并使用既有移除/添加或注销路径。

长期开发源可变，不能代替不可变RC、正式安装升级、首次登记、独立重建及五日试用。现有UUID临时候选不迁移、不移除，105等待用户添加的候选仍保留。

## 工程验证历史（签名包安装前）

- 本地arm64/macOS27.0.1：固定开发根原生normal/failure/INT/TERM退出0/7/-2/-15；错误owner及过宽权限均拒绝exit3。证据 `platforms/macos/build/stable-imk-dev/native-final.json`。这是自建ad-hoc隔离宿主直接进程验证，不是系统IMK客户端输入。
- 新9项开发工具回归覆盖固定身份、真实数据目录不创建、符号链接/宽权限/多根拒绝、开发源正在使用时零换包/零停止、路径不符零信号、保留数据/旧包、登记声明变化拒绝、并发换包零修改、最终校验失败回滚。现有隔离6项、CI根/架构4项通过。
- 完整离线41文件187项：38文件首次通过，3项系统服务沙箱失败后正常权限重跑通过；原始失败保留于 `/private/tmp/lampyris-dev-offline.log`，不删去失败历史。actionlint与make verify零诊断通过（`/private/tmp/lampyris-dev-final-verify.log`）。
- 本机固定根 `LampyrisIMKDev/lampyris-imk-d4fcecfb-af99-4b9a-a590-55fa99e16f05` 已初始化，重复调用不换UUID；测试词已通过FFI移除，私有mode恢复mixed。未安装/登记/启用开发源，无真实客户端发键。
- 生产执行535d546f…、config3bc1117c…、词库74f76e92…与105一致；实际当前ABC，启用集合未变。
- 未决：main公证开发包、首次发现/添加、同身份不同执行SHA的免注销换包、旧包回退、A/B真实客户端及调试器附加。仅前置通过，不把脚本/mock/直接进程测试计为以上原生通过。

补充原生证据：精确路径自建宿主停止通过；ad-hoc包被Developer ID门禁拒绝、未安装。换包持有owner文件的排他锁，并发调用在修改前拒绝；失败不会移动不是本次安装产生的目标包。

## 2026-10-21 预览交互复验与数据恢复

- Computer Use重试后打开已构建的`LampyrisPreview.app`，`wq`组合按↓仍保持预编辑，随后空格提交第二项“像”并清空组合。该结果支持预览路径的候选焦点/空格映射工作；AX树和截图均未包含浮动候选面板，因此没有候选列表或高亮的直接视觉证据，也不是新签名包/系统IMK证据。
- 该次直接启动独立预览包，绕过`make macos-dev`创建的私有数据根。预览使用真实`~/Library/Application Support/Lampyris`，主动选择曾短暂写入个人词库行`wubi / wqje / 像 / 1`。随后调用既有FFI词库删除API仅移除该行；回读个人词库SHA `74f76e92a6cab0eb312d73a4eec575e8d17a9d919a47630bbde0a2f827da7137`、492字节，与测试前基线完全一致；config SHA `3bc1117cc3379a4c6a100bc6d2cf3ddd3bfa37a25739437a32087a87935c7550`未变。预览已关闭。
- 流程修正：禁止通过Launch Services、Finder或Computer Use应用清单直接启动构建产物`LampyrisPreview.app`；交互预览只经`make macos-dev`或明确隔离的验收包装器。已在`docs/开发工作流.md`记录此边界。实机同SHA候选窗显示、高亮、数字/鼠标选择及提交一致性仍待固定开发包验收。

## 2026-10-21 用户方向键乱码反馈与预览修复

- 用户实测报告候选框出现后按方向键有乱码，已确认发生在预览输入区的左/右键，上/下可以切换。新回归直接调用`PreviewInput.keyDown`，旧实现左方向键123失败，证明预览左/右导航专用字符可污染组合或文本；仅测共享导航判断函数遗漏了实际接线缺口。正式IMK控制器已有相同守卫，此处不据源码判断宣布其物理键场景通过。
- 按ADR-232在预览↑↓浏览之后、字符解析之前调用共享组合导航守卫；7个导航键×3种字符表示均检验完整文本、组合和空格确认项。原实现正常权限运行exit1，修复后完整冒烟exit0；strict Swift构建及make verify全绿。初次沙箱执行exit134单独保留。证据目录`platforms/macos/build/acceptance-arrow-232/`，含修复diff和前后日志。
- 先前交互预览未显示问题不构成该用户报告的反证；修复后的物理键交互、实际候选高亮及同SHA系统IMK提交仍待复验，发布阻断不关闭。
